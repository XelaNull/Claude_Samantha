#!/usr/bin/env bash
# coord-status.sh — VERIFY every armed coord-monitor channel + the heartbeat are alive,
# then print a read-only machine process census (AMEND-PROCESS-HYGIENE-20260726 F).
# Read-only (never launches — launching must go through the harness Bash run_in_background
# so the process is harness-tracked; a shell '&' here would NOT be). Run this AFTER any
# re-arm to turn "I launched it" into a verified "it is running" before asserting so.
#
# ALL-CHANNELS (REMOTE-SEATS.md §3.4, 2026-07-18): an identity may have more than one
# armed coord-monitor.sh channel — watcher.pid for the local channel, watcher-<name>.pid
# for any additional channel (currently just watcher-remote.pid for the §3.4 remote
# channel; the naming convention generalizes). Every watcher*.pid found is enumerated
# and checked independently. The single-channel case (only watcher.pid present, the
# common/current usage) reports the exact original "BOTH ALIVE" wording; "ALL CHANNELS
# ALIVE" only appears once there's genuinely more than one channel to report on.
#
# AMEND-PROCESS-HYGIENE D (2026-07-26): ALIVE requires process exists AND ppid≠1
# (unless COORD_ALLOW_PPID1=1). PPID=1 ⇒ ORPHAN ⇒ treat as DEAD (Cursor/shell abort
# can leave scripts reparented to launchd while notify bridge is gone).
#
# AMEND-PROCESS-HYGIENE F (2026-07-26): after per-seat lines, print STAR-wide census
# (all coord-monitor/heartbeat · duplicates · strays · PPID=1 product signatures ·
# ours-over-CPU). Reports only — never kills.
#
# Usage: coord-status.sh [--identity <id>] [--dir <coorddir>]
#   --identity <id>  check this seat; overrides SAMANTHA_IDENTITY env var
#   SAMANTHA_IDENTITY=<id>  exported seat identity; wins over built-in default
#   Default identity when neither is set: orchestrator (hub)
# Exit 0 iff every discovered channel AND the heartbeat are bridged-alive; exit 1 otherwise.
# Census WARN lines do not alone force exit 1 except DUPLICATE for THIS identity.

IDENT="${SAMANTHA_IDENTITY:-orchestrator}"
DIR="${COORD_DIR:-$PWD/.samantha/coord}"
IDENT_EXPLICIT=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      echo "Usage: coord-status.sh [--identity <id>] [--dir <coorddir>]"
      echo "  --identity <id>   check this seat (overrides SAMANTHA_IDENTITY)"
      echo "  SAMANTHA_IDENTITY=<id>  exported seat identity (overrides hub default)"
      echo "Read-only liveness + process census. Never claims a pidfile."
      exit 0
      ;;
    --identity) IDENT="$2"; IDENT_EXPLICIT=1; shift 2;;
    --dir) DIR="$2"; shift 2;;
    *) shift;;
  esac
done

