#!/usr/bin/env bash
# heartbeat.sh — Idle-poke + Orchestrator discover-on-idle trigger.
#
# USAGE:
#   ./heartbeat.sh --identity <id> --role orchestrator|implementer --dir <coord-dir> \
#                  [--idle-threshold <secs>] [--cadence <secs>] [--idle-policy <txt>] \
#                  [--weak-seat] [--remote-host <alias>] [--remote-bus-dir <path>]
#
# PURPOSE:
#   Runs as a SEPARATE background process from coord-monitor.sh (the persistent
#   STAR inbox monitor). Three duties:
#
#   1. IDLE-POKE / IDLE-KICK (all instances): if this instance's own file has not been
#      modified for >= IDLE_THRESHOLD seconds, append a timestamped 💓 HEARTBEAT that
#      ALSO carries an ⚡ IDLE-KICK body — actionable standing idle_policy, NOT a bare
#      "Alive." The hub's peer-watch still sees the heartbeat; more importantly,
#      coord-monitor.sh (2026-07-18+) self-nudges on own-file HEARTBEAT/IDLE-KICK so
#      the *owning* seat actually wakes and starts idle work. (Pre-fix: STAR
#      no-self-watch meant implementer heartbeats never woke their own agent —
#      Max had to notice the idle and prompt by hand.)
#
#      Hub self-nudge is addressed IDENTITY → IDENTITY so spoke monitors' addressed
#      wake filter (PROTOCOL 1.2.1) does not wake unrelated implementers on the shared
#      hub outbox.
#
#      WEAK-SEAT GUARD (REMOTE-SEATS.md §8, IDLE-KICK amendment 2, 2026-07-18): a
#      remote/weak seat's idle policy is MANDATORY-EXPLICIT, never the strong-seat
#      "audit-and-improve... pick the next target and start work" default — that
#      default IS self-generated work, which §8 forbids outright for a weak seat
#      ("No self-generated work, ever"). Pass `--weak-seat` to enforce this: the
#      script REFUSES TO ARM at all unless `--idle-policy` is also given explicitly
#      (see the arg-parsing section below) — not a different default, an enforced
#      requirement, so a weak seat can never silently end up on a policy nobody
#      actually chose for it. A weak seat's idle policy should read roughly "post
#      exactly one 📥 WORK-REQUEST, then stop and do nothing until a reply" (§8),
#      never "start work on your own initiative."
#
#      PACE-DOWN / HOLD OVERRIDE (2026-07-18 ratified amendment, all seats): the
#      IDLE-KICK body's "do not stand by" instruction has one, and only one,
#      exception — an explicit Max pace-down or a declared, nameable HOLD in
#      effect. Those override; standing by is then the CORRECT behavior, not a
#      failure to act. This is not a license to self-declare a reason to idle —
#      only a Max-issued pace-down or a HOLD the agent can point to by name counts.
#
#   IDLE-KICK vs discover-on-idle (PROTOCOL 1.2.0):
#     - IDLE-KICK = own-file self-nudge with actionable idle_policy for ALL seats
#       (fixes STAR no-self-watch — peers never see your heartbeat as their inbox).
#     - discover-on-idle = Orchestrator-only queue-depth directive, folded INTO the
#       IDLE-KICK body when role=orchestrator — not a second parallel idle mechanism.
#   2. DISCOVER-ON-IDLE (Orchestrator only): when the heartbeat fires AND the queue is
#      below DEPTH_FLOOR buildable contracts, the IDLE-KICK body includes a
#      DISCOVERY PASS NEEDED directive (also printed to stdout). Discovery duty
#      folds into the heartbeat wake; the agent must run the M5 6-lens pass.
#
#   3. WATCHER DEAD-MAN SWITCH (all instances): each cadence tick, verify the sibling
#      coord-monitor.sh process is still alive. The heartbeat has no value if the
#      watcher is dead — and a backgrounded process can only wake its agent session by
#      terminating. (Human-directed 2026-07-04.)
#
#      WHY SUSTAINED, NOT SINGLE-TICK: under the *retired* echo-and-terminate watcher,
#      "watcher.pid points at a dead process" was NORMAL mid wake-cycle. That model is
#      gone — coord-monitor.sh is persistent (armed once per session). Sustained-death
#      tolerance (WATCHER_DEAD_TICKS consecutive failed ticks, ~15 min at default 300s
#      cadence) now mainly guards against false alarms from transient `ps` races, not
#      structurally-expected dead PIDs. If the watcher is confirmed dead for that many
#      consecutive ticks, the heartbeat:
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
#   --idle-policy <txt> standing idle work when kicked (default depends on --role).
#   --hold-check-interval  default 7200s (2h): while a HOLD marker is active, IDLE-KICK
#                       is damped and this is the interval between HOLD-CHECK liveness
#                       probes the owning agent must ACK (HOLD-DAMP-V2, 2026-07-29).
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
#                                   coord-monitor / the seat writes the presence file.
#   --dir <coord-dir>               Path to the shared coordination directory.
#
# M1 NOTE: The heartbeat's UTC timestamp IS the self-varying element. Each append is unique.
#          No --seq counter needed. coord-monitor.sh wakes on the append (own-file
#          IDLE-KICK path for this seat; peers see hub HEARTBEAT but spokes filter it).
#
# M2 NOTE: Never pkill -f on a shared machine (kills the peer's loop). To stop:
#            kill $(cat <coord-dir>/.watch-state/<id>/heartbeat.pid)
#
# M4 NOTE: After every write (PID file + heartbeat appends), read back to confirm
#          the write persisted. The sandbox filesystem can silently drop writes.
#
# WRITE MODEL: <id>.md is append-only after the seat creates its presence file.
#   The heartbeat is the SOLE appender of HEARTBEAT entries via `>>`. No mktemp+mv
#   needed here — the monitor does not rewrite <id>.md content, so there is no
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
IDLE_POLICY=""        # set after role known if unset — UNLESS --weak-seat, see below
HOLD_CHECK_INTERVAL=7200   # 2h — HOLD-DAMP-V2 liveness probe interval while damped
REMOTE_HOST=""        # optional — only used to print an exact re-arm command in a
REMOTE_BUS_DIR=""   # optional remote channel — REQUIRED with --remote-host (see advanced/REMOTE-SEATS.md)
                       # ALL-CHANNELS dead-man alert IF a remote coord-monitor
                       # channel is also armed for this identity (watcher-remote.pid
                       # present). Passing these does NOT arm anything itself — the
                       # remote coord-monitor.sh channel is a separate process.
WEAK_SEAT=0            # REMOTE-SEATS.md §8 IDLE-KICK amendment 2 (2026-07-18):
                       # deliberately SEPARATE from --remote-host above — that flag
                       # is about the ORCHESTRATOR's own heartbeat tracking a remote
                       # coord-monitor CHANNEL it owns; THIS flag is about the
                       # invoking SEAT itself being a remote/weak seat. An
                       # orchestrator heartbeat can legitimately pass --remote-host
                       # without being a weak seat itself — conflating the two would
                       # wrongly force the hub's own idle policy to work-request-only.
