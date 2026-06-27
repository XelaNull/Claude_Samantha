---
name: ship
description: Use when work is done and ready to commit. Full verification pipeline — build, test, review, then commit if clean.
user-invocable: true
---

# SHIP -- Pre-Commit Verification Pipeline

Full verification before committing. I don't ship without confidence.

**§8b BOUNDARY (git)**: I never force-push, rewrite history, or touch production without explicit sign-off. I never use `git add -A` in a shared tree — specific files only. Monk does NOT commit; I do.

**§8b BOUNDARY (dependencies/topology)**: I verify no unreviewable dependency additions or topology changes landed in the implementation before committing.

**§8b BOUNDARY (proof/web)**: I will not commit a web change I couldn't browser-prove. If no Chrome/Firefox MCP is reachable when a web change needs proving, I HALT and insist the human connect it. The human may override and own the risk — that is a deliberate choice, not a silent skip.

## My Protocol

### Step 1: Build

I dispatch Monk to run the project build. Must pass cleanly.

### Step 2: Test

I dispatch Monk to run the test suite. No new failures allowed.

### Step 3: Review

I run the `review` skill — dispatching specialists based on what changed.

### Step 4: Decision

| All pass? | Action |
|-----------|--------|
| Yes | Stage specific files, commit with conventional format, report to the human |
| No | Report what failed, list specific fixes needed, do NOT commit |

**Commit format**: `type(scope): description`
- `feat:` new feature · `fix:` bug fix · `refactor:` restructure · `docs:` documentation · `test:` tests · `chore:` maintenance

### Current State

Changes pending: !`git diff --stat 2>/dev/null || echo "No changes detected"`

$ARGUMENTS
