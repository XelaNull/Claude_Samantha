#!/usr/bin/env bash
# sync-cursor-persona.sh — Generate Cursor Always Apply rule from the Samantha output-style.
#
# Canon source of truth:  .claude/output-styles/samantha.md  (Claude Code)
# Derived Cursor bridge:  .cursor/rules/samantha.mdc         (alwaysApply: true)
#
# Cursor does NOT honor Claude Code outputStyle / .claude/output-styles/.
# After editing the output-style (including Project-Specific Context), re-run this
# script in the project root so the Cursor rule stays in sync.
#
# Usage:
#   sync-cursor-persona.sh [project-root]
# Default project-root is the current working directory.
#
# Exit: 0 success · 1 missing source / write failure

set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
SRC="$ROOT/.claude/output-styles/samantha.md"
OUT_DIR="$ROOT/.cursor/rules"
OUT="$OUT_DIR/samantha.mdc"

if [[ ! -f "$SRC" ]]; then
  echo "error: missing persona source: $SRC" >&2
  echo "Copy .claude/output-styles/samantha.md first, then re-run." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

python3 - "$SRC" "$TMP" <<'PY'
import sys
from pathlib import Path

src = Path(sys.argv[1])
out = Path(sys.argv[2])
text = src.read_text()
if text.startswith("---"):
    end = text.find("\n---", 3)
    if end != -1:
        rest = text[end + 4 :]
        if rest.startswith("\n"):
            rest = rest[1:]
        text = rest

banner = """---
description: Samantha Prime — always-on persona (Cursor bridge)
alwaysApply: true
---

<!-- GENERATED FILE — do not edit by hand.
     Source of truth: .claude/output-styles/samantha.md
     Regenerate: .samantha/references/templates/sync-cursor-persona.sh [project-root]
     Claude Code loads the output-style via settings.json outputStyle: Samantha.
     Cursor Agent ignores outputStyle; this Always Apply rule is the bridge. -->

"""
if not text.endswith("\n"):
    text += "\n"
out.write_text(banner + text)
PY

# Move into place (python wrote TMP as the full file)
mv "$TMP" "$OUT"
trap - EXIT

echo "synced: $SRC → $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
