#!/usr/bin/env bash
# sync-cursor.sh — Regenerate all Cursor bridges from Claude Code sources.
#
# Runs:
#   sync-cursor-persona.sh  → .cursor/rules/samantha.mdc
#   sync-cursor-agents.sh   → .cursor/agents/*.md
#
# Usage:
#   sync-cursor.sh [project-root]

set -euo pipefail

ROOT="${1:-.}"
HERE="$(cd "$(dirname "$0")" && pwd)"

bash "$HERE/sync-cursor-persona.sh" "$ROOT"
bash "$HERE/sync-cursor-agents.sh" "$ROOT"