SCHEDULE_FILE=""       # PROTOCOL 1.3.0 — optional idle activity schedule
HB_HOME=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
PROTOCOL_VERSION="unknown"
# shellcheck source=PROTOCOL-VERSION
[[ -f "$HB_HOME/PROTOCOL-VERSION" ]] && . "$HB_HOME/PROTOCOL-VERSION"
# shellcheck source=coord-presence.sh
[[ -f "$HB_HOME/coord-presence.sh" ]] && . "$HB_HOME/coord-presence.sh"
# shellcheck source=coord-keygen.sh
# PROTOCOL 1.4.0 (Message Authenticity): sourcing (not executing) coord-keygen.sh
# pulls in ensure_signing_key / sign_message_file — the SAME shared helpers
# coord-send.sh uses, so this appender can never drift from coord-send.sh on
# signing mechanics. Its CLI dispatch is guarded behind a BASH_SOURCE==$0
# check, so sourcing here never runs its arg-parsing/dispatch.
[[ -f "$HB_HOME/coord-keygen.sh" ]] && . "$HB_HOME/coord-keygen.sh"

# F+: help exits before any pidfile write (pidfile is claimed later).
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      echo "Usage: $0 --identity <id> --role orchestrator|implementer --dir <coord-dir> [options]"
      echo "Options: --idle-threshold --cadence --idle-policy --schedule-file --hold-check-interval --remote-host --remote-bus-dir --weak-seat"
      echo "  --schedule-file <path>   Idle activity schedule (see IDLE-SCHEDULE-template.md)."
      echo "                           Default probe: <coord-dir>/idle-schedule-<identity>.md"
      echo "  --hold-check-interval <secs>  default 7200 (2h). While a [HOLD:<name>] marker is"
      echo "                                active on this seat's latest substantive outbox header,"
      echo "                                IDLE-KICK is damped and a HOLD-CHECK is posted every"
      echo "                                <secs>; the owning AGENT must ACK it or this heartbeat"
      echo "                                self-terminates with exit 43."
      echo "PROTOCOL $PROTOCOL_VERSION — Help exits 0 WITHOUT writing heartbeat.pid."
      exit 0
      ;;
    --identity)       IDENTITY="$2";       shift 2 ;;
    --role)           ROLE="$2";           shift 2 ;;
    --dir)            COORD_DIR="$2";      shift 2 ;;
    --idle-threshold) IDLE_THRESHOLD="$2"; shift 2 ;;
    --cadence)        CADENCE="$2";        shift 2 ;;
    --idle-policy)    IDLE_POLICY="$2";    shift 2 ;;
    --schedule-file)  SCHEDULE_FILE="$2";  shift 2 ;;
    --hold-check-interval) HOLD_CHECK_INTERVAL="$2"; shift 2 ;;
    --remote-host)    REMOTE_HOST="$2";    shift 2 ;;
    --remote-bus-dir) REMOTE_BUS_DIR="$2"; shift 2 ;;
    --weak-seat)      WEAK_SEAT=1;         shift ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$IDENTITY" || -z "$ROLE" || -z "$COORD_DIR" ]]; then
  echo "ERROR: --identity, --role, and --dir are all required." >&2
  echo "Usage: $0 --identity <id> --role orchestrator|implementer --dir <coord-dir> [--idle-policy <txt>]" >&2
  exit 1
fi

if [[ "$ROLE" != "orchestrator" && "$ROLE" != "implementer" ]]; then
  echo "ERROR: --role must be 'orchestrator' or 'implementer'." >&2
  exit 1
fi

# Default standing idle policies (override with --idle-policy) — STRONG SEATS ONLY.
#
# REMOTE-SEATS.md §8 IDLE-KICK amendment 2 (2026-07-18): a weak/remote seat's
# --idle-policy is MANDATORY-EXPLICIT. The "audit-and-improve... do NOT stand by;
# pick the next target and start work" default below is exactly the SELF-GENERATED
# WORK §8 forbids for a weak seat ("No self-generated work, ever... the strong-seat
# audit-and-improve default must never be its fallback"). --weak-seat therefore
# skips the silent-fallback branch entirely and REFUSES TO ARM without an explicit
# --idle-policy — not a different default, an enforced requirement — so a weak seat
# can never end up running with a policy nobody actually chose for it.
if [[ "$WEAK_SEAT" == 1 ]]; then
  if [[ -z "$IDLE_POLICY" ]]; then
    echo "ERROR: --weak-seat requires an explicit --idle-policy (advanced/REMOTE-SEATS.md: MANDATORY-EXPLICIT, work-request-only — never the strong-seat audit-and-improve fallback)." >&2
    echo "Example: --idle-policy 'on idle: post exactly one 📥 WORK-REQUEST, then stop and do nothing until a reply; re-request no more than once per hour'" >&2
    exit 1
  fi
elif [[ -z "$IDLE_POLICY" ]]; then
  if [[ "$ROLE" == "orchestrator" ]]; then
    IDLE_POLICY="keep 🔨 queue ≥12 (6-lens discover-on-idle if READY < floor); otherwise verify/reconcile/refill"
  else
    IDLE_POLICY="audit-and-improve owned lane — do NOT stand by; pick the next honesty/Scroll-Law/defect target and start work; post 🛰️ HEADS-UP when you begin"
  fi
fi

# PROTOCOL 1.3.0 — optional per-seat activity schedule overlays / replaces prose policy body.
# Explicit --idle-policy still wins as the standing-idle-policy activity text when both exist.
if [[ -z "$SCHEDULE_FILE" && -f "$COORD_DIR/idle-schedule-$IDENTITY.md" ]]; then
  SCHEDULE_FILE="$COORD_DIR/idle-schedule-$IDENTITY.md"
