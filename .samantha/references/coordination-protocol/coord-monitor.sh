#!/usr/bin/env bash
# coord-monitor.sh — persistent coordination monitor for the Monitor tool.
#
# Replaces the one-shot poll-and-EXIT watcher. Instead of exiting to wake the
# agent (which forced a re-arm after every fire and left a deaf gap in between),
# this runs FOREVER under a persistent Monitor and emits each new peer message
# to stdout. Monitor turns stdout lines into in-chat events, batching lines
# emitted within ~200ms into ONE notification — so a whole multi-line WO arrives
# as a single event carrying the FULL message text. The agent reads the message
# straight from the notification; no separate file Read, no re-arm, no deaf gap.
#
# RECEIVE PATH (phase 2, 2026-07-12): event-driven via `fswatch` when available,
# so a peer write is delivered in ~0.1s instead of poll/2 (~0.5s at --poll 1).
# A slow safety-poll (--safety-poll, default 10s) runs alongside to catch any
# coalesced/dropped fs-event and to pace the heartbeat mutual-monitor. If fswatch
# is not on PATH (or its pipeline dies), it falls back to the fixed-interval poll
# loop — no hard dependency. Both modes call the SAME sweep + emit machinery.
#
# NETWORK FILESYSTEMS (--force-poll, 2026-07-18): fswatch is built on OS-level
# filesystem-change notifications (FSEvents on macOS, inotify on Linux). Those
# notifications are LOCAL-only — a write made by a peer process on a different
# machine onto a network-mounted coord-dir (SMB/SSHFS/NFS) does NOT generate a
# local fs-event, so fswatch_loop goes silently deaf while still reporting
# itself armed. --force-poll skips fswatch entirely (even if it's on PATH) and
# runs poll_loop from the start. Polling is safe here because delta detection
# is size-based (emit_new stats + reads the file), not event-based — a plain
# stat/read sweep works identically over a network mount. Use --poll >=2 on
# network mounts: SMB/NFS client-side attribute caching can delay a remote
# writer's size change becoming visible by a couple of seconds, so treat the
# effective latency as low seconds, not milliseconds.
#
# Usage (under the Monitor tool, persistent:true):
#   coord-monitor.sh --identity orchestrator --dir <coorddir> [--poll 2] [--safety-poll 10] [--force-poll]
#
# Watches every *.md in <dir> EXCEPT the own-identity file, QUEUE.md, and
# *.archive.md — i.e. the peer outbox(es), matching the STAR no-self-watch rule.

set -u
IDENT="orchestrator"
DIR="/Users/mrathbone/github/Nebuspace/.samantha/coord"
POLL=2            # fallback poll interval (used only when fswatch is unavailable, or --force-poll)
SAFETY_POLL=10    # event-mode slow-poll backstop + heartbeat-check cadence
FORCE_POLL=0      # skip fswatch entirely and run poll_loop — for network-mounted coord-dirs
while [ $# -gt 0 ]; do
  case "$1" in
    --identity) IDENT="$2"; shift 2;;
    --dir) DIR="$2"; shift 2;;
    --poll) POLL="$2"; shift 2;;
    --safety-poll) SAFETY_POLL="$2"; shift 2;;
    --force-poll) FORCE_POLL=1; shift;;
    *) shift;;
  esac
done

STATEDIR="$DIR/.watch-state/$IDENT/monitor"
mkdir -p "$STATEDIR"

# Claim the watcher-liveness slot. heartbeat.sh and coord-status.sh both check
# <identity>/watcher.pid; writing our own PID there lets the EXISTING dead-man
# backstop watch THIS monitor — if it ever dies, the heartbeat fires exit-42 and
# the agent relaunches. Same safety net, zero new machinery. (Stop the old
# one-shot watcher BEFORE launching this, or they fight over the file.)
WATCHER_PID_FILE="$DIR/.watch-state/$IDENT/watcher.pid"
printf '%s' "$$" > "$WATCHER_PID_FILE"