# WARN if bare/default identity is being used while multiple seats are registered.
# A spoke that forgets --identity (or SAMANTHA_IDENTITY) will silently check the hub.
if [ "$IDENT_EXPLICIT" = "0" ] && [ "$IDENT" = "orchestrator" ]; then
  _ws_count=$(find "$DIR/.watch-state" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  if [ "${_ws_count:-0}" -gt 1 ] 2>/dev/null; then
    echo "WARN: checking default identity 'orchestrator' — $DIR/.watch-state/ has ${_ws_count} seat(s); spokes should pass --identity <id> or export SAMANTHA_IDENTITY"
  fi
fi

SD="$DIR/.watch-state/$IDENT"

# Return ppid for pid, or empty.
ppid_of() {
  ps -p "$1" -o ppid= 2>/dev/null | tr -d ' '
}

# Print liveness line for a pidfile to stdout. Return 0=ALIVE, 1=dead/orphan.
alive() {
  local pid ppid et
  pid=$(cat "$1" 2>/dev/null)
  if [ -z "$pid" ] || ! ps -p "$pid" >/dev/null 2>&1; then
    echo "DEAD"
    return 1
  fi
  ppid=$(ppid_of "$pid")
  et=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')
  if [ -z "${COORD_ALLOW_PPID1:-}" ] && [ "$ppid" = "1" ]; then
    echo "ORPHAN (pid $pid, ppid=1, etime=$et) — treat as DEAD; kill by recorded PID + re-arm under harness bridge"
    return 1
  fi
  echo "ALIVE (pid $pid, $et)"
  return 0
}

channel_label() {
  local b; b=$(basename "$1" .pid)
  if [ "$b" = "watcher" ]; then echo "local"; else echo "${b#watcher-}"; fi
}

echo "identity:  $IDENT"

ALL_OK=1
CHANNEL_COUNT=0
for pf in "$SD"/watcher.pid "$SD"/watcher-*.pid; do
  [ -e "$pf" ] || continue
  CHANNEL_COUNT=$((CHANNEL_COUNT + 1))
  label=$(channel_label "$pf")
  if W=$(alive "$pf"); then
    echo "watcher [$label]: $W"
  else
    echo "watcher [$label]: $W"
    ALL_OK=0
  fi
done

if H=$(alive "$SD/heartbeat.pid"); then
  echo "heartbeat: $H"
else
  echo "heartbeat: $H"
  ALL_OK=0
fi

if [ "$CHANNEL_COUNT" -eq 0 ]; then
  echo "STATUS: ⚠️ DEGRADED — no watcher pidfile found at all; re-arm coord-monitor.sh"
  # still print census below
  ALL_OK=0
fi

# ── F: process census (read-only) ─────────────────────────────────────────────
echo "--- process census ---"
# Only the real script processes — NOT the harness wrapper shells that also
# mention --identity in their command line (those falsely doubled every seat).
CENSUS_TMP=$(mktemp 2>/dev/null || echo /tmp/coord-census.$$)
ps aux 2>/dev/null | grep -E '[c]oord-monitor\.sh|[h]eartbeat\.sh' | grep -v 'snap=\$(command cat' | grep -v 'shell-snapshots' | grep -v 'builtin eval' > "$CENSUS_TMP" || true

while IFS= read -r line; do
  [ -z "$line" ] && continue
  pid=$(echo "$line" | awk '{print $2}')
  cpu=$(echo "$line" | awk '{print $3}')
  cmd=$(echo "$line" | sed 's/^[^ ]* *[0-9]* *[0-9.]* *[0-9.]* *[0-9]* *[0-9]* *[^ ]* *[^ ]* *[^ ]* *[0-9:]* *//')
  # Keep only lines whose executable path is the script (bash …/coord-monitor.sh or …/heartbeat.sh)
  case "$cmd" in
    *coord-monitor.sh*|*heartbeat.sh*) ;;
    *) continue ;;
  esac
  case "$cmd" in
    *snap=\$\(command\ cat*|*shell-snapshots*|*builtin\ eval*) continue ;;
  esac
  et=$(ps -p "$pid" -o etime= 2>/dev/null | tr -d ' ')
  ppid=$(ppid_of "$pid")
  id_flag=$(echo "$cmd" | sed -n 's/.*--identity[= ]\([^ ]*\).*/\1/p' | head -1)
  [ -z "$id_flag" ] && id_flag="?"
  kind="?"
  echo "$cmd" | grep -q 'coord-monitor' && kind="coord-monitor"
  echo "$cmd" | grep -q 'heartbeat\.sh' && kind="heartbeat"
  mark=""; [ "$id_flag" = "$IDENT" ] && mark=" ← this seat"
  orphan_mark=""; [ "$ppid" = "1" ] && orphan_mark=" ORPHAN-PPID1"
  stray_mark=""
  if echo "$cmd" | grep -qE -- '--help|-h( |$)' || [ "$id_flag" = "?" ]; then
    stray_mark=" STRAY"
  fi
  echo "  $kind  pid=$pid  id=$id_flag  cpu=${cpu}%  etime=$et  ppid=$ppid${mark}${orphan_mark}${stray_mark}"
  if echo "$cpu" | awk '{exit !($1+0 >= 50)}'; then
    echo "    WARN: OURS-HIGH-CPU (≥50%)"
  fi
done < "$CENSUS_TMP"

# Duplicates: count only real script PIDs for this identity (not wrappers)
mon_total=$(grep -c "coord-monitor\.sh.*--identity[= ]$IDENT" "$CENSUS_TMP" 2>/dev/null || echo 0)
hb_total=$(grep -c "heartbeat\.sh.*--identity[= ]$IDENT" "$CENSUS_TMP" 2>/dev/null || echo 0)
# grep -c prints 0 on no match with exit 1; normalize
mon_total=$(echo "$mon_total" | tr -d ' \n')
hb_total=$(echo "$hb_total" | tr -d ' \n')
[ -z "$mon_total" ] && mon_total=0
[ -z "$hb_total" ] && hb_total=0
if [ "$mon_total" -gt 1 ] 2>/dev/null; then
  echo "  WARN: DUPLICATE coord-monitor for identity $IDENT (count=$mon_total)"
  ALL_OK=0
fi
if [ "$hb_total" -gt 1 ] 2>/dev/null; then
  echo "  WARN: DUPLICATE heartbeat for identity $IDENT (count=$hb_total)"
  ALL_OK=0
fi
rm -f "$CENSUS_TMP"

# Product orphan signatures (PPID=1) — report only
prod_orphans=$(ps -axo pid=,ppid=,etime=,command= 2>/dev/null | awk '$2==1 && (/curses\.wrapper/ || /pty_bootstrap/) {print}' | head -20)
if [ -n "$prod_orphans" ]; then
  echo "  WARN: ORPHAN-PRODUCT candidates (PPID=1 + allowlisted signature) — report only; heartbeat may reap if age≥threshold:"
  echo "$prod_orphans" | while IFS= read -r ol; do echo "    $ol"; done
else
  echo "  orphan-product: none matched"
fi

echo "--- end census ---"

if [ "$CHANNEL_COUNT" -eq 0 ]; then
  exit 1
fi

if [ "$ALL_OK" = 1 ]; then
  if [ "$CHANNEL_COUNT" -gt 1 ]; then
    echo "STATUS: ✅ ALL CHANNELS ALIVE ($CHANNEL_COUNT watcher channel(s) + heartbeat)"
  else
    echo "STATUS: ✅ BOTH ALIVE"
  fi
  exit 0
else
  echo "STATUS: ⚠️ DEGRADED — re-arm the dead/orphan channel(s) above (watcher channel(s) first, then heartbeat if also dead) via harness Bash run_in_background=true + notify bridge, then re-run this to confirm. If ORPHAN: kill by recorded PID first."
  exit 1
fi
