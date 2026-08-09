#!/usr/bin/env bash
# Coordination protocol smoke tests (bash 3.2). Usage: ./tests/run.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../coord-address-filter.sh
. "$ROOT/coord-address-filter.sh"
# shellcheck source=../PROTOCOL-VERSION
. "$ROOT/PROTOCOL-VERSION"

PASS=0
FAIL=0
assert_eq() {
  local name="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    printf 'PASS %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf 'FAIL %s\n  got:  %s\n  want: %s\n' "$name" "$got" "$want"
    FAIL=$((FAIL + 1))
  fi
}
assert_contains() {
  local name="$1" hay="$2" needle="$3"
  case "$hay" in
    *"$needle"*) printf 'PASS %s\n' "$name"; PASS=$((PASS + 1)) ;;
    *) printf 'FAIL %s (missing %s)\n' "$name" "$needle"; FAIL=$((FAIL + 1)) ;;
  esac
}
assert_not_contains() {
  local name="$1" hay="$2" needle="$3"
  case "$hay" in
    *"$needle"*) printf 'FAIL %s (unexpected %s)\n' "$name" "$needle"; FAIL=$((FAIL + 1)) ;;
    *) printf 'PASS %s\n' "$name"; PASS=$((PASS + 1)) ;;
  esac
}

assert_eq "protocol-version-file" "$PROTOCOL_VERSION" "1.3.0"
assert_eq "project-of-impl-sectorwars" "$(protocol_project_of_identity impl-sectorwars)" "sectorwars"
assert_eq "project-of-impl-sectorwars-ui" "$(protocol_project_of_identity impl-sectorwars-ui)" "sectorwars"
assert_eq "project-of-impl-aiclient" "$(protocol_project_of_identity impl-aiclient)" "aiclient"

AICLIENT=$(cat <<'EOF'

### 2026-08-09T12:00:00Z — orchestrator → impl-aiclient — 🤝 HANDOFF

**WO for aiclient only**
EOF
)
SW_SIB=$(cat <<'EOF'

### 2026-08-09T12:00:01Z — orchestrator → impl-sectorwars-ui — 🤝 HANDOFF

**WO for sibling Sectorwars seat**
EOF
)
SW_ME=$(cat <<'EOF'

### 2026-08-09T12:00:02Z — orchestrator → impl-sectorwars — 🤝 HANDOFF

**WO for me**
EOF
)
ALL=$(cat <<'EOF'

### 2026-08-09T12:00:03Z — orchestrator → ALL — 🔧 DEPLOY-WINDOW OPEN

Global broadcast
EOF
)
HUB_SELF=$(cat <<'EOF'

### 2026-08-09T12:00:04Z — orchestrator → orchestrator — 💓 HEARTBEAT [self-nudge]

⚡ **IDLE-KICK** hub only
EOF
)
MIXED="${AICLIENT}${SW_SIB}${SW_ME}${ALL}${HUB_SELF}"

if filtered=$(spoke_filter_delta "impl-sectorwars" "sectorwars" "$AICLIENT"); then
  assert_eq "other-project-silent" "emitted" "silent"
else
  assert_eq "other-project-silent" "silent" "silent"
fi

if filtered=$(spoke_filter_delta "impl-sectorwars" "sectorwars" "$SW_SIB"); then
  assert_contains "same-project-sibling-handoff" "$filtered" "sibling Sectorwars"
else
  assert_eq "same-project-sibling-handoff" "silent" "emitted"
fi

if filtered=$(spoke_filter_delta "impl-sectorwars" "sectorwars" "$SW_ME"); then
  assert_contains "self-handoff" "$filtered" "WO for me"
else
  assert_eq "self-handoff" "silent" "emitted"
fi

if filtered=$(spoke_filter_delta "impl-sectorwars" "sectorwars" "$ALL"); then
  assert_contains "all-broadcast" "$filtered" "DEPLOY-WINDOW OPEN"
else
  assert_eq "all-broadcast" "silent" "emitted"
fi

