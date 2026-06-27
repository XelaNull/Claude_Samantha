#!/usr/bin/env bash
# bootstrap-identity.sh — Provisional-ID generation and identity adoption helper.
#
# DESIGN EXTENSION — not derived from the source project.
# Use during the identity bootstrap handshake when a newborn Implementer needs the
# Orchestrator to assign a stable identity. See README.md § Identity Bootstrap.
#
# USAGE:
#   Provision (run first, before arming the watcher):
#     PROV_ID=$(./bootstrap-identity.sh --provision --dir <coord-dir> [--zone <cwd>])
#
#   Adopt (run after the Orchestrator replies with ASSIGN-IDENTITY):
#     ./bootstrap-identity.sh --adopt \
#       --provisional <pending-id> --assigned <name> --dir <coord-dir>
#
# PROVISION mode:
#   1. Generates a collision-proof provisional identity IN THE SHELL (never by the model):
#        pending-<uuid>  (fallback: pending-<PID>-<epoch> if uuidgen unavailable).
#   2. Creates <coord-dir>/pending-<uuid>.md with a minimal presence header and a
#      🛰️ HEADS-UP message to the Orchestrator requesting name assignment.
#      The new file trips the Orchestrator's watcher (hub watches all .md files).
#   3. M4: reads the file back to confirm the write persisted.
#   4. Prints the provisional ID to stdout — one line, for capture via $(...).
#      All guidance text goes to stderr so the capture is clean.
#
# ADOPT mode:
#   1. Validates <coord-dir>/<provisional-id>.md exists.
#   2. Validates <coord-dir>/<assigned-name>.md does NOT exist (collision guard).
#   3. Atomically renames <provisional-id>.md → <assigned-name>.md
#      (POSIX: mv within the same directory is atomic on local filesystems).
#   4. M4: confirms the rename landed and the provisional file is gone.
#   5. Prints kill command (M2) and re-arm command to stderr.
#
# M2 NOTE: The provisional watcher records its PID in the provisional file.
#   The rename preserves that PID entry. Kill by PID before re-arming:
#     kill $(grep '^watcher_pid:' <coord-dir>/<assigned-name>.md | cut -d' ' -f2)
#   NEVER pkill -f on a shared machine — it kills peers' watchers too.

set -uo pipefail

# ── argument parsing ──────────────────────────────────────────────────────────

MODE=""
COORD_DIR=""
ZONE="${PWD}"
PROVISIONAL=""
ASSIGNED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provision)   MODE="provision"; shift ;;
    --adopt)       MODE="adopt";     shift ;;
    --dir)         COORD_DIR="$2";   shift 2 ;;
    --zone)        ZONE="$2";        shift 2 ;;
    --provisional) PROVISIONAL="$2"; shift 2 ;;
    --assigned)    ASSIGNED="$2";    shift 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$MODE" || -z "$COORD_DIR" ]]; then
  cat >&2 <<'USAGE'
ERROR: mode and --dir are required.
Usage:
  bootstrap-identity.sh --provision --dir <coord-dir> [--zone <cwd>]
  bootstrap-identity.sh --adopt --provisional <id> --assigned <name> --dir <coord-dir>
USAGE
  exit 1
fi

mkdir -p "$COORD_DIR"

# ── provision ─────────────────────────────────────────────────────────────────

