#!/usr/bin/env bash
# heartbeat.sh — Idle-poke + Orchestrator discover-on-idle trigger.
#
# USAGE:
#   ./heartbeat.sh --identity <id> --role orchestrator|implementer --dir <coord-dir> \
#                  [--idle-threshold <secs>] [--cadence <secs>]
#
# PURPOSE:
#   Runs as a SEPARATE background process from watch-coordination.sh.
#   Three duties:
#
#   1. IDLE-POKE (all instances): if this instance's own file has not been modified
#      for >= IDLE_THRESHOLD seconds, append a timestamped 💓 HEARTBEAT entry to it.
#      The timestamp makes every HEARTBEAT unique → trips the peer's watcher (STAR topology)
#      AND satisfies the self-varying-prompt rule (M1) — the content is always different.
#
#   2. DISCOVER-ON-IDLE (Orchestrator only): when the heartbeat fires AND the queue is
#      below DEPTH_FLOOR buildable contracts, print a DISCOVERY PASS NEEDED signal.
#      This replaces the old cron job — discovery duty folds into the heartbeat wake.
#      The agent sees the signal in the background output and runs the M5 6-lens pass.
#
#   3. WATCHER DEAD-MAN SWITCH (all instances): each cadence tick, verify the sibling
#      watch-coordination.sh process is still alive. The heartbeat has no value if the
#      watcher is dead — and a backgrounded process can only wake its agent session by
#      terminating. (Human-directed 2026-07-04.)
#
#      WHY SUSTAINED, NOT SINGLE-TICK: our watchers are ECHO-AND-TERMINATE — on every
#      detected delta the watcher prints and EXITS, and the agent session re-arms it
#      only at the END of its wake-cycle, which can take several minutes. So "watcher.pid
#      points at a dead process" is the NORMAL state during every active wake-cycle, not
#      a signal of trouble. v2 tripped on a single failed tick (+20s debounce) and fired
#      a false positive mid-wake-cycle (watcher down ~2.5 min, session fully alive and
#      posting) — corrected 2026-07-04 (v2.1). Only SUSTAINED death — dead across
#      WATCHER_DEAD_TICKS consecutive cadence ticks (~15 min at the default 300s cadence)
#      — distinguishes a genuinely dormant/dead session from a normal in-progress
#      wake-cycle. If the watcher is confirmed dead for that many consecutive ticks,
#      the heartbeat:
#        a. Appends an ADDRESSED "⚠️ WATCHER-DOWN" alert to its own file (addressee:
#           ALL if this is the orchestrator, else "orchestrator") so the peer's watcher
#           wakes on it — closing the "unaddressed 💓 absorbed silently" gap.
#        b. Prints a loud stdout banner with both re-arm commands.
#        c. exit 42 (dead-man exit — distinct from the normal cap-reached exit 0) —
#           this is the ONLY way a backgrounded process can wake a dormant agent session.
#      COUNTER: a per-loop consecutive-failure counter increments on each failed
#      watcher_alive check and resets to 0 the instant a check succeeds — including a
#      fresh re-arm mid-count, since the mtime-GRACE below makes watcher_alive report
#      "alive" immediately once the new watcher.pid is written, with no extra code
#      needed to detect the reset.
#      GRACE: a watcher.pid younger than 60s is assumed to be mid-(re)arm and never
#      trips the alarm on its own (this is a per-check test, independent of and always
#      applied before the consecutive-tick counter above). The heartbeat NEVER
#      auto-re-arms the watcher (P6) — it only screams; the agent session re-arms it.
#
# CONCRETE VALUES:
#   --idle-threshold    default 1200s (20 min): own file idle >= this → heartbeat fires.
#   --cadence           default 300s  (5 min):  check-interval between idle-status checks.
#   CAP                 21600s (~6h): self-cap; agent re-arms if longer operation needed.
#   DEPTH_FLOOR         12: minimum READY WOs before discovery triggers.
#   WATCHER_GRACE       60s: watcher.pid younger than this is never treated as dead
#                       (a deliberate kill-and-re-arm cycle in progress).
#   WATCHER_DEAD_TICKS  3: consecutive failed cadence ticks required to trip the alarm —
#                       ~15 min of sustained death at the default 300s cadence. Chosen
#                       because echo-and-terminate watchers are legitimately "dead"
#                       (exited, not yet re-armed) throughout any active wake-cycle;
#                       only death sustained across multiple ticks means the session
#                       itself has gone dormant/dead, not merely mid-wake-cycle.
#   EXIT 42             Dead-man exit code: watcher confirmed dead for WATCHER_DEAD_TICKS
#                       consecutive ticks, alert posted, heartbeat self-terminated as
#                       its session's only wake mechanism.
#
# REQUIRED ARGUMENTS:
#   --identity <id>                 This instance's stable ID.
#   --role orchestrator|implementer Role is explicit — do NOT infer from presence file.
#                                   Inference would race: heartbeat may start before
#                                   watch-coordination.sh creates the presence file.
#   --dir <coord-dir>               Path to the shared coordination directory.
#
# M1 NOTE: The heartbeat's UTC timestamp IS the self-varying element. Each append is unique.
#          No --seq counter needed. The watcher (watch-coordination.sh) wakes on the append
#          and delivers the new content (with its unique timestamp) to the agent.
#
# M2 NOTE: Never pkill -f on a shared machine (kills the peer's loop). To stop:
#            kill $(cat <coord-dir>/.watch-state/<id>/heartbeat.pid)
#
# M4 NOTE: After every write (PID file + heartbeat appends), read back to confirm
#          the write persisted. The sandbox filesystem can silently drop writes.
#
# WRITE MODEL: <id>.md is append-only after watch-coordination.sh creates it.
#   The heartbeat is the SOLE appender of HEARTBEAT entries via `>>`. No mktemp+mv
#   needed here — the watcher no longer writes <id>.md content, so there is no
#   concurrent writer to race against. Direct append is safe and simpler.
#
# TOOL-BACKGROUND (required):
#   Run via the Bash tool with run_in_background=true.
#   ALSO: use dangerouslyDisableSandbox:true — the heartbeat writes to files at idle intervals
#   spanning many minutes; the sandboxed environment may restrict background file I/O without it.
#   NEVER use shell `&` or `disown` — orphans the process (silent stall; no harness visibility).

