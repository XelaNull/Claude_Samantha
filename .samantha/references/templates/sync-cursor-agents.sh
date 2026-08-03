#!/usr/bin/env bash
# sync-cursor-agents.sh — Generate Cursor subagent defs from Claude Code agents.
#
# Canon source of truth:  .claude/agents/*.md   (Claude Code)
# Derived Cursor bridge:  .cursor/agents/*.md   (Cursor; wins over .claude/ on name clash)
#
# Cursor discovers `.claude/agents/` for Claude compatibility, but its documented
# `model` field wants `inherit` or a Cursor model ID — not Claude Code aliases
# (`sonnet` / `opus` / `haiku`). This sync:
#   - maps those aliases to Cursor Anthropic IDs
#   - keeps name / description / readonly
#   - drops Claude-only frontmatter (tools, memory, hooks)
#
# After editing any `.claude/agents/*.md` (including Project-Specific Extensions),
# re-run this script so the Cursor copies stay in sync.
#
# Usage:
#   sync-cursor-agents.sh [project-root]
# Default project-root is the current working directory.
#
# Exit: 0 success · 1 missing source dir / write failure

set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
SRC_DIR="$ROOT/.claude/agents"
OUT_DIR="$ROOT/.cursor/agents"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "error: missing agents source dir: $SRC_DIR" >&2
  echo "Copy .claude/agents/ first, then re-run." >&2
  exit 1
fi

shopt -s nullglob
SOURCES=("$SRC_DIR"/*.md)
if [[ ${#SOURCES[@]} -eq 0 ]]; then
  echo "error: no .md agents in $SRC_DIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

python3 - "$SRC_DIR" "$OUT_DIR" <<'PY'
import re
import sys
from pathlib import Path

src_dir = Path(sys.argv[1])
out_dir = Path(sys.argv[2])

# Claude Code alias → Cursor model ID (Anthropic IDs Cursor accepts).
# Pass-through for inherit / already-qualified IDs. Unknown → inherit + warn.
MODEL_MAP = {
    "opus": "claude-opus-5",
    "sonnet": "claude-sonnet-5",
    "haiku": "claude-haiku-4-5",
    "inherit": "inherit",
}

BANNER = """<!-- GENERATED FILE — do not edit by hand.
     Source of truth: .claude/agents/{name}.md
     Regenerate: .samantha/references/templates/sync-cursor-agents.sh [project-root]
     Claude Code loads .claude/agents/; Cursor prefers .cursor/agents/ when both exist.
     This copy maps Claude model aliases to Cursor model IDs and drops Claude-only
     frontmatter (tools, memory, hooks). -->
"""


def split_frontmatter(text: str):
    if not text.startswith("---"):
        return None, text
    end = text.find("\n---", 3)
    if end == -1:
        return None, text
    fm = text[3:end].lstrip("\n")
    body = text[end + 4 :]
    if body.startswith("\n"):
        body = body[1:]
    return fm, body


def extract_field(fm, key):
    # Quoted string (supports \" and \\ only — keep UTF-8 as-is)
    m = re.search(
        rf'^{re.escape(key)}:\s*"((?:\\.|[^"\\])*)"\s*$',
        fm,
        re.M,
    )
    if m:
        return m.group(1).replace("\\\"", '"').replace("\\\\", "\\")
    # Single-quoted
    m = re.search(rf"^{re.escape(key)}:\s*'([^']*)'\s*$", fm, re.M)
    if m:
        return m.group(1)
    # Bare token / boolean
    m = re.search(rf"^{re.escape(key)}:\s*(\S+)\s*$", fm, re.M)
    if m:
        return m.group(1)
    return None


def map_model(raw, agent_name):
    if not raw:
        print(f"warn: {agent_name}: no model in source; using inherit", file=sys.stderr)
        return "inherit"
    key = raw.strip().strip("\"'")
    lower = key.lower()
    if lower in MODEL_MAP:
        return MODEL_MAP[lower]
    # Already a provider-style ID (or Cursor-specific)
    if (
        lower.startswith("claude-")
        or lower.startswith("gpt-")
        or lower.startswith("composer-")
        or lower.startswith("gemini-")
        or "[" in key  # model params e.g. claude-opus-5[effort=high]
    ):
        return key
    print(
        f"warn: {agent_name}: unknown model {key!r}; using inherit",
        file=sys.stderr,
    )
    return "inherit"


def yaml_quote(s: str) -> str:
    esc = s.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{esc}"'


managed = set()
for src in sorted(src_dir.glob("*.md")):
    text = src.read_text()
    fm, body = split_frontmatter(text)
    if fm is None:
        print(f"warn: {src.name}: no frontmatter; skipping", file=sys.stderr)
        continue

    name = extract_field(fm, "name") or src.stem
    description = extract_field(fm, "description") or ""
    model = map_model(extract_field(fm, "model"), name)
    readonly = extract_field(fm, "readonly")

    lines = ["---", f"name: {name}"]
    if description:
        lines.append(f"description: {yaml_quote(description)}")
    lines.append(f"model: {model}")
    if readonly is not None and str(readonly).lower() in ("true", "false"):
        lines.append(f"readonly: {str(readonly).lower()}")
    lines.append("---")
    lines.append("")
    lines.append(BANNER.format(name=src.stem))
    lines.append("")
    if not body.endswith("\n"):
        body += "\n"
    out = out_dir / src.name
    out.write_text("\n".join(lines) + "\n" + body)
    managed.add(out.name)
    print(f"synced: {src} → {out} (model={model})")

# Remove previously generated Cursor agents whose source disappeared.
for dest in sorted(out_dir.glob("*.md")):
    if dest.name in managed:
        continue
    try:
        head = dest.read_text(encoding="utf-8", errors="replace")[:400]
    except OSError:
        continue
    if "GENERATED FILE" in head and "sync-cursor-agents.sh" in head:
        dest.unlink()
        print(f"removed stale generated: {dest}")
PY

echo "done: $(ls -1 "$OUT_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ') agent(s) in $OUT_DIR"