fi
if [[ -n "$SCHEDULE_FILE" && -f "$SCHEDULE_FILE" ]]; then
  _sched_body=$(awk -v role="$ROLE" '
    BEGIN { id=""; when=""; summary=""; in_sum=0 }
    /^[[:space:]]*- id:[[:space:]]*/ {
      if (id != "" && keep) {
        printf "- **%s** (%s): %s\n", id, when, summary
      }
      id=$0; sub(/^[[:space:]]*- id:[[:space:]]*/, "", id)
      when=""; summary=""; keep=0; in_sum=0
      next
    }
    /^[[:space:]]*when:[[:space:]]*/ {
      when=$0; sub(/^[[:space:]]*when:[[:space:]]*/, "", when)
      keep=0
      if (when ~ /^always$/) keep=1
      if (when ~ ("role=" role)) keep=1
      if (role == "orchestrator" && when ~ /queue_ready/) keep=1
      if (role == "implementer" && when ~ /queue_has_unclaimed/) keep=1
      if (when ~ /hold_active/) keep=1
      next
    }
    /^[[:space:]]*summary:[[:space:]]*>-/ { in_sum=1; summary=""; next }
    /^[[:space:]]*summary:[[:space:]]*/ {
      summary=$0; sub(/^[[:space:]]*summary:[[:space:]]*/, "", summary)
      gsub(/^"/, "", summary); gsub(/"$/, "", summary)
      in_sum=0; next
    }
    in_sum == 1 {
      line=$0; sub(/^[[:space:]]*/, "", line)
      if (summary != "") summary=summary " "
      summary=summary line
      next
    }
    END {
      if (id != "" && keep) printf "- **%s** (%s): %s\n", id, when, summary
    }
  ' "$SCHEDULE_FILE")
  if [[ -n "$_sched_body" ]]; then
    IDLE_POLICY=$(printf 'Due idle activities (from %s):\n%s\nStanding fallback: %s' \
      "$(basename "$SCHEDULE_FILE")" "$_sched_body" "$IDLE_POLICY")
  fi
  unset _sched_body
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
HOLD_PENDING_FILE="$STATE_DIR/hold-check.pending"
HOLD_TICKS_FILE="$STATE_DIR/hold-check.ticks"
HOLD_LAST_FILE="$STATE_DIR/hold-check.last"
readonly HOLD_ACK_TICKS=2        # cadence ticks an agent has to ACK a HOLD-CHECK
readonly WATCHER_GRACE=60        # watcher.pid younger than this → never treated as dead
readonly WATCHER_DEAD_TICKS=3    # consecutive failed cadence ticks → trip the alarm (~15 min @ 300s)

# Absolute path of this script — used in the re-arm command printed at the cap.
SCRIPT_ABS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"

# Absolute path of the sibling coord-monitor.sh — used in WATCHER-DOWN re-arm text.
# (Legacy name watch-coordination.sh is retired; PID-reuse guard still accepts both.)
WATCH_SCRIPT_ABS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/coord-monitor.sh"

# Same path under the modern name (ALL-CHANNELS re-arm instructions).
MONITOR_SCRIPT_ABS="$WATCH_SCRIPT_ABS"


# Portable rule: remote re-arm hints require an explicit bus dir when --remote-host is set.
if [[ -n "$REMOTE_HOST" && -z "$REMOTE_BUS_DIR" ]]; then
  echo "ERROR: --remote-host requires --remote-bus-dir <path> (see advanced/REMOTE-SEATS.md)." >&2
  exit 2
fi

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
  # Takes the pidfile to check as $1 (REMOTE-SEATS.md §3.4 ALL-CHANNELS dead-man:
  # this identity may have MORE than one armed coord-monitor channel — watcher.pid
  # for the local channel, watcher-remote.pid for the §3.4 remote channel — each
  # checked independently by the discover/loop logic below).
  #
  # Checks, in order:
  #   1. pidfile missing or empty → dead.
  #   2. GRACE: pidfile mtime < WATCHER_GRACE seconds old → alive (assume a
  #      deliberate kill-and-re-arm cycle is in progress; don't false-trip on the
  #      brief window between the old watcher exiting and the new one re-arming).
  #   3. `kill -0 "$pid"` fails (no such process) → dead.
  #   4. PID-reuse guard: the OS may have recycled the PID for an unrelated process
  #      since the watcher wrote it. Confirm the live process's command line still
  #      contains "watch-coordination.sh" — else dead (a recycled PID must not fake
  #      liveness).
  local pidfile="$1" pid mt now age

  [[ -s "$pidfile" ]] || return 1

  mt=$(file_mtime "$pidfile")
  now=$(now_epoch)
  age=$((now - mt))
  if [[ $age -lt $WATCHER_GRACE ]]; then
    return 0   # GRACE: too soon to judge — assume a re-arm cycle in progress.
  fi

  pid=$(cat "$pidfile" 2>/dev/null)
  [[ -n "$pid" ]] || return 1

  kill -0 "$pid" 2>/dev/null || return 1

  # D (AMEND-PROCESS-HYGIENE-20260726): PPID=1 ⇒ ORPHAN ⇒ not harness-bridged ⇒ dead.
  local ppid
  ppid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')
  if [[ -z "${COORD_ALLOW_PPID1:-}" && "$ppid" == "1" ]]; then
    return 1
  fi

  # PID-reuse guard. Accept EITHER the legacy one-shot watcher (watch-coordination.sh)
  # OR the persistent coord-monitor.sh — both legitimately claim a watcher*.pid file.
  # Without coord-monitor.sh here, a live persistent monitor is misread as a dead
  # watcher and the heartbeat false-fires exit-42 every WATCHER_DEAD_TICKS (~15 min).
  local cmd
  cmd=$(ps -p "$pid" -o command= 2>/dev/null)
  [[ "$cmd" == *watch-coordination.sh* || "$cmd" == *coord-monitor.sh* ]] || return 1

  return 0
}

# B/C — durable orphan product sweep (report; conditional kill). Survives the
# shell SIGTERM that creates orphans. Never kills coord-monitor/heartbeat.
sweep_product_orphans() {
  local pid etime cmd ppid mm age_ok
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    ppid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')
    [[ "$ppid" == "1" ]] || continue
    cmd=$(ps -p "$pid" -o command= 2>/dev/null)
    [[ "$cmd" == *coord-monitor.sh* || "$cmd" == *heartbeat.sh* ]] && continue
    case "$cmd" in
      *curses.wrapper*|*pty_bootstrap*) ;;
      *) continue ;;
    esac
    etime=$(ps -p "$pid" -o etime= 2>/dev/null | tr -d ' ')
    age_ok=0
    case "$etime" in
      *-*) age_ok=1 ;;                          # days
      *:*:*) age_ok=1 ;;                        # hh:mm:ss
      *:*)
        mm=${etime%%:*}
        if [[ "$mm" =~ ^[0-9]+$ ]] && [[ "$mm" -ge 5 ]]; then age_ok=1; fi
        ;;
    esac
    echo "[heartbeat] ORPHAN-PRODUCT pid=$pid etime=$etime ppid=1 cmd=$(echo "$cmd" | cut -c1-120)"
    if [[ "$age_ok" -eq 1 ]]; then
      if kill "$pid" 2>/dev/null; then
        echo "[heartbeat] ORPHAN-PRODUCT reaped pid=$pid (PPID=1 ∧ signature ∧ age≥5m)"
      else
        echo "[heartbeat] ORPHAN-PRODUCT kill failed pid=$pid (left reported)"
      fi
    else
      echo "[heartbeat] ORPHAN-PRODUCT too young (etime=$etime) — report only"
    fi
  done < <(ps -axo pid= -o command= 2>/dev/null | grep -E 'curses\.wrapper|pty_bootstrap' | grep -v grep | awk '{print $1}')
}

# ── ALL-CHANNELS discovery (REMOTE-SEATS.md §3.4) ────────────────────────────
# watcher.pid = the local channel (unchanged path/name — full backward compat: an
# identity with only this one file behaves exactly as before). watcher-<name>.pid
# = any additional armed channel (currently just watcher-remote.pid for §3.4, but
# the naming convention generalizes). Discovered by glob, not hardcoded — a new
# channel type needs zero heartbeat.sh changes to be picked up.
discover_watcher_pidfiles() {
  local f
  for f in "$STATE_DIR"/watcher.pid "$STATE_DIR"/watcher-*.pid; do
    [[ -e "$f" ]] && printf '%s\n' "$f"
  done
}

channel_label() {
  local b; b=$(basename "$1" .pid)
  if [[ "$b" == "watcher" ]]; then echo "local"; else echo "${b#watcher-}"; fi
}

# Per-channel re-arm command for the alert/banner. Only "local" and "remote" are
# known concretely (remote needs --remote-host/--remote-bus-dir, which this script
# only has if THEY were passed to it — see the flags above); anything else prints
# a channel-labelled fallback rather than guessing a wrong command.
rearm_command_for_channel() {
  local label="$1"
  case "$label" in
    local)
      printf '%s --identity %s --dir %s' "$MONITOR_SCRIPT_ABS" "$IDENTITY" "$COORD_DIR"
      ;;
    remote)
      if [[ -n "$REMOTE_HOST" ]]; then
        printf '%s --identity %s --dir %s --remote-host %s --remote-bus-dir %s' \
          "$MONITOR_SCRIPT_ABS" "$IDENTITY" "$COORD_DIR" "$REMOTE_HOST" "$REMOTE_BUS_DIR"
      else
        printf '%s --identity %s --dir %s --remote-host <alias> --remote-bus-dir %s   # (this heartbeat was not told --remote-host — fill in the alias)' \
          "$MONITOR_SCRIPT_ABS" "$IDENTITY" "$COORD_DIR" "$REMOTE_BUS_DIR"
      fi
      ;;
    *)
      printf '%s --identity %s --dir %s   # channel "%s" — check its own coord-monitor.sh invocation for any extra flags it needs' \
        "$MONITOR_SCRIPT_ABS" "$IDENTITY" "$COORD_DIR" "$label"
      ;;
  esac
}

