#!/usr/bin/env bash
# coord-protocol-metrics.sh — shared helpers for queue-depth / protocol-version /
# amendment-debt / migration-chain reporting.
#
# Sourced by coord-status.sh and heartbeat.sh. Safe to `bash coord-protocol-metrics.sh`
# for a standalone dump (prints metrics for --dir).
#
# All paths are CONFIGURABLE — no project-specific default is assumed. Set via
# env var before sourcing, or pass flags to the standalone invocation.
#
# shellcheck disable=SC2034

# ── configuration (env-overridable; no project-specific defaults) ────────────
: "${COORD_PROTOCOL_README:=}"                          # path to this protocol's README.md (PROTOCOL-VERSION stamp)
: "${COORD_AMENDMENTS_FILE:=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/PROTOCOL-AMENDMENTS.tsv}"
: "${COORD_DEPTH_FLOOR:=12}"                             # minimum open rows per queue-*.md before QUEUE-SHALLOW fires
: "${COORD_MIGRATIONS_DIR:=}"                            # optional: dir of migration scripts, for the disk-count fallback

# PROTOCOL-VERSION from README stamp, else from amendments header, else unknown.
protocol_version() {
  local v=""
  if [[ -n "$COORD_PROTOCOL_README" && -f "$COORD_PROTOCOL_README" ]]; then
    v=$(grep -E '^PROTOCOL-VERSION:' "$COORD_PROTOCOL_README" 2>/dev/null | head -1 | sed 's/^PROTOCOL-VERSION:[[:space:]]*//')
  fi
  if [[ -z "$v" && -f "$COORD_AMENDMENTS_FILE" ]]; then
    v=$(grep -E '^# PROTOCOL-VERSION:' "$COORD_AMENDMENTS_FILE" 2>/dev/null | head -1 | sed 's/^# PROTOCOL-VERSION:[[:space:]]*//')
  fi
  echo "${v:-unknown}"
}

# Bucket amendment rows. Sets _AMEND_OPEN / _AMEND_NA_PROMPT / _AMEND_DEFERRED.
# open = pending (and any unknown non-terminal status) — actionable work.
# n/a-prompt and deferred are permanent/parked buckets, NOT open (floor-of-N defect).
# TSV columns: id<TAB>status<TAB>title  (lines starting with # ignored)
amendments_bucket_counts() {
  _AMEND_OPEN=0
  _AMEND_NA_PROMPT=0
  _AMEND_DEFERRED=0
  [[ -f "$COORD_AMENDMENTS_FILE" ]] || return
  while IFS=$'\t' read -r _id status _rest; do
    [[ -z "$_id" || "$_id" == \#* ]] && continue
    status_lc=$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')
    case "$status_lc" in
      implemented|done|shipped) ;;
      n/a-prompt|na-prompt|n_a_prompt) _AMEND_NA_PROMPT=$((_AMEND_NA_PROMPT + 1)) ;;
      deferred) _AMEND_DEFERRED=$((_AMEND_DEFERRED + 1)) ;;
      *) _AMEND_OPEN=$((_AMEND_OPEN + 1)) ;;
    esac
  done < "$COORD_AMENDMENTS_FILE"
}

# Actionable open count only (excludes n/a-prompt + deferred).
amendments_unimplemented_count() {
  amendments_bucket_counts
  echo "${_AMEND_OPEN:-0}"
}

# Human line: "5 open · 2 n/a-prompt" (+ " · N deferred" only when deferred > 0).
amendments_unimplemented_display() {
  amendments_bucket_counts
  local line="${_AMEND_OPEN} open · ${_AMEND_NA_PROMPT} n/a-prompt"
  if [[ "${_AMEND_DEFERRED}" -gt 0 ]]; then
    line="${line} · ${_AMEND_DEFERRED} deferred"
  fi
  echo "$line"
}

# Count non-DONE / non-CLOSED rows in a single queue-*.md table.
# Uses python for robust markdown-table parsing (status column by header name).
queue_open_count() {
  local qf="$1"
  python3 - "$qf" <<'PY'
import re, sys
path = sys.argv[1]
try:
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
except OSError:
    print(0)
    sys.exit(0)

done_re = re.compile(r'\b(DONE|CLOSED)\b', re.I)
sep_re = re.compile(r'^:?-+:?$')
count = 0
status_idx = None

for ln in lines:
    s = ln.strip()
    if not s.startswith("|"):
        status_idx = None  # left a table
        continue
    cells = [c.strip() for c in s.strip("|").split("|")]
    if not cells:
        continue
    # header row: remember Status column
    if any(c.lower() == "status" for c in cells) and any(c.lower() in ("wo-n", "wo", "id", "title") for c in cells):
        status_idx = next(i for i, c in enumerate(cells) if c.lower() == "status")
        continue
    # separator
    if cells and all(sep_re.match(c or "-") for c in cells):
        continue
    if not cells[0] or cells[0].lower() in ("wo-n", "wo", "id"):
        continue
    if status_idx is None:
        # legacy: Status is typically column 3
        status_idx = 3 if len(cells) > 3 else 0
    status = cells[status_idx] if status_idx < len(cells) else " ".join(cells)
    status_plain = re.sub(r'[*_`]+', '', status)
    if done_re.search(status_plain):
        continue
    count += 1
print(count)
PY
}