set -uo pipefail

# ── argument parsing ──────────────────────────────────────────────────────────

IDENTITY=""
ROLE=""
COORD_DIR=""
IDLE_THRESHOLD=1200   # 20 min
CADENCE=300           # 5 min check-interval

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity)       IDENTITY="$2";       shift 2 ;;
    --role)           ROLE="$2";           shift 2 ;;
    --dir)            COORD_DIR="$2";      shift 2 ;;
    --idle-threshold) IDLE_THRESHOLD="$2"; shift 2 ;;
    --cadence)        CADENCE="$2";        shift 2 ;;
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

# CRITICAL: identity charset assertion — IDENTITY is used in file paths and presence-file
# content that peers read and grep. A metachar or path-separator in the id causes
# silent mis-behaviour (file not found, grep pattern error, or wrong file written).
if [[ ! "$IDENTITY" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: identity '${IDENTITY}' contains characters outside [A-Za-z0-9._-]." >&2
  echo "Rename to letters, digits, dots, underscores, and dashes (e.g. 'impl-alpha', not 'feature/auth[2]')." >&2
  exit 1
fi

MY_FILE="$COORD_DIR/$IDENTITY.md"
QUEUE_FILE="$COORD_DIR/QUEUE.md"
readonly CAP=21600
readonly DEPTH_FLOOR=12

STATE_DIR="$COORD_DIR/.watch-state/$IDENTITY"
HEARTBEAT_PID_FILE="$STATE_DIR/heartbeat.pid"
WATCHER_PID_FILE="$STATE_DIR/watcher.pid"
readonly WATCHER_GRACE=60        # watcher.pid younger than this → never treated as dead
readonly WATCHER_DEAD_TICKS=3    # consecutive failed cadence ticks → trip the alarm (~15 min @ 300s)

# Absolute path of this script — used in the re-arm command printed at the cap.
SCRIPT_ABS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"

# Absolute path of the sibling watch-coordination.sh — used in the WATCHER-DOWN
# alert's re-arm instructions. Same directory as this script (both ship together).
WATCH_SCRIPT_ABS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/watch-coordination.sh"

# ── directories ───────────────────────────────────────────────────────────────

mkdir -p "$COORD_DIR"
mkdir -p "$STATE_DIR" || { echo "FATAL: cannot create state dir $STATE_DIR" >&2; exit 1; }

# ── mtime utility (portable: macOS + Linux) ───────────────────────────────────
# Probe $COORD_DIR rather than $0 to handle split-filesystem edge cases where the
# script and the coord-dir live on filesystems with different stat flavors.

_STAT_CMD=""
if stat -f "%m" "$COORD_DIR" >/dev/null 2>&1; then
  _STAT_CMD="bsd"   # macOS / BSD stat
elif stat -c "%Y" "$COORD_DIR" >/dev/null 2>&1; then
  _STAT_CMD="gnu"   # Linux / GNU stat
else
  _STAT_CMD="none"
fi

file_mtime() {
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
      fi
      ;;
  esac
}

now_epoch() { date +%s; }

# ── watcher dead-man helper ───────────────────────────────────────────────────

watcher_alive() {
  # Returns 0 (alive) or 1 (dead). Never exits on error — used in a boolean context.
  #
  # Checks, in order:
  #   1. watcher.pid missing or empty → dead.
  #   2. GRACE: watcher.pid mtime < WATCHER_GRACE seconds old → alive (assume a
  #      deliberate kill-and-re-arm cycle is in progress; don't false-trip on the
  #      brief window between the old watcher exiting and the new one re-arming).
  #   3. `kill -0 "$pid"` fails (no such process) → dead.
  #   4. PID-reuse guard: the OS may have recycled the PID for an unrelated process
  #      since the watcher wrote it. Confirm the live process's command line still
  #      contains "watch-coordination.sh" — else dead (a recycled PID must not fake
  #      liveness).
  local pid mt now age

  [[ -s "$WATCHER_PID_FILE" ]] || return 1

  mt=$(file_mtime "$WATCHER_PID_FILE")
  now=$(now_epoch)
  age=$((now - mt))
  if [[ $age -lt $WATCHER_GRACE ]]; then
    return 0   # GRACE: too soon to judge — assume a re-arm cycle in progress.
  fi

  pid=$(cat "$WATCHER_PID_FILE" 2>/dev/null)
  [[ -n "$pid" ]] || return 1

  kill -0 "$pid" 2>/dev/null || return 1

  # PID-reuse guard.
  local cmd
  cmd=$(ps -p "$pid" -o command= 2>/dev/null)
  [[ "$cmd" == *watch-coordination.sh* ]] || return 1

  return 0
}

# ── self-registration: write heartbeat PID (M2, M4) ──────────────────────────
# PID goes to a dedicated single-writer file — no race with watch-coordination.sh
# (the watcher writes watcher.pid; we write heartbeat.pid; <id>.md is never rewritten).

printf '%s\n' "$$" > "$HEARTBEAT_PID_FILE"

# M4: confirm PID file persisted.
if ! grep -q "^$$" "$HEARTBEAT_PID_FILE" 2>/dev/null; then
  echo "WARN: heartbeat PID write did not persist: $HEARTBEAT_PID_FILE" >&2
  # Non-fatal — the heartbeat can still run; M2 kill will not work via the PID file.
fi

# Verify presence file exists. The watcher (watch-coordination.sh) creates it on arm.
# Start order: arm watcher FIRST, then arm heartbeat. If the file is missing here,
# the agent likely armed out of order. Log a warning — append_heartbeat() will also warn.
if [[ ! -f "$MY_FILE" ]]; then
  echo "WARN: $MY_FILE does not exist. The watcher should create it first." >&2
  echo "      Recommended start order: arm watch-coordination.sh, then heartbeat.sh." >&2
fi

echo "[heartbeat] $IDENTITY (role=$ROLE) armed at $(date -u +"%Y-%m-%dT%H:%M:%SZ")."
echo "[heartbeat] PID $$ → $HEARTBEAT_PID_FILE"
echo "[heartbeat] To stop (M2): kill \$(cat $HEARTBEAT_PID_FILE)"
echo "[heartbeat] idle-threshold=${IDLE_THRESHOLD}s, cadence=${CADENCE}s, cap=${CAP}s."
echo "[heartbeat] Discover-on-idle: $([ "$ROLE" = "orchestrator" ] && echo "ENABLED (depth floor $DEPTH_FLOOR)" || echo "disabled (implementer)")"

# ── helpers ───────────────────────────────────────────────────────────────────

count_ready_wos() {
  # Count READY (unclaimed, buildable) WOs in QUEUE.md.
  # Looks for "| READY |" in the queue table (QUEUE-template.md format).
  [[ -f "$QUEUE_FILE" ]] || { echo 0; return; }
  local n
  n=$(grep -c "| READY |" "$QUEUE_FILE" 2>/dev/null) || true
  echo "${n:-0}"
}

seconds_since_own_file_modified() {
  # How long ago (in seconds) did this instance's own file last change?
  # "idle" = no messages posted and no heartbeats appended.
  [[ -f "$MY_FILE" ]] || { echo "$CAP"; return; }  # no file → treat as maximally idle
  local mt now
  mt=$(file_mtime "$MY_FILE")
  now=$(now_epoch)
  echo $((now - mt))
}

append_heartbeat() {
  local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Guard: presence file must exist (watcher creates it on arm).
  if [[ ! -f "$MY_FILE" ]]; then
    echo "WARN: $MY_FILE does not exist. Watcher should create it first. Skipping heartbeat." >&2
    return
  fi

  # Watcher pid read at append time — enriches the body with liveness context.
  # Never fails the append if unreadable; degrade to "UNKNOWN" instead.
  local watcher_pid_str
  watcher_pid_str=$(cat "$WATCHER_PID_FILE" 2>/dev/null)
  [[ -n "$watcher_pid_str" ]] || watcher_pid_str="UNKNOWN"

  # Direct append — heartbeat is the SOLE appender of HEARTBEAT entries (no race).
  # <id>.md is append-only: watcher ensures-or-creates it; we only append here.
  # M1: every heartbeat has a unique UTC timestamp → always unique content → watcher wakes.
  printf '\n### %s — %s — 💓 HEARTBEAT\n\nAlive. Watcher %s OK. Own file idle for >= %ss.\n' \
    "$ts" "$IDENTITY" "$watcher_pid_str" "$IDLE_THRESHOLD" >> "$MY_FILE"

  # M4: confirm append persisted.
  if ! tail -5 "$MY_FILE" 2>/dev/null | grep -q "HEARTBEAT"; then
    echo "WARN: heartbeat append did not persist in $MY_FILE" >&2
  else
    echo "[heartbeat] HEARTBEAT appended at $ts."
  fi
}

trip_watcher_down_alarm() {
  # Called only after watcher_alive has failed WATCHER_DEAD_TICKS consecutive cadence
  # ticks in a row (main loop's consecutive-failure counter).
  # Posts an ADDRESSED alert (so the peer's watcher, which filters by addressee,
  # actually wakes on it), prints a loud banner, and self-terminates with exit 42 —
  # the ONLY way a backgrounded process can wake a dormant agent session (P6: the
  # heartbeat NEVER auto-re-arms the watcher itself — it only screams).
  local ts pid addressee
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  pid=$(cat "$WATCHER_PID_FILE" 2>/dev/null)
  [[ -n "$pid" ]] || pid="UNKNOWN"

  if [[ "$ROLE" == "orchestrator" ]]; then
    addressee="ALL"
  else
    addressee="orchestrator"
  fi

  # Guard: skip the append if MY_FILE is missing, but still exit — the alarm's
  # dead-man exit is unconditional; a missing presence file must not suppress it.
  if [[ -f "$MY_FILE" ]]; then
    printf '\n### %s — %s → %s — ⚠️ WATCHER-DOWN\n\nWatcher PID %s is dead; this lane'"'"'s inbox is DEAF until the watcher is re-armed. Heartbeat is self-terminating as a dead-man wake signal for its own session. Re-arm the watcher with:\n\n  %s --identity %s --role %s --dir %s\n' \
      "$ts" "$IDENTITY" "$addressee" "$pid" "$WATCH_SCRIPT_ABS" "$IDENTITY" "$ROLE" "$COORD_DIR" >> "$MY_FILE"

    # M4: read back (tail + grep WATCHER-DOWN) to confirm the append persisted.
    if ! tail -10 "$MY_FILE" 2>/dev/null | grep -q "WATCHER-DOWN"; then
      echo "WARN: WATCHER-DOWN alert append did not persist in $MY_FILE" >&2
    fi
  else
    echo "WARN: $MY_FILE does not exist. Skipping WATCHER-DOWN append but still self-terminating." >&2
  fi

  echo ""
  echo "=== WATCHER DOWN — HEARTBEAT SELF-TERMINATING (dead-man wake) ==="
  echo "Dead watcher PID: $pid"
  echo ""
  echo "Reason chain:"
  echo "  1. Watcher confirmed dead across ${WATCHER_DEAD_TICKS} consecutive cadence ticks (~15 min)."
  echo "  2. Addressed ⚠️ WATCHER-DOWN alert posted to $MY_FILE (addressee: $addressee) →"
  echo "     the peer's watcher wakes on it (STAR addressing filter)."
  echo "  3. This heartbeat now self-exits (exit 42) — a backgrounded process's ONLY"
  echo "     way to wake its own dormant agent session is by terminating (harness"
  echo "     task-completion notification)."
  echo ""
  echo "Re-arm BOTH, in this order (P6: use the harness Bash tool with"
  echo "run_in_background=true — NEVER shell '&'):"
  echo ""
  echo "  1. $WATCH_SCRIPT_ABS --identity $IDENTITY --role $ROLE --dir $COORD_DIR"
  echo "  2. $SCRIPT_ABS --identity $IDENTITY --role $ROLE --dir $COORD_DIR"
  echo ""
  echo "=== end dead-man alert ==="

  exit 42
}

# ── main loop ─────────────────────────────────────────────────────────────────

started_at=$(now_epoch)
watcher_dead_ticks=0   # consecutive failed watcher_alive checks; resets to 0 on any success

while true; do
  sleep "$CADENCE"

  now=$(now_epoch)
  elapsed=$((now - started_at))

  if [[ $elapsed -ge $CAP ]]; then
    echo "[heartbeat] cap reached (${CAP}s elapsed). Exiting."
    echo "Re-arm to continue heartbeat monitoring:"
    echo ""
    echo "  $SCRIPT_ABS --identity $IDENTITY --role $ROLE --dir $COORD_DIR"
    exit 0
  fi

  # WATCHER DEAD-MAN SWITCH: check every tick, before the idle logic.
  # SUSTAINED-DEATH counter — echo-and-terminate watchers are legitimately dead
  # (exited, awaiting re-arm) throughout any active wake-cycle, so a single failed
  # tick is NORMAL, not a signal. Only death sustained across WATCHER_DEAD_TICKS
  # consecutive ticks (~15 min @ default cadence) means the session itself has gone
  # dormant/dead. A success at any point — including a fresh re-arm mid-count, which
  # watcher_alive's mtime-GRACE reports as "alive" immediately — resets the counter
  # to 0 with no extra code needed.
  if watcher_alive; then
    watcher_dead_ticks=0
  else
    watcher_dead_ticks=$((watcher_dead_ticks + 1))
    echo "[heartbeat] watcher check failed (${watcher_dead_ticks}/${WATCHER_DEAD_TICKS})."
    if [[ $watcher_dead_ticks -ge $WATCHER_DEAD_TICKS ]]; then
      trip_watcher_down_alarm
      # trip_watcher_down_alarm always exits (42) — unreachable, but explicit for readers.
      exit 42
    fi
  fi

  idle=$(seconds_since_own_file_modified)

  if [[ $idle -ge $IDLE_THRESHOLD ]]; then
    append_heartbeat

    # DISCOVER-ON-IDLE (Orchestrator only):
    # Heartbeat fired = we have been quiet for >= idle-threshold.
    # If queue is below the depth floor, the Orchestrator should run a discovery pass.
    if [[ "$ROLE" == "orchestrator" ]]; then
      ready=$(count_ready_wos)
      if [[ $ready -lt $DEPTH_FLOOR ]]; then
        echo ""
        echo "=== DISCOVERY PASS NEEDED ==="
        echo "Queue READY count: $ready (floor: $DEPTH_FLOOR)"
        echo "Orchestrator has been idle for ${idle}s. Run the M5 6-lens discovery pass."
        echo "See 6-lens-audit.md and README.md for methodology."
        echo ""
      fi
    fi
  fi
done