# ── self-registration: write heartbeat PID (M2, M4) ──────────────────────────
# PID goes to a dedicated single-writer file — no race with coord-monitor.sh
# (the monitor writes watcher.pid; we write heartbeat.pid; <id>.md is never rewritten).

printf '%s\n' "$$" > "$HEARTBEAT_PID_FILE"
if declare -F presence_set >/dev/null 2>&1; then
  presence_ensure_from_mailbox "$COORD_DIR" "$IDENTITY"
  presence_set "$COORD_DIR" "$IDENTITY" "heartbeat_pid" "$$"
  presence_set "$COORD_DIR" "$IDENTITY" "role" "$ROLE"
  presence_set "$COORD_DIR" "$IDENTITY" "protocol_version" "$PROTOCOL_VERSION"
fi

# M4: confirm PID file persisted.
if ! grep -q "^$$" "$HEARTBEAT_PID_FILE" 2>/dev/null; then
  echo "WARN: heartbeat PID write did not persist: $HEARTBEAT_PID_FILE" >&2
  # Non-fatal — the heartbeat can still run; M2 kill will not work via the PID file.
fi

# Verify presence file exists. The seat (or bootstrap) creates it before arming.
# Start order: write presence + arm coord-monitor FIRST, then arm heartbeat.
if [[ ! -f "$MY_FILE" ]]; then
  echo "WARN: $MY_FILE does not exist. Create the presence file / arm the seat first." >&2
  echo "      Recommended start order: arm coord-monitor.sh, then heartbeat.sh." >&2
fi

echo "[heartbeat] $IDENTITY (role=$ROLE) armed at $(date -u +"%Y-%m-%dT%H:%M:%SZ")."
echo "[heartbeat] PID $$ → $HEARTBEAT_PID_FILE"
echo "[heartbeat] PROTOCOL $PROTOCOL_VERSION"
echo "[heartbeat] To stop (M2): kill \$(cat $HEARTBEAT_PID_FILE)"
if [[ -n "$SCHEDULE_FILE" && -f "$SCHEDULE_FILE" ]]; then
  echo "[heartbeat] Schedule: $SCHEDULE_FILE"
fi
echo "[heartbeat] idle-threshold=${IDLE_THRESHOLD}s, cadence=${CADENCE}s, cap=${CAP}s."
echo "[heartbeat] idle-policy: $IDLE_POLICY"
echo "[heartbeat] Discover-on-idle: $([ "$ROLE" = "orchestrator" ] && echo "ENABLED (depth floor $DEPTH_FLOOR)" || echo "via IDLE-KICK body (implementer)")"

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
  local idle_s; idle_s=$(seconds_since_own_file_modified)

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

  # Optional discover directive (orchestrator, queue thin).
  local discover_block=""
  if [[ "$ROLE" == "orchestrator" ]]; then
    local ready; ready=$(count_ready_wos)
    if [[ $ready -lt $DEPTH_FLOOR ]]; then
      discover_block=$(printf '\n**DISCOVERY PASS NEEDED** — queue READY=%s (floor %s). Run the M5 6-lens discovery pass NOW (see 6-lens-audit.md). Do not stand by.\n' "$ready" "$DEPTH_FLOOR")
      echo ""
      echo "=== DISCOVERY PASS NEEDED ==="
      echo "Queue READY count: $ready (floor: $DEPTH_FLOOR)"
      echo "Orchestrator has been idle for ${idle_s}s. Run the M5 6-lens discovery pass."
      echo ""
    fi
  fi

  # Direct append — heartbeat is the SOLE appender of HEARTBEAT entries (no race).
  # Body must include ⚡ IDLE-KICK so coord-monitor's self-nudge path wakes THIS seat
  # (STAR no-self-watch otherwise leaves implementers forever idle until a human pokes).
  # M1: every heartbeat has a unique UTC timestamp → always unique content → watcher wakes.
  #
  # PROTOCOL 1.4.0: build the message into a temp file, sign THAT file, then
  # append the signed file + SIG block together — sign or skip, never post
  # unsigned (dead-man-switch backstop already tolerates a missed cycle;
  # WATCHER_DEAD_TICKS exists for exactly this kind of transient gap).
  local hb_tmp; hb_tmp=$(mktemp "${TMPDIR:-/tmp}/coord-hb.XXXXXX")
  {
    # Hub outbox is every spoke's inbox — address self-nudges as IDENTITY → IDENTITY
    # and tag SELF-NUDGE so spokes do not treat hub IDLE-KICK imperatives as HANDOFFs
    # (CC PROCESS-NOTE 2026-07-27; WO-PROCESS-HUB-IDLE-KICK-ADDRESS).
    printf '### %s — %s → %s — 💓 HEARTBEAT [self-nudge]\n\n' "$ts" "$IDENTITY" "$IDENTITY"
    if [[ "$ROLE" == "orchestrator" ]]; then
      printf '**SELF-NUDGE (hub only — spokes ignore for action)**\n\n'
    fi
    printf 'Alive. Watcher %s OK. Own file idle for >= %ss (actual ~%ss).\n\n' \
      "$watcher_pid_str" "$IDLE_THRESHOLD" "$idle_s"
    # PROTOCOL 1.5.0 §3.5 Part D (round-9, 2026-08-10, Cipher HIGH): the ONLY
    # signed-and-verifiable source coordination-precommit-hook.sh's check 1d
    # trusts for a peer's protocol version — unlike the unsigned .presence
    # sidecar (coord-dir-write-level forgeable, no ownership enforcement),
    # this line lives inside the SAME already-signed HEARTBEAT body, so a
    # forged claim would have to forge the whole signature. Own line, own
    # prefix (`PROTOCOL-VERSION: `) so check 1d's scan can find it reliably
    # regardless of surrounding body text.
    printf 'PROTOCOL-VERSION: %s\n\n' "$PROTOCOL_VERSION"
    printf '⚡ **IDLE-KICK** — you have been quiet. Mid-task → CONTINUE where you left off (do not idle between steps). Queue/lane empty → start idle work NOW:\n\n'
    printf '> %s\n\n' "$IDLE_POLICY"
    printf 'Do **not** answer with "standing by" / "no action" and stop. Post a 🛰️ HEADS-UP naming the next target, then build. (coord-monitor self-nudge delivers this wake; peers also see the HEARTBEAT.)\n\n'
    printf '**Exception (2026-07-18 ratified amendment):** unless an explicit Max pace-down or a declared HOLD (name it) is active — those override; standing by is then correct. This is NOT a license to invent your own reason to idle; only a Max-issued pace-down or a HOLD you can point to by name counts.\n'
    if [[ -n "$discover_block" ]]; then
      # $(...) strips the trailing newline printf built into discover_block —
      # restore it here. Without this, the SIG block glues onto the same line
      # as this text (no newline before it), which coord-verify.sh's
      # line-based SIG_START match then simply cannot find.
      printf '%s\n' "$discover_block"
    fi
  } > "$hb_tmp"

  if ! command -v ensure_signing_key >/dev/null 2>&1; then
    echo "WARN: coord-keygen.sh not found beside heartbeat.sh ($HB_HOME) — cannot sign; skipping this heartbeat cycle (never posting unsigned)." >&2
    rm -f "$hb_tmp"
    return
  fi
  local hb_privkey; hb_privkey=$(ensure_signing_key "$HB_HOME/coord-keygen.sh" "$IDENTITY" "$COORD_DIR")
  if [[ -z "$hb_privkey" ]]; then
    echo "WARN: signing key unavailable for $IDENTITY — skipping this heartbeat cycle (never posting unsigned)." >&2
    rm -f "$hb_tmp"
    return
  fi
  local hb_sig; hb_sig=$(sign_message_file "$hb_privkey" "$IDENTITY" "$hb_tmp")
  if [[ $? -ne 0 || -z "$hb_sig" ]]; then
    echo "WARN: ssh-keygen -Y sign FAILED for this heartbeat cycle — skipping the append (never posting unsigned)." >&2
    rm -f "$hb_tmp"
    return
  fi

  { printf '\n'; cat "$hb_tmp"; printf '%s' "$hb_sig"; } >> "$MY_FILE"
  rm -f "$hb_tmp"

  # M4: confirm append persisted.
  # PROTOCOL 1.4.0: window widened 8 → 40 lines — the appended SIG block (~9
  # lines) now sits after the body text this check greps for, so a narrow
  # tail window can push IDLE-KICK out of range and false-WARN on a landed,
  # correctly-signed append.
  if ! tail -40 "$MY_FILE" 2>/dev/null | grep -q "IDLE-KICK"; then
    echo "WARN: heartbeat/IDLE-KICK append did not persist in $MY_FILE" >&2
  else
    echo "[heartbeat] HEARTBEAT+IDLE-KICK appended at $ts (idle~${idle_s}s), signed."
    # Stdout banner — also matches notify_on_output if this shell is monitored.
    printf '┃ IDLE-KICK ▼ %s idle~%ss — start idle_policy work (do not stand by) @ %s\n' \
      "$IDENTITY" "$idle_s" "$ts"
  fi
}

