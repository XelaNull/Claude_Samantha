---
name: coordination-hook-audit
description: Security audit of git-pre-commit.sh — coordination protocol hook; key attack surface and confirmed findings
metadata:
  type: project
---

Audited `.samantha/references/coordination-protocol/git-pre-commit.sh` (257 lines, template that ships to all projects via Reference Pack).

**Why:** Template propagation means any weakness here multiplies across every project that adopts the coordination protocol.

**How to apply:** When reviewing hook updates, check these confirmed weak points first before assessing new code.

## Confirmed Findings (2026-06-27)

**CRITICAL (line 168):** `MY_ID` interpolated unescaped into `_addr_pattern` for `grep -cE`. Invalid ERE bracket class in MY_ID (e.g., `feature[1`) causes grep to exit 2; `2>/dev/null` + `|| echo 0` silently sets `unread=0` → mailbox gate passes on all commits. Also enables DoS via over-matching regex.

**HIGH (lines 95–99):** grep/sed fallback's `[^"]*` stops at first literal `"` in JSON. Command `VAR="x" && git commit` truncates to `VAR=\` — not recognized as a commit. Hook exits 0, all three checks skipped. Only triggers when python3 absent.

**MED:** `\x27` and `\s` are not POSIX ERE — fail on macOS BSD grep, silently disabling token/password pattern matching. `sk-[a-zA-Z0-9]{32,}` misses Anthropic (`sk-ant-api03-...`) and OpenAI new format (`sk-proj-...`) due to hyphens in key body. GCP, Azure, JWT, DB DSN, fine-grained PAT patterns entirely absent.

**MED:** Receipt file is a plain integer with no integrity check — write access to `COORD_DIR/.watch-state/<id>/` = permanent mailbox gate bypass.

**LOW:** Dangerous-verb check (lines 195–207) emits WARN but does not set `FAIL=1`, contradicting Rule 1 language in comments. `echo "$STAGED_DIFF"` should be `printf '%s\n'` for portability.

## Attack Surface Map
- `MY_ID` → regex injection (lines 168–170) — HIGHEST priority fix
- `COORD_DIR` → filesystem path, quoted throughout, low risk
- `BASH_CMD` / `CLAUDE_TOOL_INPUT` → extracted via python3 (safe) or grep/sed (bypass risk)
- Receipt files → integrity gap, requires local write access
- Pattern array → false-negative coverage gaps, not injection risk

[[reference-pack-structure]]
