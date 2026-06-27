#!/usr/bin/env bash
# watch-coordination.sh — Directory-based, identity-aware, echo-and-terminate watcher.
#
# USAGE:
#   ./watch-coordination.sh --identity <id> --role orchestrator|implementer --dir <coord-dir>
#
# ARGUMENTS:
#   --identity <id>   This instance's stable ID (e.g. "orchestrator", "impl-alpha").
#                     The instance's presence file is <coord-dir>/<id>.md.
#   --role <role>     orchestrator  → watches ALL .md files in <coord-dir> EXCEPT its own (hub).
#                     implementer   → watches ONLY orchestrator.md (spoke).
#   --dir <coord-dir> Path to the shared coordination directory.
#
# ORCHESTRATOR IDENTIFICATION (the convention this script enforces):
#   The Orchestrator's identity MUST be the literal string "orchestrator".
#   Its file is therefore always <coord-dir>/orchestrator.md.
#   This is a hard convention — not scanned for, not discovered. Simple and unambiguous.
#   An Implementer watches exactly one file: <coord-dir>/orchestrator.md.
#   If that file does not exist when the Implementer starts, the watcher waits up to 5 min.
#
# HOW IT WORKS:
#   1. Self-registers: writes PID to <coord-dir>/.watch-state/<id>/watcher.pid (sole
#      writer — no race with heartbeat). Ensures <id>.md exists; NEVER rewrites it
#      (<id>.md is append-only; heartbeat is the sole appender of HEARTBEAT markers).
#   2. Builds the watch-set by role (STAR topology — structural self-filter; never self-trip).
#   3. Snapshots each watched file: byte-size (from stable state or current EOF on
#      first arm — FIX 1) + mtime (temp cache, for change-detection within this run).
#   4. Polls every 20s (cap ~6h = 1080 iterations).
#   5. On a FILE SIZE CHANGE: computes the delta (newly appended or shrunk bytes).
#      Size-unchanged / mtime-changed events are silently absorbed — append-only
#      grammar means a real new message always grows the file (FIX 2).
#   5.5 ADDRESSING FILTER: scans the delta for message-header lines matching
#       "→ <IDENTITY>" or "→ ALL" (tolerant ERE — optional whitespace, em-dash or
#       hyphen; grammar: ### <UTC> — <FROM> → <TO> — <TAG>; FIX 3).
#       Wakes ONLY when at least one such line is found, OR the file was deleted.
#       Changes addressed to others are silently absorbed. Essential for N-spoke
#       sessions (all spokes watch the same hub file).
#   6. On a relevant change: persists read-time EOF to stable state (FIX 1 refinement),
#      echoes the delta, prints a re-arm command, exits 0. The agent acts, then re-arms.
#
# IDENTITY RE-ARMING: SIG_DIR (mtime cache) is deterministic under STATE_DIR and
#   cleaned at arm start — no mktemp orphan if the previous run was SIGKILLed.
#   Byte-sizes are persisted in <coord-dir>/.watch-state/<identity>/<basename>.size
#   so a re-arm under the SAME identity resumes from the last-processed offset —
#   gap messages from the exit→re-arm window are caught on the first poll (FIX 1).
#   Re-arming under a NEW identity (e.g. after bootstrap adoption) starts a fresh
#   baseline: the new identity's state directory is empty on first use.
#
# RULES (enforce via the header comment — agents read this):
#   M2 — NEVER `pkill -f` on a shared machine (kills the peer's loop).
#          To stop THIS watcher:
#            kill $(cat <coord-dir>/.watch-state/<id>/watcher.pid)
#          To stop the heartbeat:
#            kill $(cat <coord-dir>/.watch-state/<id>/heartbeat.pid)
#   M3 — Signatures = byte-size + mtime. mtime alone breaks under sandbox clock skew;
#          size catches content growth even when mtime is wrong.
#   M4 — After writing the PID file, read it back to confirm it persisted.
#   M1 — Re-arm request is self-varying: the delta content is always unique.
#
# TOOL BACKGROUND (required):
#   Run via the Bash tool with run_in_background=true.
#   NEVER use shell `&` or `disown` — orphans the process (silent stall; no harness visibility).

set -uo pipefail
# Note: we do NOT use `set -e`. Several read operations intentionally tolerate failure
# (e.g. grep returning 1 for no match, stat on a just-deleted file). We handle errors
# explicitly at each callsite rather than relying on automatic exit.

# ── constants ─────────────────────────────────────────────────────────────────