# Print one line per queue-*.md: queue-<repo>: N open (floor F)
# Sets global _QUEUE_SHALLOW_REPOS as space-separated "repo:N" for shallow ones.
report_queue_depths() {
  local dir="${1:-}"
  local floor="${COORD_DEPTH_FLOOR}"
  _QUEUE_SHALLOW_REPOS=""
  [[ -n "$dir" && -d "$dir" ]] || { echo "queue-depth: (no coord dir)"; return; }
  local found=0
  local qf base repo n
  for qf in "$dir"/queue-*.md; do
    [[ -f "$qf" ]] || continue
    found=1
    base=$(basename "$qf" .md)
    repo="${base#queue-}"
    n=$(queue_open_count "$qf")
    echo "queue-depth[$repo]: $n open (floor $floor)"
    if [[ "$n" -lt "$floor" ]]; then
      _QUEUE_SHALLOW_REPOS="${_QUEUE_SHALLOW_REPOS} ${repo}:${n}"
    fi
  done
  if [[ "$found" -eq 0 ]]; then
    echo "queue-depth: (no queue-*.md found)"
  fi
  _QUEUE_SHALLOW_REPOS="${_QUEUE_SHALLOW_REPOS# }"
}

# Migration-chain signal. Prefers explicit coord-dir status file:
#   $COORD_DIR/migration-chain.status
#   unapplied: <N>
#   blocked_at: <rev>
# Optional fallback: script count under $COORD_MIGRATIONS_DIR when status absent → unknown.
# This is deliberately conservative: absence of a status file is reported as
# "unknown", never inferred as zero or as blocked.
report_migration_chain() {
  local dir="${1:-}"
  local sf=""
  [[ -n "$dir" ]] && sf="$dir/migration-chain.status"
  if [[ -n "$sf" && -f "$sf" ]]; then
    local unapplied blocked
    unapplied=$(grep -E '^unapplied:' "$sf" 2>/dev/null | head -1 | sed 's/^unapplied:[[:space:]]*//')
    blocked=$(grep -E '^blocked_at:' "$sf" 2>/dev/null | head -1 | sed 's/^blocked_at:[[:space:]]*//')
    unapplied="${unapplied:-?}"
    blocked="${blocked:-unknown}"
    echo "migration chain: ${unapplied} unapplied, blocked at ${blocked}"
    return
  fi
  # No status file — report unknown (do not invent a block from a script count alone).
  local n_vers=0
  if [[ -n "$COORD_MIGRATIONS_DIR" && -d "$COORD_MIGRATIONS_DIR" ]]; then
    n_vers=$(find "$COORD_MIGRATIONS_DIR" -maxdepth 1 -name '*.py' ! -name '__*' 2>/dev/null | wc -l | tr -d ' ')
  fi
  echo "migration chain: unknown (no migration-chain.status; migration scripts on disk: ${n_vers})"
}

report_protocol_meta() {
  local ver display
  ver=$(protocol_version)
  display=$(amendments_unimplemented_display)
  echo "PROTOCOL-VERSION: $ver"
  echo "amendments ratified-but-unimplemented: $display"
}

# Standalone dump when executed (not sourced).
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  DIR=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir) DIR="$2"; shift 2 ;;
      --readme) COORD_PROTOCOL_README="$2"; shift 2 ;;
      --amendments-file) COORD_AMENDMENTS_FILE="$2"; shift 2 ;;
      --depth-floor) COORD_DEPTH_FLOOR="$2"; shift 2 ;;
      --migrations-dir) COORD_MIGRATIONS_DIR="$2"; shift 2 ;;
      -h|--help)
        echo "Usage: $0 --dir <coord-dir> [--readme <README.md>] [--amendments-file <tsv>]"
        echo "          [--depth-floor N] [--migrations-dir <path>]"
        exit 0 ;;
      *) shift ;;
    esac
  done
  report_protocol_meta
  report_queue_depths "$DIR"
  report_migration_chain "$DIR"
  if [[ -n "${_QUEUE_SHALLOW_REPOS:-}" ]]; then
    for pair in $_QUEUE_SHALLOW_REPOS; do
      echo "⚠️ QUEUE-SHALLOW: ${pair%%:*} ${pair##*:} (floor $COORD_DEPTH_FLOOR)"
    done
  fi
fi
