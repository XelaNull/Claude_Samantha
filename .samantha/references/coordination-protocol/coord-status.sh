#!/usr/bin/env bash
# coord-status.sh — VERIFY the orchestrator coord watcher + heartbeat are BOTH alive.
# Read-only (never launches — launching must go through the harness Bash run_in_background
# so the process is harness-tracked; a shell '&' here would NOT be). Run this AFTER any
# re-arm to turn "I launched it" into a verified "it is running" before asserting so.
#
# Usage: coord-status.sh [--identity <id>] [--dir <coorddir>]
# Exit 0 iff BOTH alive; exit 1 if either is down.

IDENT="orchestrator"
DIR="${COORD_DIR:-$PWD/.samantha/coord}"
while [ $# -gt 0 ]; do
  case "$1" in
    --identity) IDENT="$2"; shift 2;;
    --dir) DIR="$2"; shift 2;;
    *) shift;;
  esac
done

SD="$DIR/.watch-state/$IDENT"
alive() {
  local pid; pid=$(cat "$1" 2>/dev/null)
  if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
    echo "ALIVE (pid $pid, $(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' '))"
  else
    echo "DEAD"
  fi
}

W=$(alive "$SD/watcher.pid")
H=$(alive "$SD/heartbeat.pid")
echo "identity:  $IDENT"
echo "watcher:   $W"
echo "heartbeat: $H"

# ── Protocol metrics (queue-depth / PROTOCOL-VERSION / amendment-debt /
#    migration-chain) ─────────────────────────────────────────────────────────
# Printed on every status check so ratified-but-unimplemented rules stay visible.
# Sourced from a sibling coord-protocol-metrics.sh — skipped silently if absent
# (this project may not have adopted the protocol-metrics layer).
_METRICS_LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/coord-protocol-metrics.sh"
if [ -f "$_METRICS_LIB" ]; then
  # shellcheck source=/dev/null
  . "$_METRICS_LIB"
  echo "--- protocol metrics ---"
  report_protocol_meta
  report_queue_depths "$DIR"
  report_migration_chain "$DIR"
  if [ -n "${_QUEUE_SHALLOW_REPOS:-}" ]; then
    for _pair in $_QUEUE_SHALLOW_REPOS; do
      echo "⚠️ QUEUE-SHALLOW: ${_pair%%:*} ${_pair##*:} (floor ${COORD_DEPTH_FLOOR:-12})"
    done
  fi
  echo "--- end protocol metrics ---"
fi

case "$W|$H" in
  ALIVE*\|ALIVE*)
    echo "STATUS: ✅ BOTH ALIVE"
    exit 0;;
  *)
    echo "STATUS: ⚠️ DEGRADED — re-arm (watcher FIRST, then heartbeat) via harness Bash run_in_background=true, then re-run this to confirm."
    exit 1;;
esac