readonly POLL_INTERVAL=20       # seconds between polls
readonly MAX_POLL=1080           # ~6h cap (1080 × 20s = 21600s)
readonly ORCH_WAIT_MAX=300       # seconds an implementer waits for orchestrator.md to appear
readonly ORCH_ID="orchestrator"  # HARD CONVENTION — the Orchestrator's identity is always this

# ── argument parsing ──────────────────────────────────────────────────────────

IDENTITY=""
ROLE=""
COORD_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity) IDENTITY="$2"; shift 2 ;;
    --role)     ROLE="$2";     shift 2 ;;
    --dir)      COORD_DIR="$2"; shift 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$IDENTITY" || -z "$ROLE" || -z "$COORD_DIR" ]]; then
  echo "ERROR: --identity, --role, and --dir are all required." >&2
  echo "Usage: $0 --identity <id> --role orchestrator|implementer --dir <coord-dir>" >&2
  exit 1
fi

if [[ "$ROLE" != "orchestrator" && "$ROLE" != "implementer" ]]; then
  echo "ERROR: --role must be 'orchestrator' or 'implementer'." >&2
  exit 1
fi

# CRITICAL: identity charset assertion — IDENTITY is interpolated raw into grep -E patterns
# (addressing filter, delta_addressed_to_me). A metachar in the id (e.g. "feature/auth[2]",
# ".*") makes grep error or silently mis-behave: all messages are absorbed, watcher never wakes.
if [[ ! "$IDENTITY" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: identity '${IDENTITY}' contains characters outside [A-Za-z0-9._-]." >&2
  echo "Identity strings are interpolated into grep -E patterns; metacharacters cause silent mis-match." >&2
  echo "Rename to letters, digits, dots, underscores, and dashes (e.g. 'impl-alpha', not 'feature/auth[2]')." >&2
  exit 1
fi

if [[ "$ROLE" == "orchestrator" && "$IDENTITY" != "$ORCH_ID" ]]; then
  echo "ERROR: Orchestrator's --identity must be '$ORCH_ID' (hard convention)." >&2
  exit 1
fi

MY_FILE="$COORD_DIR/$IDENTITY.md"
ORCH_FILE="$COORD_DIR/$ORCH_ID.md"
STATE_DIR="$COORD_DIR/.watch-state/$IDENTITY"   # stable size-state, survives re-arm (FIX 1)
WATCHER_PID_FILE="$STATE_DIR/watcher.pid"        # sole-writer PID file (no race with heartbeat)

# Absolute path of this script — safe for re-arm regardless of caller cwd.
SCRIPT_ABS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"

# Create directories early — stat probe below needs $COORD_DIR to exist.
mkdir -p "$COORD_DIR"
mkdir -p "$STATE_DIR" || { echo "FATAL: cannot create state dir $STATE_DIR" >&2; exit 1; }

# ── mtime utility (portable: macOS + Linux) ───────────────────────────────────
# Probe $COORD_DIR rather than $0 to handle split-filesystem edge cases where the
# script and the coord-dir live on filesystems with different stat flavors.

_STAT_CMD=""
if stat -f "%m" "$COORD_DIR" >/dev/null 2>&1; then
  _STAT_CMD="bsd"   # macOS / BSD stat: stat -f "%m" <file>
elif stat -c "%Y" "$COORD_DIR" >/dev/null 2>&1; then
  _STAT_CMD="gnu"   # Linux / GNU stat: stat -c "%Y" <file>
else
  _STAT_CMD="none"  # No stat; fall back to python3 / perl
fi

file_mtime() {
  # Returns integer Unix mtime of $1, or 0 on failure. Never exits on error.
  local f="$1"
  [[ -f "$f" ]] || { echo 0; return; }
  case "$_STAT_CMD" in
    bsd)  stat -f "%m" "$f" 2>/dev/null || echo 0 ;;
    gnu)  stat -c "%Y" "$f" 2>/dev/null || echo 0 ;;
    none)
      if command -v python3 >/dev/null 2>&1; then
        python3 -c "import os,sys; print(int(os.stat(sys.argv[1]).st_mtime))" "$f" 2>/dev/null || echo 0
      elif command -v perl >/dev/null 2>&1; then
        perl -e "print((stat(shift))[9]//0)" -- "$f" 2>/dev/null || echo 0
      else
        echo 0
        echo "WARN: cannot read mtime (no stat/python3/perl) — size-only detection active." >&2
      fi
      ;;
  esac
}

file_size() {
  # Returns byte count of $1, or 0 on failure.
  [[ -f "$1" ]] || { echo 0; return; }
  wc -c < "$1" 2>/dev/null | tr -d ' ' || echo 0
}