trip_watcher_down_alarm() {
  # Called only after watcher_alive has failed WATCHER_DEAD_TICKS consecutive cadence
  # ticks in a row FOR ONE CHANNEL (main loop's per-channel counter file — see
  # discover_watcher_pidfiles above). $1 = the dead pidfile; channel label derived
  # from it (REMOTE-SEATS.md §3.4 ALL-CHANNELS dead-man — any armed channel dying
  # trips this the same way, local or remote).
  # Posts an ADDRESSED alert (so the peer's watcher, which filters by addressee,
  # actually wakes on it), prints a loud banner, and self-terminates with exit 42 —
  # the ONLY way a backgrounded process can wake a dormant agent session (P6: the
  # heartbeat NEVER auto-re-arms the watcher itself — it only screams).
  local pidfile="$1" label ts pid addressee rearm_cmd
  label=$(channel_label "$pidfile")
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  pid=$(cat "$pidfile" 2>/dev/null)
  [[ -n "$pid" ]] || pid="UNKNOWN"
  rearm_cmd=$(rearm_command_for_channel "$label")

  if [[ "$ROLE" == "orchestrator" ]]; then
    addressee="ALL"
  else
    addressee="orchestrator"
  fi

  # Guard: skip the append if MY_FILE is missing, but still exit — the alarm's
  # dead-man exit is unconditional; a missing presence file must not suppress it.
  if [[ -f "$MY_FILE" ]]; then
    # PROTOCOL 1.4.0: try to sign — the common case, and when it succeeds this
    # message is fully verified like everything else. WATCHER-DOWN is the ONE
    # message this protocol must never silently swallow for auth-layer reasons
    # ("the only way a backgrounded process can wake a dormant agent session"),
    # so ONLY on a signing failure does this fall back to an UNSIGNED append —
    # loudly flagged in the body, never silent. See coord-verify.sh's
    # exemption (c) (TAG starts with "⚠️ " AND the SIGNING-FAILED sentinel is
    # the body's first substantive line — shared with HOLD-WAKE-UNACKED
    # below, collapsed into one sentinel exemption 2026-08-09) — a SIGNED
    # WATCHER-DOWN still gets full verification and a tampered/forged one
    # still hard-fails as INVALID same as any other message.
    local wd_tmp; wd_tmp=$(mktemp "${TMPDIR:-/tmp}/coord-wd.XXXXXX")
    printf '### %s — %s → %s — ⚠️ WATCHER-DOWN [channel: %s]\n\nWatcher PID %s (channel: %s) is dead; this lane'"'"'s inbox on that channel is DEAF until it is re-armed. Heartbeat is self-terminating as a dead-man wake signal for its own session. Re-arm with:\n\n  %s\n' \
      "$ts" "$IDENTITY" "$addressee" "$label" "$pid" "$label" "$rearm_cmd" > "$wd_tmp"

    local wd_sig="" wd_signed=0
    if command -v ensure_signing_key >/dev/null 2>&1; then
      local wd_privkey; wd_privkey=$(ensure_signing_key "$HB_HOME/coord-keygen.sh" "$IDENTITY" "$COORD_DIR")
      if [[ -n "$wd_privkey" ]]; then
        wd_sig=$(sign_message_file "$wd_privkey" "$IDENTITY" "$wd_tmp")
        [[ $? -eq 0 && -n "$wd_sig" ]] && wd_signed=1
      fi
    fi

    if [[ "$wd_signed" -eq 1 ]]; then
      { printf '\n'; cat "$wd_tmp"; printf '%s' "$wd_sig"; } >> "$MY_FILE"
    else
      echo "WARN: could not sign the WATCHER-DOWN alert — posting UNSIGNED, loudly flagged. This is the one message the protocol never silently swallows for auth-layer reasons." >&2
      {
        printf '\n### %s — %s → %s — ⚠️ WATCHER-DOWN [channel: %s]\n\n' "$ts" "$IDENTITY" "$addressee" "$label"
        printf '[SIGNING-FAILED — unauthenticated, verify liveness by other means]\n\n'
        printf 'Watcher PID %s (channel: %s) is dead; this lane'"'"'s inbox on that channel is DEAF until it is re-armed. Heartbeat is self-terminating as a dead-man wake signal for its own session. Re-arm with:\n\n  %s\n' \
          "$pid" "$label" "$rearm_cmd"
      } >> "$MY_FILE"
    fi
    rm -f "$wd_tmp"

    # M4: read back (tail + grep WATCHER-DOWN) to confirm the append persisted.
    # PROTOCOL 1.4.0: window widened 10 → 40 lines — same reason as the
    # IDLE-KICK check above: a signed WATCHER-DOWN carries a ~9-line SIG
    # block after the body, which a narrow tail window can push out of range.
    if ! tail -40 "$MY_FILE" 2>/dev/null | grep -q "WATCHER-DOWN"; then
      echo "WARN: WATCHER-DOWN alert append did not persist in $MY_FILE" >&2
    fi
  else
    echo "WARN: $MY_FILE does not exist. Skipping WATCHER-DOWN append but still self-terminating." >&2
  fi

  echo ""
  echo "=== WATCHER DOWN [channel: $label] — HEARTBEAT SELF-TERMINATING (dead-man wake) ==="
  echo "Dead watcher PID: $pid (channel: $label)"
  echo ""
  echo "Reason chain:"
  echo "  1. Watcher confirmed dead across ${WATCHER_DEAD_TICKS} consecutive cadence ticks (~15 min) on the '$label' channel."
  echo "  2. Addressed ⚠️ WATCHER-DOWN alert posted to $MY_FILE (addressee: $addressee) →"
  echo "     the peer's watcher wakes on it (STAR addressing filter)."
  echo "  3. This heartbeat now self-exits (exit 42) — a backgrounded process's ONLY"
  echo "     way to wake its own dormant agent session is by terminating (harness"
  echo "     task-completion notification). NOTE: this exits the WHOLE heartbeat, not"
  echo "     just the '$label' channel's tracking — ALL channels need re-checking on restart."
  echo ""
  echo "Re-arm the '$label' channel, then this heartbeat (P6: use the harness Bash tool"
  echo "with run_in_background=true — NEVER shell '&'):"
  echo ""
  echo "  1. $rearm_cmd"
  echo "  2. $SCRIPT_ABS --identity $IDENTITY --role $ROLE --dir $COORD_DIR${REMOTE_HOST:+ --remote-host $REMOTE_HOST --remote-bus-dir $REMOTE_BUS_DIR}"
  echo ""
  echo "(If OTHER channels were still alive when this one tripped, they are untouched on"
  echo "disk — only re-arm the channel(s) named above, plus this heartbeat.)"
  echo ""
  echo "=== end dead-man alert ==="

  exit 42
}


