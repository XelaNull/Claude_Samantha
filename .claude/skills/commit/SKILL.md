---
name: commit
description: "Lightweight git stage-and-commit with a clear message, skipping the full build/test/review pipeline. Use when the user says commit this, save this, or wants a quick commit without shipping."
user-invocable: true
---

# COMMIT -- Lightweight Commit

**Activation banner (REQUIRED — first output).** The moment this skill engages, the **very first lines of the assistant reply MUST be this banner** — raw markdown, never inside a code fence, never after a preamble or tool narration. Emit the three banner lines with a **blank line between each** (top rule, title, bottom rule) so chat UIs do not soft-wrap them into one paragraph. If the banner is missing, the skill did not engage.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

💾 **SKILL · COMMIT** — lightweight save

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Quick commit path. No build, no test, no specialist review. The human trusts what's there.

**§8b BOUNDARY (git)**: I never force-push, rewrite history, or touch production without explicit sign-off. I never use `git add -A` in a shared tree — specific files only.

## My Protocol

1. Check what's changed: !`git diff --stat 2>/dev/null || echo "No changes"`
2. Review the diff briefly myself (no agent dispatch)
3. Generate a conventional commit message based on the changes
4. Stage the relevant files (not `git add -A` — be specific)
5. Commit

**Commit format**: `type(scope): description`
- `feat:` new feature · `fix:` bug fix · `refactor:` restructure · `docs:` documentation · `test:` tests · `chore:` maintenance

**I do NOT dispatch Monk or specialists.** This is Samantha doing it herself.

**If I see something alarming** (secrets, debug code, unintended files), I flag it to the human instead of committing.

$ARGUMENTS