# ── signature store (per-arm mtime cache; deterministic location) ─────────────
# SIG_DIR lives under STATE_DIR so it's always co-located with stable state.
# Cleaned at arm start: any orphan from a SIGKILL'd previous run is wiped before
# the new arm builds its fresh mtime baseline. No EXIT trap needed.

SIG_DIR="$STATE_DIR/sigs"
rm -rf "$SIG_DIR"
mkdir -p "$SIG_DIR" || { echo "FATAL: cannot create sig dir $SIG_DIR" >&2; exit 1; }

# Signature key: basename of the watched file (files in coord-dir have unique basenames).
sig_key() { basename "$1"; }

read_sig() {
  # Returns "SIZE MTIME" for file $1. Default: "0 0" if not yet stored.
  local key; key=$(sig_key "$1")
  cat "$SIG_DIR/$key" 2>/dev/null || echo "0 0"
}

write_sig() {
  # Stores "SIZE MTIME" for file $1.
  local key; key=$(sig_key "$1")
  printf '%s %s\n' "$2" "$3" > "$SIG_DIR/$key"
}

# ── stable state store (FIX 1: survives re-arm) ──────────────────────────────
# SIG_DIR (mtime cache) is cleaned on every arm. STATE_DIR persists the last-processed
# byte-size per watched file across re-arms. A re-armed watcher resumes from the
# correct offset — gap messages from the exit→re-arm window are caught on first poll.

state_file_for() {
  printf '%s/%s.size' "$STATE_DIR" "$(basename "$1")"
}

read_persisted_size() {
  # Returns last-processed byte-size for file $1, or -1 if no state exists (first arm).
  local sf; sf=$(state_file_for "$1")
  [[ -f "$sf" ]] && cat "$sf" 2>/dev/null || echo -1
}

write_persisted_size() {
  # Atomically persists the new byte-size for file $1 to stable state.
  local sf; sf=$(state_file_for "$1")
  local tmp; tmp=$(mktemp "$sf.XXXXXX")
  printf '%s\n' "$2" > "$tmp"
  mv "$tmp" "$sf"
}

# ── addressing filter ─────────────────────────────────────────────────────────

delta_addressed_to_me() {
  # Returns 0 (true) if the pre-captured delta $1 contains a message-header line
  # addressed to $IDENTITY or to the broadcast token ALL.
  #
  # Item 15: caller captures the delta bytes ONCE and passes them here.
  # This function does NO file I/O — it only checks the addressing filter.
  # Eliminates the double-read race where a sibling's later bytes leaked into the
  # display delta when the file was re-read between the filter check and the echo.
  #
  # Grammar: ### <UTC ISO 8601> — <FROM> → <TO> — <emoji TAG>
  # Accepts both canonical Unicode headers and ASCII-typed equivalents:
  #   Arrow: → (U+2192) OR ->
  #   Dash:  — (U+2014) OR --
  # Anchored on the TO field: cannot match the FROM position or → other-id —.
  # IDENTITY contains only [a-zA-Z0-9_-] — no regex metachar escaping needed.
  #
  # Arguments: $1=captured_delta (string, may be multi-line)
  printf '%s\n' "$1" | \
    grep -qE "(→|->)[[:space:]]*(${IDENTITY}|ALL)[[:space:]]*(—|--)" 2>/dev/null
}

# ── self-registration: PID file + ensure presence file ───────────────────────
# PIDs live in sole-writer files under .watch-state/ — not in <id>.md.
# This eliminates the write race between watcher and heartbeat (each instance
# is the exclusive writer of its own PID file; <id>.md stays append-only).

printf '%s\n' "$$" > "$WATCHER_PID_FILE"

# M4: confirm PID file persisted.
if ! grep -q "^$$" "$WATCHER_PID_FILE" 2>/dev/null; then
  echo "FATAL: watcher PID write did not persist: $WATCHER_PID_FILE" >&2
  exit 1
fi

# Ensure presence file exists. Create with header ONLY IF ABSENT.
# Never rewrite — <id>.md is append-only after this point.
if [[ ! -f "$MY_FILE" ]]; then
  printf '# Presence: %s\nrole: %s\nstate: Active\nstarted_at: %s\n' \
    "$IDENTITY" "$ROLE" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$MY_FILE"
  if [[ ! -f "$MY_FILE" ]]; then
    echo "FATAL: could not create presence file: $MY_FILE" >&2
    exit 1
  fi
fi

# ── watch-set builder ─────────────────────────────────────────────────────────