# ── HOLD damping (HOLD-DAMP-V2 — ratified 2026-07-29, unanimous) ──────────────
#
# A seat under a declared HOLD marks the header of its latest substantive outbox
# entry with [HOLD:<name>]. While that marker stands, IDLE-KICK is suppressed and
# the heartbeat instead posts a HOLD-CHECK every HOLD_CHECK_INTERVAL seconds, which
# the OWNING AGENT (never this script) must ACK. No ACK inside HOLD_ACK_TICKS cadence
# ticks → ⚠️ HOLD-WAKE-UNACKED + exit 43. A hold damps a seat that is still THERE;
# unproven liveness under a hold is the exact deaf-gap this amendment exists to close.
#
# SUBSTANTIVE — we enumerate the CLOSED side, deliberately.
# The ratified draft specified detection as a fixed alternation of tag words anchored
# straight after "— ":
#     ### .*— (STATUS|HEADS-UP|HANDOFF|ACK|DECISION|PROCESS-NOTE|DEPLOY)
# Measured against the live coord dir, that regex matched 0 of 5034 real headers.
# Two independent reasons: (a) every real header carries an EMOJI between "— " and
# the tag word, which the anchor forbids; (b) the live tag vocabulary is far wider
# than those seven words — QUEUE-STATUS, ACCEPT, MERGED, CLAIM, GO, MERGE-ARMED,
# REVISE, CORRECTION and more are all in daily use. Implemented literally, HOLD
# damping would have been a silent no-op: HOLD_ACTIVE always 0, IDLE-KICK never
# suppressed, HOLD-CHECK never posted, exit 43 unreachable — and every test that
# only asked "does it still work unheld?" would have passed.
#
# So the predicate is inverted: a header is substantive UNLESS it is one of the few
# known non-substantive kinds. A NEW, unrecognised tag therefore defaults to
# substantive → clears the hold → IDLE-KICK resumes. That is the fail-LOUD
# direction. The closed-list version fails silent, which is the wrong way for a
# mechanism whose only job is to notice that somebody stopped answering.
#
# The exclusion test is applied to the TAG WORD ONLY — the text after the final
# "— ", with any trailing "[...]" qualifier stripped. Matching "HEARTBEAT" anywhere
# on the line, or even anywhere in the tag, would let a STATUS *about* the heartbeat
# count as non-substantive: "📋 STATUS [WO-FIX-HEARTBEAT-DEADMAN]" contains the word.
# That is the fail-silent direction — a real message ignored, the seat left damped.
# The Rule 6 ACK exclusion is the one test that must see the qualifier, because
# "[HOLD-CHECK:<nonce>]" is precisely what distinguishes it from an ordinary ACK, so
# it matches against the unstripped tag.
#
# Extraction is pure bash parameter expansion, not sed/awk: this runs on every
# header of a mailbox that reached 2.2MB before archiving, every cadence tick, and
# one fork per header line is not worth paying.

HOLD_ACTIVE=0
HOLD_NAME=""

detect_hold_marker() {
  # Sets HOLD_ACTIVE (1/0) and HOLD_NAME. Never fails the caller.
  HOLD_ACTIVE=0
  HOLD_NAME=""
  [[ -f "$MY_FILE" ]] || return 0

  local line tag tagword last="" rest
  while IFS= read -r line; do
    tag="${line##*— }"          # text after the FINAL em-dash separator
    tagword="${tag%% \[*}"      # ...minus any trailing "[qualifier]"
    case "$tag" in
      *ACK*"[HOLD-CHECK:"*) continue ;;   # Rule 6 — needs the qualifier to identify it
    esac
    case "$tagword" in
      *HEARTBEAT*|*WATCHER-DOWN*|*HOLD-WAKE-UNACKED*) continue ;;
    esac
    last="$line"
  done < <(grep -E '^### .*—.*—' "$MY_FILE" 2>/dev/null)

  [[ -n "$last" ]] || return 0

  case "$last" in
    *"[HOLD:"*)
      rest="${last#*"[HOLD:"}"
      HOLD_NAME="${rest%%]*}"
      HOLD_NAME="${HOLD_NAME%% ·*}"          # tolerate "[HOLD:name · HOLD-CHECK:ts]"
      [[ -n "$HOLD_NAME" ]] && HOLD_ACTIVE=1 # grammar requires [^]]+ — empty is not a hold
      ;;
  esac
  return 0
}

hold_addressee() {
  if [[ "$ROLE" == "orchestrator" ]]; then printf 'ALL'; else printf 'orchestrator'; fi
}

append_hold_check() {
  local ts nonce addressee
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  nonce="$ts"
  addressee=$(hold_addressee)

  # PROTOCOL 1.4.0: sign or skip, same policy as append_heartbeat — this is a
  # periodic liveness probe with its own retry cadence (HOLD_ACK_TICKS), so a
  # skipped cycle costs nothing and must never post unsigned.
  local hc_tmp; hc_tmp=$(mktemp "${TMPDIR:-/tmp}/coord-hc.XXXXXX")
  {
    printf '### %s — %s → %s — 💓 HEARTBEAT [HOLD:%s · HOLD-CHECK:%s]\n\n' \
      "$ts" "$IDENTITY" "$addressee" "$HOLD_NAME" "$nonce"
    printf 'HOLD **%s** is active — IDLE-KICK is damped, so this seat is deliberately quiet.\n' "$HOLD_NAME"
    printf 'This is the periodic liveness check (every %ss).\n\n' "$HOLD_CHECK_INTERVAL"
    printf 'The **owning agent** must answer on this file (this script cannot answer for you):\n\n'
    printf '    ### <ts> — %s → %s — 🤝 ACK [HOLD-CHECK:%s]\n\n' "$IDENTITY" "$addressee" "$nonce"
    printf 'That ACK does **not** clear the hold (Rule 6 exclusion) — damping continues.\n'
    printf 'No ACK within %s cadence ticks (~%ss) → ⚠️ HOLD-WAKE-UNACKED and this heartbeat exits 43.\n' \
      "$HOLD_ACK_TICKS" "$((HOLD_ACK_TICKS * CADENCE))"
  } > "$hc_tmp"

  if ! command -v ensure_signing_key >/dev/null 2>&1; then
    echo "WARN: coord-keygen.sh not found beside heartbeat.sh ($HB_HOME) — cannot sign; skipping this HOLD-CHECK cycle (never posting unsigned)." >&2
    rm -f "$hc_tmp"
    return
  fi
  local hc_privkey; hc_privkey=$(ensure_signing_key "$HB_HOME/coord-keygen.sh" "$IDENTITY" "$COORD_DIR")
  if [[ -z "$hc_privkey" ]]; then
    echo "WARN: signing key unavailable for $IDENTITY — skipping this HOLD-CHECK cycle (never posting unsigned)." >&2
    rm -f "$hc_tmp"
    return
  fi
  local hc_sig; hc_sig=$(sign_message_file "$hc_privkey" "$IDENTITY" "$hc_tmp")
  if [[ $? -ne 0 || -z "$hc_sig" ]]; then
    echo "WARN: ssh-keygen -Y sign FAILED for this HOLD-CHECK cycle — skipping the append (never posting unsigned)." >&2
    rm -f "$hc_tmp"
    return
  fi

  { printf '\n'; cat "$hc_tmp"; printf '%s' "$hc_sig"; } >> "$MY_FILE"
  rm -f "$hc_tmp"

  printf '%s' "$nonce" > "$HOLD_PENDING_FILE"
  printf '0' > "$HOLD_TICKS_FILE"
  printf '%s' "$(now_epoch)" > "$HOLD_LAST_FILE"

  echo "[heartbeat] HOLD-CHECK posted (hold=$HOLD_NAME nonce=$nonce), signed."
  printf '┃ HOLD-CHECK ▼ %s hold=%s nonce=%s — agent ACK required within %s ticks\n' \
    "$IDENTITY" "$HOLD_NAME" "$nonce" "$HOLD_ACK_TICKS"
}

