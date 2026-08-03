#!/usr/bin/env bash
# coord-evidence-lint.sh — coord-dir evidence-presence lint.
#
# CEILING (stated so it is not later over-trusted): this lint verifies that evidence
# shaped like tool output is PRESENT next to a completion claim — not that the
# evidence is TRUE. A fabricated `state=MERGED` line still passes. Real value:
# converts "wrote a confident sentence" into "had to produce something shaped like
# output," which catches omission-style narration failures.
#
# Flags an entry (### … block) that claims MERGED / mergedAt / state / pushed /
# edited without an adjacent literal-value pattern (state=, mergedAt=, a SHA,
# a fenced code block, or a grep -n style cite).
#
# Usage:
#   coord-evidence-lint.sh [--file <mailbox.md>] [--dir <coord-dir>] [--since-bytes N]
# Exit 0 = clean; exit 1 = one or more claims lacked adjacent evidence.
set -euo pipefail

FILE=""
DIR=""
SINCE_BYTES=0

usage() {
  echo "Usage: $0 (--file <mailbox.md> | --dir <coord-dir>) [--since-bytes N]" >&2
  echo "  Ceiling: presence-of-evidence-shape, NOT truth of the claim." >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) FILE="${2:-}"; shift 2 ;;
    --dir) DIR="${2:-}"; shift 2 ;;
    --since-bytes) SINCE_BYTES="${2:-0}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

lint_one() {
  local path="$1"
  local since="${2:-0}"
  python3 - "$path" "$since" <<'PY'
import re, sys
path, since = sys.argv[1], int(sys.argv[2])
raw = open(path, encoding="utf-8", errors="replace").read()
if since > 0 and since < len(raw.encode("utf-8", errors="replace")):
    # approximate: skip leading bytes by decoding after offset
    raw_b = open(path, "rb").read()
    text = raw_b[since:].decode("utf-8", errors="replace")
else:
    text = raw

# Split on message headers
parts = re.split(r'(?m)^(### .+)$', text)
# parts: [preamble, header1, body1, header2, body2, ...]
claim_re = re.compile(
    r'\b(MERGED|mergedAt|pushed|edited|PUSHED|EDITED)\b|\bstate\s*[:=]',
    re.I,
)
# Evidence shapes: explicit assignments, SHAs, fenced blocks, grep -n cites, gh/tool JSON-ish
evidence_re = re.compile(
    r'(state\s*=\s*\S+|mergedAt\s*=\s*\S+|`[0-9a-f]{7,40}`|\b[0-9a-f]{7,40}\b'
    r'|```|grep\s+-n|\bexit_code\s*=|\bpermission["\']?\s*:'
    r'|\b\"state\"\s*:\s*\"|https://github\.com/[^\s]+/pull/\d+)',
    re.I,
)

flags = 0
i = 1
while i + 1 < len(parts):
    header, body = parts[i], parts[i + 1]
    i += 2
    window = header + "\n" + body[:4000]  # adjacent = header + start of body
    if not claim_re.search(window):
        continue
    if evidence_re.search(window):
        continue
    # claim without evidence shape
    flags += 1
    short = header.strip()[:120]
    print(f"EVIDENCE-MISSING: {path}")
    print(f"  header: {short}")
    print("  claim verbs found without adjacent literal evidence (state=/mergedAt=/SHA/fence/grep -n/PR URL)")
    print("  CEILING: presence lint only — does not prove the claim is true.")

sys.exit(1 if flags else 0)
PY
}

FAIL=0
if [[ -n "$FILE" ]]; then
  lint_one "$FILE" "$SINCE_BYTES" || FAIL=1
elif [[ -n "$DIR" && -d "$DIR" ]]; then
  for f in "$DIR"/orchestrator.md "$DIR"/impl-*.md; do
    [[ -f "$f" ]] || continue
    lint_one "$f" 0 || FAIL=1
  done
else
  usage
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "coord-evidence-lint: FAILED (one or more claims lacked evidence-shaped adjacent text)" >&2
  exit 1
fi
echo "coord-evidence-lint: OK"
exit 0