if filtered=$(spoke_filter_delta "impl-sectorwars" "sectorwars" "$HUB_SELF"); then
  assert_eq "hub-self-nudge-silent" "emitted" "silent"
else
  assert_eq "hub-self-nudge-silent" "silent" "silent"
fi

if filtered=$(spoke_filter_delta "impl-sectorwars" "sectorwars" "$MIXED"); then
  assert_contains "mixed-keeps-sibling" "$filtered" "sibling Sectorwars"
  assert_contains "mixed-keeps-self" "$filtered" "WO for me"
  assert_contains "mixed-keeps-all" "$filtered" "DEPLOY-WINDOW OPEN"
  assert_not_contains "mixed-drops-aiclient" "$filtered" "aiclient only"
  assert_not_contains "mixed-drops-hub-nudge" "$filtered" "hub only"
else
  assert_eq "mixed" "silent" "emitted"
fi

# Watch-set simulation: same-project peers listed, other project not
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP"
touch "$TMP/orchestrator.md" "$TMP/impl-sectorwars.md" "$TMP/impl-sectorwars-ui.md" "$TMP/impl-aiclient.md"
PROJECT=sectorwars
IDENT=impl-sectorwars
DIR=$TMP
ROLE=implementer
# inline watched() copy of monitor logic
watched_sim() {
  local f b p
  f="$DIR/orchestrator.md"; [ -e "$f" ] && printf '%s\n' "$f"
  for f in "$DIR"/impl-*.md; do
    [ -e "$f" ] || continue
    b=$(basename "$f" .md)
    [ "$b" = "$IDENT" ] && continue
    p=$(protocol_project_of_identity "$b")
    [ "$p" = "$PROJECT" ] || continue
    printf '%s\n' "$f"
  done
}
WATCH_LIST=$(watched_sim | xargs -n1 basename | tr '\n' ' ')
assert_contains "watch-has-hub" "$WATCH_LIST" "orchestrator.md"
assert_contains "watch-has-sibling" "$WATCH_LIST" "impl-sectorwars-ui.md"
assert_not_contains "watch-excludes-self" "$WATCH_LIST" "impl-sectorwars.md"
assert_not_contains "watch-excludes-other-project" "$WATCH_LIST" "impl-aiclient.md"

# 0c evidence refresh
MB="$TMP/orch.md"
cat > "$MB" <<'EOF'
role: orchestrator
watcher_pid: 12
heartbeat_pid: 34
state: Active

---
EOF
before=$(wc -c < "$MB" | tr -d ' ')
sed -i.bak 's/watcher_pid: 12/watcher_pid: 123456/' "$MB"
after=$(wc -c < "$MB" | tr -d ' ')
delta=$((after - before))
{
  printf '# Offset evidence (Phase 0c)\n\n'
  printf 'Measured on %s · PROTOCOL %s\n\n' "$(date -u +%FT%TZ)" "$PROTOCOL_VERSION"
  printf 'Header PID widen: %s → %s (delta %+d). Presence-split (Phase 4) removes this class.\n' "$before" "$after" "$delta"
} > "$ROOT/tests/OFFSET-EVIDENCE.md"
assert_eq "0c-notes" "$(test -s "$ROOT/tests/OFFSET-EVIDENCE.md" && echo yes)" "yes"

# Presence sidecar smoke
PRES_DIR="$TMP/pres-coord"
mkdir -p "$PRES_DIR"
# shellcheck source=../coord-presence.sh
. "$ROOT/coord-presence.sh"
presence_set "$PRES_DIR" "impl-sectorwars" "watcher_pid" "99"
presence_set "$PRES_DIR" "impl-sectorwars" "project" "sectorwars"
assert_eq "presence-get-pid" "$(presence_get "$PRES_DIR" "impl-sectorwars" "watcher_pid")" "99"
assert_eq "presence-get-project" "$(presence_get "$PRES_DIR" "impl-sectorwars" "project")" "sectorwars"

printf '\n%d passed, %d failed · PROTOCOL %s\n' "$PASS" "$FAIL" "$PROTOCOL_VERSION"
[ "$FAIL" -eq 0 ]