build_watch_set() {
  # Prints one file path per line (sorted, LC_ALL=C for determinism).
  if [[ "$ROLE" == "orchestrator" ]]; then
    # Hub: all .md files in coord-dir EXCEPT own.
    find "$COORD_DIR" -maxdepth 1 -name "*.md" ! -name "$IDENTITY.md" -type f \
      | LC_ALL=C sort
  else
    # Spoke: ONLY the Orchestrator's file.
    if [[ -f "$ORCH_FILE" ]]; then
      echo "$ORCH_FILE"
    fi
    # If it doesn't exist yet, return empty; the wait loop below handles it.
  fi
}

# ── implementer startup: wait for orchestrator.md ─────────────────────────────

if [[ "$ROLE" == "implementer" ]]; then
  waited=0
  while [[ ! -f "$ORCH_FILE" ]]; do
    if [[ $waited -ge $ORCH_WAIT_MAX ]]; then
      echo "ERROR: orchestrator.md not found in $COORD_DIR after ${ORCH_WAIT_MAX}s." >&2
      echo "The Orchestrator must arm first (or supply the correct --dir path)." >&2
      exit 1
    fi
    echo "[watch] Waiting for $ORCH_FILE to appear... (${waited}s elapsed)"
    sleep 10
    waited=$((waited + 10))
  done
fi

# ── initial snapshot ──────────────────────────────────────────────────────────
# FIX 1: First arm  → baseline = current EOF (no history replay).
#         Re-arm    → baseline = persisted size (gap messages caught on first poll).

while IFS= read -r f; do
  [[ -n "$f" && -f "$f" ]] || continue
  persisted=$(read_persisted_size "$f")
  if [[ "$persisted" == "-1" ]]; then
    # First arm: baseline at current EOF — do not replay history.
    sz=$(file_size "$f")
    write_persisted_size "$f" "$sz"
  else
    # Re-arm: resume from last-processed byte-offset.
    sz="$persisted"
  fi
  mt=$(file_mtime "$f")
  write_sig "$f" "$sz" "$mt"
done < <(build_watch_set)

echo "[watch] $IDENTITY (role=$ROLE) armed at $(date -u +"%Y-%m-%dT%H:%M:%SZ")."
echo "[watch] PID $$ → $WATCHER_PID_FILE"
echo "[watch] To stop (M2): kill \$(cat $WATCHER_PID_FILE)"
echo "[watch] Polling every ${POLL_INTERVAL}s. Cap: $MAX_POLL iterations (~6h)."
if [[ "$ROLE" == "implementer" ]]; then
  echo "[watch] Watching: $ORCH_FILE"
else
  echo "[watch] Watching: all .md files in $COORD_DIR except $MY_FILE"
fi

# ── poll loop ─────────────────────────────────────────────────────────────────

iteration=0

