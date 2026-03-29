---
name: ship
description: Use when work is done and ready to commit. Full verification pipeline -- build, test, review, then commit if clean.
user-invocable: true
---

# SHIP -- Pre-Commit Verification Pipeline

Full verification before committing. I don't ship without confidence.

## My Protocol

### Step 1: Build

I dispatch Monk to run the project build. Must pass cleanly.

### Step 2: Test

I dispatch Monk to run the test suite. No new failures allowed.

### Step 3: Review

I run the REVIEW skill -- dispatching specialists based on what changed.

### Step 4: Decision

| All pass? | Action |
|-----------|--------|
| Yes | Stage changes, commit with conventional format, report to the human |
| No | Report what failed, list specific fixes needed, do NOT commit |

### Current State

Changes pending: !`git diff --stat 2>/dev/null || echo "No changes detected"`

$ARGUMENTS
