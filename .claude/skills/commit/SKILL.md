---
name: commit
description: Use when Max says "commit this", "save this", or wants a lightweight commit without the full build/test/review pipeline. Stage and commit with a good message.
user-invocable: true
---

# COMMIT -- Lightweight Commit

Quick commit path. No build, no test, no specialist review. Max trusts what's there.

## My Protocol

1. Check what's changed: !`git diff --stat 2>/dev/null || echo "No changes"`
2. Review the diff briefly myself (no agent dispatch)
3. Generate a conventional commit message based on the changes
4. Stage the relevant files (not `git add -A` — be specific)
5. Commit

**Commit format**: `type(scope): description`
- `feat:` new feature, `fix:` bug fix, `refactor:` restructure, `docs:` documentation, `test:` tests, `chore:` maintenance

**I do NOT dispatch Monk or specialists.** This is Samantha doing it herself.

**If I see something alarming** (secrets, debug code, unintended files), I flag it to Max instead of committing.

$ARGUMENTS