trip_hold_wake_unacked() {
  # Same dead-man-alarm shape as trip_watcher_down_alarm (2026-08-09 ratified
  # amendment): a HOLD damping a seat that has gone silently unresponsive is
  # the same "deaf gap" WATCHER-DOWN exists to close, just detected via a
  # missed HOLD-CHECK ACK instead of a dead watcher PID — so it gets
  # identical auth treatment. Try to sign first (the common case — fully
  # verified like everything else, tamper still caught). ONLY on a genuine
  # signing failure does this fall back to an UNSIGNED append, loudly flagged
  # in the body, never silent. See coord-verify.sh's exemption (c) (TAG
  # starts with "⚠️ " AND the SIGNING-FAILED sentinel is the body's first
  # substantive line — shared with WATCHER-DOWN above, collapsed into one
  # sentinel exemption 2026-08-09) — a SIGNED HOLD-WAKE-UNACKED still gets
  # full verification and a tampered/forged one still hard-fails as INVALID
  # same as any other message.
  local nonce="$1" ts addressee
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  addressee=$(hold_addressee)

  # Guard: skip the append if MY_FILE is missing, but still exit — the
  # alarm's dead-man exit is unconditional; a missing presence file must not
  # suppress it.
  if [[ -f "$MY_FILE" ]]; then
    local hw_tmp; hw_tmp=$(mktemp "${TMPDIR:-/tmp}/coord-hw.XXXXXX")
    {
      printf '### %s — %s → %s — ⚠️ HOLD-WAKE-UNACKED [HOLD:%s · HOLD-CHECK:%s]\n\n' \
        "$ts" "$IDENTITY" "$addressee" "$HOLD_NAME" "$nonce"
      printf 'HOLD **%s** was damping IDLE-KICK on this seat, but HOLD-CHECK `%s` went unACKed\n' "$HOLD_NAME" "$nonce"
      printf 'for %s cadence ticks (~%ss).\n\n' "$HOLD_ACK_TICKS" "$((HOLD_ACK_TICKS * CADENCE))"
      printf 'A hold damps a seat that is still THERE. Unproven liveness under a hold is the deaf\n'
      printf 'gap this amendment exists to close, so the heartbeat self-terminates (exit 43 —\n'
      printf 'distinct from watcher-dead exit 42) to wake the dormant agent session.\n\n'
      printf 'Re-arm:\n\n    %s --identity %s --role %s --dir %s\n' \
        "$SCRIPT_ABS" "$IDENTITY" "$ROLE" "$COORD_DIR"
    } > "$hw_tmp"

    local hw_sig="" hw_signed=0
    if command -v ensure_signing_key >/dev/null 2>&1; then
      local hw_privkey; hw_privkey=$(ensure_signing_key "$HB_HOME/coord-keygen.sh" "$IDENTITY" "$COORD_DIR")
      if [[ -n "$hw_privkey" ]]; then
        hw_sig=$(sign_message_file "$hw_privkey" "$IDENTITY" "$hw_tmp")
        [[ $? -eq 0 && -n "$hw_sig" ]] && hw_signed=1
      fi
    fi

    if [[ "$hw_signed" -eq 1 ]]; then
      { printf '\n'; cat "$hw_tmp"; printf '%s' "$hw_sig"; } >> "$MY_FILE"
    else
      echo "WARN: could not sign the HOLD-WAKE-UNACKED alert — posting UNSIGNED, loudly flagged. This is a dead-man alarm the protocol never silently swallows for auth-layer reasons." >&2
      {
        printf '\n### %s — %s → %s — ⚠️ HOLD-WAKE-UNACKED [HOLD:%s · HOLD-CHECK:%s]\n\n' \
          "$ts" "$IDENTITY" "$addressee" "$HOLD_NAME" "$nonce"
        printf '[SIGNING-FAILED — unauthenticated, verify liveness by other means]\n\n'
        printf 'HOLD **%s** was damping IDLE-KICK on this seat, but HOLD-CHECK `%s` went unACKed\n' "$HOLD_NAME" "$nonce"
        printf 'for %s cadence ticks (~%ss).\n\n' "$HOLD_ACK_TICKS" "$((HOLD_ACK_TICKS * CADENCE))"
        printf 'A hold damps a seat that is still THERE. Unproven liveness under a hold is the deaf\n'
        printf 'gap this amendment exists to close, so the heartbeat self-terminates (exit 43 —\n'
        printf 'distinct from watcher-dead exit 42) to wake the dormant agent session.\n\n'
        printf 'Re-arm:\n\n    %s --identity %s --role %s --dir %s\n' \
          "$SCRIPT_ABS" "$IDENTITY" "$ROLE" "$COORD_DIR"
      } >> "$MY_FILE"
    fi
    rm -f "$hw_tmp"

    # M4: read back (tail + grep) to confirm the append persisted — window
    # wide enough to comfortably include a signed message's ~9-line SIG block.
    if ! tail -40 "$MY_FILE" 2>/dev/null | grep -q "HOLD-WAKE-UNACKED"; then
      echo "WARN: HOLD-WAKE-UNACKED alert append did not persist in $MY_FILE" >&2
    fi
  else
    echo "WARN: $MY_FILE does not exist. Skipping HOLD-WAKE-UNACKED append but still self-terminating." >&2
  fi

  echo ""
  echo "=== HOLD-WAKE-UNACKED — HEARTBEAT SELF-TERMINATING (exit 43) ==="
  echo "Hold: $HOLD_NAME   Nonce: $nonce   Unacked cadence ticks: $HOLD_ACK_TICKS"
  echo "Re-arm: $SCRIPT_ABS --identity $IDENTITY --role $ROLE --dir $COORD_DIR"
  echo "=== end hold-wake alert ==="
  exit 43
}