while [[ $iteration -lt $MAX_POLL ]]; do
  sleep "$POLL_INTERVAL"
  iteration=$((iteration + 1))

  # Parallel arrays: path-safe (no colon parsing — paths may contain colons).
  # RF_PREV sentinel "DELETED" distinguishes deletion from content changes.
  # RF_DELTA holds the exact bytes captured at detection time (item 15: single read).
  RF_PATH=()
  RF_PREV=()
  RF_CURR=()
  RF_DELTA=()
  ABSORBED=0

  # ── change detection: iterate current watch-set ───────────────────────────────
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue

    if [[ ! -f "$f" ]]; then
      # Race-window departure: file was returned by find but vanished before we
      # reached it. Remove its state file and emit now. The departure scan below
      # skips any file whose state file was already removed — no double-emit.
      sf=$(state_file_for "$f")
      if [[ -f "$sf" ]]; then
        RF_PATH+=("$f"); RF_PREV+=("DELETED"); RF_CURR+=("DELETED"); RF_DELTA+=("")
        write_sig "$f" "0" "0"
        rm -f "$sf" 2>/dev/null || true
      fi
      continue
    fi

    curr_sz=$(file_size "$f")
    curr_mt=$(file_mtime "$f")
    prev_sz=$(read_sig "$f" | cut -d' ' -f1)
    prev_mt=$(read_sig "$f" | cut -d' ' -f2)

    if [[ "$curr_sz" != "$prev_sz" ]]; then
      # Size changed: real content change (append or shrink).

      # Item 15: capture delta ONCE here — do NOT re-read the file in the display
      # loop. Eliminates the double-read race where a sibling's bytes appended
      # between this read and the display read leaked into the agent's echo.
      if [[ $curr_sz -gt $prev_sz ]]; then
        captured_delta=$(tail -c +"$((prev_sz + 1))" "$f" 2>/dev/null || true)
      else
        # File shrank (archive rotation): full current content.
        captured_delta=$(cat "$f" 2>/dev/null || true)
      fi
      # FIX 1 refinement: capture read-time EOF immediately after reading.
      capture_end_sz=$(file_size "$f")

      write_sig "$f" "$curr_sz" "$curr_mt"
      write_persisted_size "$f" "$capture_end_sz"   # Persist read-time EOF; before exit.

      # Addressing filter: pass pre-captured delta (no second file read).
      if delta_addressed_to_me "$captured_delta"; then
        RF_PATH+=("$f"); RF_PREV+=("$prev_sz"); RF_CURR+=("$curr_sz")
        RF_DELTA+=("$captured_delta")
      else
        ABSORBED=$((ABSORBED + 1))
      fi
    elif [[ "$curr_mt" != "$prev_mt" ]]; then
      # FIX 2: mtime changed but size unchanged. Not a message change — append-only
      # grammar means a real new message always grows the file. Silently update the
      # mtime baseline and continue. (In-place edits of message bodies unsupported.)
      write_sig "$f" "$curr_sz" "$curr_mt"
    fi
  done < <(build_watch_set)

  # ── departure detection: scan known-set for files gone between polls ──────────
  # build_watch_set uses `find -type f` and never returns deleted files — a peer
  # deleted between polls is silently absent from the find output and would never
  # be detected without this second loop.
  # Placed AFTER the find-loop: any STATE file still present here was absent for
  # the entire poll window (real departure). The find-loop's race-window branch
  # above removes STATE files for TOCTOU-window departures, so no de-dup needed.
  for sf in "$STATE_DIR"/*.size; do
    [[ -f "$sf" ]] || continue   # glob may expand to literal "*.size" if dir is empty
    bn="${sf##*/}"; bn="${bn%.size}"   # "impl-alpha.md.size" → "impl-alpha.md"
    f="$COORD_DIR/$bn"
    if [[ ! -f "$f" ]]; then
      RF_PATH+=("$f"); RF_PREV+=("DELETED"); RF_CURR+=("DELETED"); RF_DELTA+=("")
      write_sig "$f" "0" "0"
      rm -f "$sf" 2>/dev/null || true   # clear state; reappearance = first arm
    fi
  done

  if [[ $ABSORBED -gt 0 ]]; then
    echo "[watch] Iteration $iteration: absorbed $ABSORBED change(s) not addressed to '$IDENTITY' — continuing poll."
  fi

  [[ ${#RF_PATH[@]} -eq 0 ]] && continue

  # ── relevant change detected — echo and exit ──────────────────────────────

  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  echo ""
  printf '=%.0s' {1..60}; echo
  echo "WATCHER: CHANGE DETECTED"
  echo "Time:     $TIMESTAMP"
  echo "Instance: $IDENTITY (role=$ROLE, iteration=$iteration/$MAX_POLL)"
  printf '=%.0s' {1..60}; echo
  echo ""

  for i in "${!RF_PATH[@]}"; do
    f="${RF_PATH[$i]}"
    prev_sz="${RF_PREV[$i]}"
    curr_sz="${RF_CURR[$i]}"
    captured_delta="${RF_DELTA[$i]}"

    echo "--- $f ---"

    if [[ "$prev_sz" == "DELETED" ]]; then
      echo "(file was deleted or archived)"
      echo ""
      continue
    fi

    if [[ $curr_sz -gt $prev_sz ]]; then
      echo "(grew ${prev_sz}→${curr_sz} bytes; showing new content:)"
      echo ""
      # Item 15: use pre-captured bytes — no second file read, no sibling leak.
      printf '%s\n' "$captured_delta"
    elif [[ $curr_sz -lt $prev_sz ]]; then
      echo "(SHRANK ${prev_sz}→${curr_sz} bytes — possible archive rotation; showing full content:)"
      echo ""
      printf '%s\n' "$captured_delta"
    fi
    # FIX 1 refinement is handled in detection (capture_end_sz persisted above).
    # Same-size entries never reach here (FIX 2 absorbs them before RF_PATH).
    echo ""
  done

  # Re-arm instruction (M1: unique because the delta context above varies every time).
  printf '=%.0s' {1..60}; echo
  echo "ACTION: RE-ARM WATCHER after acting on the delta above."
  echo ""
  echo "  $SCRIPT_ABS --identity $IDENTITY --role $ROLE --dir $COORD_DIR"
  echo ""
  printf '=%.0s' {1..60}; echo

  exit 0
done

# ── cap reached ───────────────────────────────────────────────────────────────

echo ""
echo "WATCHER: CAP REACHED (~6h, $MAX_POLL iterations). No changes in this window."
echo "Re-arm to continue:"
echo ""
echo "  $SCRIPT_ABS --identity $IDENTITY --role $ROLE --dir $COORD_DIR"
exit 0