# Peer files = *.md minus own outbox, the queue board, and archives.
watched() {
  local f b
  for f in "$DIR"/*.md; do
    [ -e "$f" ] || continue
    b=$(basename "$f")
    case "$b" in
      "$IDENT.md"|QUEUE.md|*.archive.md) continue;;
    esac
    printf '%s\n' "$f"
  done
}

offset_file() { printf '%s/%s.off' "$STATEDIR" "$(basename "$1")"; }
size_of() { wc -c < "$1" 2>/dev/null | tr -d ' '; }

emit_new() {
  local f="$1" of cur prev
  of=$(offset_file "$f"); cur=$(size_of "$f"); prev=$(cat "$of" 2>/dev/null || echo 0)
  [ -z "${cur:-}" ] && return 0
  if [ "$cur" -lt "$prev" ]; then
    printf '┃ COORD ⟳ %s rewritten/archived (%s→%s bytes) — baseline reset @ %s\n' \
      "$(basename "$f")" "$prev" "$cur" "$(date -u +%FT%TZ)"
    printf '%s' "$cur" > "$of"; return 0
  fi
  if [ "$cur" -gt "$prev" ]; then
    # One tight burst → Monitor batches it into a single notification carrying the whole message.
    printf '┃ COORD ▼ new message on %s · %s bytes @ %s\n' "$(basename "$f")" "$((cur-prev))" "$(date -u +%FT%TZ)"
    tail -c "+$((prev+1))" "$f"
    printf '┃ COORD ▲ end %s — re-run coord-status.sh if you acted on a DEPLOY/DECISION\n' "$(basename "$f")"
    printf '%s' "$cur" > "$of"
    # Advance the pre-commit hook's Rule-4 mailbox receipt too (ratified 2026-07-16, impl
    # PROCESS-NOTE 2026-07-15): streamed-into-chat == delivered == read, matching the retired
    # watcher's behavior — without this, a caught-up implementer gets commit-denied until a
    # manual `wc -c > receipt`. GROWTH PATH ONLY: on shrink/rotation (above) the receipt is
    # deliberately left stale-large so the hook's F6 forces one catch-up read of the new file.
    printf '%s' "$cur" > "$DIR/.watch-state/$IDENT/$(basename "$f").size"
  fi
  return 0
}

# Initialize offsets to the CURRENT end so we stream only NEW messages, never replay history.
for f in $(watched); do printf '%s' "$(size_of "$f")" > "$(offset_file "$f")"; done

# sweep: emit any new content across all peer files (idempotent; a no-op when nothing changed,
# and re-globs each pass so a newly-appearing Implementer file is auto-discovered).
sweep() { local f; for f in $(watched); do emit_new "$f"; done; }

# MUTUAL MONITORING. The heartbeat watches THIS monitor (via watcher.pid) and exit-42s if
# it dies; this monitor watches the heartbeat (via heartbeat.pid) and ALERTS in-chat if IT
# dies — while staying alive (no exit needed). So a single failure of EITHER process is
# always caught by the survivor; only a simultaneous double-death is uncovered. Alert once
# per down-transition, with a ~3-tick tolerance so a heartbeat relaunch doesn't false-alarm.
HB_PID_FILE="$DIR/.watch-state/$IDENT/heartbeat.pid"
hb_dead=0; hb_alerted=0
check_heartbeat() {
  local hp; hp=$(cat "$HB_PID_FILE" 2>/dev/null)
  if [ -n "$hp" ] && ps -p "$hp" >/dev/null 2>&1; then
    [ "$hb_alerted" = 1 ] && printf '┃ COORD ✅ heartbeat RECOVERED (pid %s) @ %s\n' "$hp" "$(date -u +%FT%TZ)"
    hb_dead=0; hb_alerted=0
  else
    hb_dead=$((hb_dead+1))
    if [ "$hb_dead" -ge 3 ] && [ "$hb_alerted" = 0 ]; then
      printf '┃ COORD ⚠️ HEARTBEAT DOWN @ %s (mutual-monitor) — the liveness backstop is gone; relaunch heartbeat.sh --identity %s (Bash run_in_background + dangerouslyDisableSandbox), then coord-status.sh to confirm BOTH ALIVE\n' "$(date -u +%FT%TZ)" "$IDENT"
      hb_alerted=1
    fi
  fi
}

# ── run modes (both call sweep + check_heartbeat; only the trigger differs) ──
poll_loop() {   # fallback: fixed-interval poll — used iff fswatch is absent, after an fswatch exit,
  # or --force-poll (network-mounted coord-dirs, where fs-events never see a remote peer's write)
  while true; do sweep; check_heartbeat; sleep "$POLL"; done
}

fswatch_loop() {   # primary: event-driven. Delivers a peer write in ~0.1s; a SAFETY_POLL-second
  # read timeout drives the slow-poll safety net + heartbeat cadence; fswatch death → fall back.
  #
  # bash 3.2 (macOS system bash) returns rc=1 from `read -t` on BOTH timeout AND EOF (the >128
  # timeout convention is 4.0+), so rc alone can't tell them apart. We capture fswatch's PID via a
  # FIFO and disambiguate with `kill -0`: fswatch ALIVE on a nonzero read = timeout (safety sweep,
  # stay in event mode); fswatch DEAD = EOF (break → caller drops to poll_loop, never going deaf).
  # -e '\.watch-state' excludes the offset dir emit_new writes to (FSEvents is recursive on macOS),
  # else every offset write would retrigger fswatch. -l 0.1 = 100ms batch latency.
  local rc _p fw_pid fifo
  fifo="$STATEDIR/fsevents.$$.fifo"
  rm -f "$fifo"; mkfifo "$fifo" 2>/dev/null || return 1     # no FIFO → caller falls back to poll
  fswatch -0 -l 0.1 -e '\.watch-state' "$DIR" > "$fifo" 2>/dev/null &
  fw_pid=$!
  # Cleanup so fswatch never orphans. TERM/INT must EXIT (an external stop = die), NOT fall through —
  # otherwise the trap kills fswatch, the read below sees EOF, and we'd wrongly drop into poll_loop and
  # survive the stop (→ a zombie second monitor at the next cutover). Only fswatch dying ON ITS OWN
  # (no signal) reaches the EOF→poll fallback path.
  trap 'kill "$fw_pid" 2>/dev/null; rm -f "$fifo"; exit 0' TERM INT
  trap 'kill "$fw_pid" 2>/dev/null; rm -f "$fifo"' EXIT
  exec 3< "$fifo"
  while true; do
    IFS= read -r -d '' -t "$SAFETY_POLL" _p <&3; rc=$?
    if [ "$rc" -ne 0 ]; then
      kill -0 "$fw_pid" 2>/dev/null || break   # nonzero + fswatch dead = EOF → fall back to poll
    fi                                          # nonzero + fswatch alive = timeout → safety sweep
    sweep; check_heartbeat                      # rc 0 (event) or timeout: both sweep
  done
  exec 3<&-
  kill "$fw_pid" 2>/dev/null; rm -f "$fifo"; trap - EXIT TERM INT
  return 0
}

if [ "$FORCE_POLL" = 1 ]; then
  MODE="poll ${POLL}s (--force-poll — fswatch skipped; use for network-mounted coord-dirs, e.g. SMB/SSHFS/NFS)"
elif command -v fswatch >/dev/null 2>&1; then
  MODE="fswatch event-driven (latency 0.1s · safety-poll ${SAFETY_POLL}s)"
else
  MODE="poll ${POLL}s (fswatch not on PATH — install it for event-driven receive)"
fi
printf '┃ coord-monitor ARMED for %s @ %s — watching: %s · MODE: %s · mutual-monitoring the heartbeat\n' \
  "$IDENT" "$(date -u +%FT%TZ)" "$(watched | xargs -n1 basename 2>/dev/null | tr '\n' ' ')" "$MODE"

if [ "$FORCE_POLL" != 1 ] && command -v fswatch >/dev/null 2>&1; then
  fswatch_loop
  printf '┃ COORD ⚠️ fswatch pipeline exited @ %s — falling back to %ss poll loop (receive still works, just slower)\n' "$(date -u +%FT%TZ)" "$POLL"
  poll_loop
else
  poll_loop
fi