hold_ack_scan() {
  # Runs EVERY cadence tick, OUTSIDE the idle gate. That placement is load-bearing.
  #
  # Posting a HOLD-CHECK appends to $MY_FILE, which resets
  # seconds_since_own_file_modified to ~0. Nested under "idle >= IDLE_THRESHOLD"
  # (where the ratified draft's step 4c literally reads), this scan would not run
  # again until the seat had been idle another full IDLE_THRESHOLD — with the shipped
  # defaults that is 1200s, i.e. four cadence ticks, so a "two cadence tick" ACK
  # window is simply unreachable there. The agent's own ACK resets the clock again on
  # top of that. The deadline is cadence-based, so its scan must be cadence-driven.
  local nonce ticks
  nonce=$(cat "$HOLD_PENDING_FILE" 2>/dev/null || true)
  [[ -n "$nonce" ]] || return 0

  if [[ $HOLD_ACTIVE -ne 1 ]]; then
    # The hold cleared while a check was pending. Posting an unmarked substantive
    # message IS the liveness this check was asking for — clearing a hold must never
    # trip the alarm.
    rm -f "$HOLD_PENDING_FILE" "$HOLD_TICKS_FILE" "$HOLD_LAST_FILE"
    echo "[heartbeat] hold cleared with HOLD-CHECK $nonce pending — resolved by the clearing message."
    return 0
  fi

  # Anchored to ^### — HEADER lines only. Unanchored, this check ACKs ITSELF: the
  # HOLD-CHECK body prints the exact line the agent is supposed to post
  # ("### <ts> — … — 🤝 ACK [HOLD-CHECK:<nonce>]") as a worked example, so a
  # whole-file substring search finds its own instruction text and clears the pending
  # check on the very tick it was posted. Measured: exit 43 became unreachable and
  # the dead-man this whole amendment exists for was silently dead. The example is
  # indented inside a code block, so the ^### anchor excludes it.
  if grep -qE "^### .*ACK.*\[HOLD-CHECK:$nonce\]" "$MY_FILE" 2>/dev/null; then
    rm -f "$HOLD_PENDING_FILE" "$HOLD_TICKS_FILE"
    echo "[heartbeat] HOLD-CHECK $nonce ACKed by agent — damping continues."
    return 0
  fi

  ticks=$(( $(cat "$HOLD_TICKS_FILE" 2>/dev/null || echo 0) + 1 ))
  printf '%s' "$ticks" > "$HOLD_TICKS_FILE"
  echo "[heartbeat] HOLD-CHECK $nonce unACKed (${ticks}/${HOLD_ACK_TICKS})."
  if [[ $ticks -ge $HOLD_ACK_TICKS ]]; then
    trip_hold_wake_unacked "$nonce"
  fi
  return 0
}

# ── main loop ─────────────────────────────────────────────────────────────────

started_at=$(now_epoch)
# ALL-CHANNELS dead-man (REMOTE-SEATS.md §3.4): per-channel counters live in small
# state FILES ($STATE_DIR/<pidfile-basename>.deadticks), not in-memory bash variables
# — bash 3.2 has no associative arrays, and a discovered, variable-length SET of
# channels (today: local + optionally remote; tomorrow: possibly more) is far simpler
# to track this way than indirect variable references. Functionally identical to the
# old single in-memory counter for the single-channel (no remote armed) case: same
# GRACE, same WATCHER_DEAD_TICKS threshold, same reset-on-success semantics — just
# file-backed instead of variable-backed, which also means the counter survives this
# script's own restart (a minor extra robustness, not a behavior change that matters
# here since a restart re-derives from disk state either way).

while true; do
  sleep "$CADENCE"

  now=$(now_epoch)
  elapsed=$((now - started_at))

  if [[ $elapsed -ge $CAP ]]; then
    echo "[heartbeat] cap reached (${CAP}s elapsed). Exiting."
    echo "Re-arm to continue heartbeat monitoring:"
    echo ""
    echo "  $SCRIPT_ABS --identity $IDENTITY --role $ROLE --dir $COORD_DIR${REMOTE_HOST:+ --remote-host $REMOTE_HOST --remote-bus-dir $REMOTE_BUS_DIR}"
    exit 0
  fi

  # WATCHER DEAD-MAN SWITCH: check EVERY armed channel, every tick, before the idle
  # logic. SUSTAINED-DEATH counter — echo-and-terminate watchers are legitimately
  # dead (exited, awaiting re-arm) throughout any active wake-cycle, so a single
  # failed tick is NORMAL, not a signal. Only death sustained across
  # WATCHER_DEAD_TICKS consecutive ticks (~15 min @ default cadence) means that
  # CHANNEL has gone dormant/dead. A success at any point — including a fresh re-arm
  # mid-count, which watcher_alive's mtime-GRACE reports as "alive" immediately —
  # resets that channel's counter to 0.
  while IFS= read -r pidfile; do
    [[ -z "$pidfile" ]] && continue
    ctrfile="$STATE_DIR/$(basename "$pidfile").deadticks"
    if watcher_alive "$pidfile"; then
      printf '0' > "$ctrfile"
    else
      ticks=$(( $(cat "$ctrfile" 2>/dev/null || echo 0) + 1 ))
      printf '%s' "$ticks" > "$ctrfile"
      echo "[heartbeat] watcher check failed for channel '$(channel_label "$pidfile")' (${ticks}/${WATCHER_DEAD_TICKS})."
      if [[ $ticks -ge $WATCHER_DEAD_TICKS ]]; then
        trip_watcher_down_alarm "$pidfile"
        # trip_watcher_down_alarm always exits (42) — unreachable, but explicit for readers.
        exit 42
      fi
    fi
  done < <(discover_watcher_pidfiles)

  # B/C process-hygiene backstop (AMEND-PROCESS-HYGIENE-20260726)
  sweep_product_orphans

  # HOLD-DAMP-V2: evaluated every tick, before the idle gate, because the ACK
  # deadline is cadence-based (see hold_ack_scan for why it cannot be nested).
  detect_hold_marker
  hold_ack_scan

  idle=$(seconds_since_own_file_modified)

  if [[ $idle -ge $IDLE_THRESHOLD ]]; then
    if [[ $HOLD_ACTIVE -eq 1 ]]; then
      # Damped: no IDLE-KICK body at all. The mailbox grows only from HOLD-CHECKs.
      hold_last=$(cat "$HOLD_LAST_FILE" 2>/dev/null || true)
      if [[ -z "$hold_last" ]]; then
        # First idle tick under a fresh hold. The marker post itself just proved
        # liveness, so start the clock here rather than probing immediately.
        printf '%s' "$(now_epoch)" > "$HOLD_LAST_FILE"
        echo "[heartbeat] HOLD '$HOLD_NAME' active — IDLE-KICK damped (next HOLD-CHECK in ${HOLD_CHECK_INTERVAL}s)."
      elif [[ -s "$HOLD_PENDING_FILE" ]]; then
        # A HOLD-CHECK is already outstanding — do NOT ask again. append_hold_check
        # rewrites hold-check.ticks back to 0, so re-asking on a timer forgives the
        # missed answer: at any interval <= HOLD_ACK_TICKS * CADENCE the counter would
        # reset before it could reach its threshold and exit 43 would be unreachable.
        # A guard whose own re-arming resets its counter cannot stop anything. The
        # outstanding check owns the deadline until hold_ack_scan resolves it.
        echo "[heartbeat] HOLD '$HOLD_NAME' — awaiting the agent's ACK of the outstanding HOLD-CHECK."
      elif [[ $(( $(now_epoch) - hold_last )) -ge $HOLD_CHECK_INTERVAL ]]; then
        append_hold_check
      else
        echo "[heartbeat] HOLD '$HOLD_NAME' active — IDLE-KICK damped (idle~${idle}s)."
      fi
    else
      # Not held: drop any stale hold state so a future hold starts a clean clock.
      rm -f "$HOLD_LAST_FILE" "$HOLD_PENDING_FILE" "$HOLD_TICKS_FILE"
      append_heartbeat
    fi
    # Discover-on-idle text is now inside append_heartbeat (orch only) so the
    # agent's own coord-monitor self-nudge delivers it — stdout-only was invisible
    # to the Monitor tool (which tails coord-monitor, not this shell).
  fi
done