do_provision() {
  # Generate a collision-proof provisional identity in the shell (never by the model).
  local suffix
  if command -v uuidgen >/dev/null 2>&1; then
    # uuidgen is available on macOS and most Linux. Strip dashes, lowercase, take 16 chars.
    suffix=$(uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '-' | head -c 16)
  else
    # Fallback: PID + epoch. Collision-resistant on a single machine.
    suffix="$$-$(date +%s)"
  fi

  local prov_id="pending-${suffix}"
  local prov_file="$COORD_DIR/$prov_id.md"

  if [[ -f "$prov_file" ]]; then
    echo "ERROR: $prov_file already exists — UUID collision (should not happen)." >&2
    exit 1
  fi

  local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local tmp; tmp=$(mktemp "$prov_file.XXXXXX")

  # Write minimal presence header + HEADS-UP message in one atomic operation.
  cat > "$tmp" <<EOF
# Presence: $prov_id
role: implementer
zone: $ZONE
state: Pending
started_at: $ts

---

## Message Log

---

### $ts — $prov_id → orchestrator — 🛰️ HEADS-UP

Newborn implementer requesting identity assignment.

zone: $ZONE
state: awaiting-name

Please reply in orchestrator.md with ASSIGN-IDENTITY addressed to $prov_id.
EOF

  mv "$tmp" "$prov_file"

  # M4: confirm the write persisted.
  if ! grep -q "awaiting-name" "$prov_file" 2>/dev/null; then
    echo "FATAL: provisional file write did not persist: $prov_file" >&2
    exit 1
  fi

  # stdout: provisional ID only — clean for $(...) capture.
  echo "$prov_id"

  # stderr: human-readable guidance (does not pollute the capture).
  {
    echo ""
    echo "[bootstrap] Provisional identity: $prov_id"
    echo "[bootstrap] File written: $prov_file"
    echo ""
    echo "[bootstrap] Arm the watcher now (Bash tool, run_in_background=true):"
    echo "  ./watch-coordination.sh --identity $prov_id --role implementer --dir $COORD_DIR"
    echo ""
    echo "[bootstrap] The watcher fires when the Orchestrator replies to $prov_id."
    echo "[bootstrap] Then adopt the assigned identity:"
    echo "  ./bootstrap-identity.sh --adopt --provisional $prov_id --assigned <name> --dir $COORD_DIR"
  } >&2
}

# ── adopt ─────────────────────────────────────────────────────────────────────

do_adopt() {
  if [[ -z "$PROVISIONAL" || -z "$ASSIGNED" ]]; then
    echo "ERROR: --adopt requires --provisional <id> and --assigned <name>." >&2
    exit 1
  fi

  # Validate assigned name is a safe filename (alphanumeric, hyphens, underscores only).
  if [[ ! "$ASSIGNED" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "ERROR: assigned name '$ASSIGNED' contains unsafe characters." >&2
    echo "Use only: a-z A-Z 0-9 - _" >&2
    exit 1
  fi

  local prov_file="$COORD_DIR/$PROVISIONAL.md"
  local final_file="$COORD_DIR/$ASSIGNED.md"

  if [[ ! -f "$prov_file" ]]; then
    echo "ERROR: provisional file not found: $prov_file" >&2
    exit 1
  fi

  if [[ -f "$final_file" ]]; then
    echo "ERROR: assigned name already taken: $final_file" >&2
    echo "The Orchestrator must pick a name not currently present in $COORD_DIR/." >&2
    exit 1
  fi

  # Atomic rename (POSIX: mv within the same directory is atomic on local filesystems).
  mv "$prov_file" "$final_file"

  # M4: confirm the rename.
  if [[ ! -f "$final_file" ]]; then
    echo "FATAL: rename did not produce $final_file" >&2
    exit 1
  fi
  if [[ -f "$prov_file" ]]; then
    echo "FATAL: provisional file still present after rename: $prov_file" >&2
    exit 1
  fi

  # stderr: guidance for next steps.
  {
    echo ""
    echo "[bootstrap] Identity adopted: $PROVISIONAL → $ASSIGNED"
    echo "[bootstrap] File: $final_file"
    echo ""
    echo "[bootstrap] Kill the provisional watcher (M2 — PID, never pkill -f):"
    echo "  kill \$(grep '^watcher_pid:' $final_file | cut -d' ' -f2)"
    echo ""
    echo "[bootstrap] Re-arm under assigned identity (Bash tool, run_in_background=true):"
    echo "  ./watch-coordination.sh --identity $ASSIGNED --role implementer --dir $COORD_DIR"
    echo ""
    echo "[bootstrap] Post ACK in $final_file:"
    printf "  ### %s — %s → orchestrator — 🤝 ACK\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$ASSIGNED"
    echo "  Identity adopted. Armed in as $ASSIGNED. Zone: $ZONE."
  } >&2
}

# ── dispatch ──────────────────────────────────────────────────────────────────

case "$MODE" in
  provision) do_provision ;;
  adopt)     do_adopt ;;
  *) echo "ERROR: unknown mode: $MODE" >&2; exit 1 ;;
esac
