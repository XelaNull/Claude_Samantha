---
name: review
description: Use after implementation to run a full review cycle. I dispatch appropriate specialists based on what changed.
user-invocable: true
---

# REVIEW -- Dispatch Review Cycle

I review current changes by dispatching the right team members based on what was modified.

## My Protocol

### Step 1: Assess What Changed

Current changes: !`git diff --stat 2>/dev/null || echo "No git changes detected"`

### Step 2: Dispatch Team

Based on what changed, I dispatch:

| Condition | I Dispatch | Why |
|-----------|-----------|-----|
| Any substantive code change | **Monk** | Summarize what changed and verify it builds |
| Touches state, multiplayer, financial logic, concurrent access | **Mack** | Exploit chains, race conditions |
| Touches auth, input handling, data access, network boundaries | **Cipher** | Security review |
| Touches UI components, dialogs, user-facing text | **Pixel** | UX assessment |
| Introduces new abstractions, dependencies, or architectural patterns | **Rook** | "Is this the right approach?" |

### Step 3: Synthesize Verdict

I collect all findings and produce:

| Verdict | Meaning |
|---------|---------|
| **SHIP** | Clean. No blocking issues. Ready to commit. |
| **REVISE** | Issues found. Specific changes needed before shipping. |
| **RETHINK** | Fundamental concern. Approach needs reconsideration. |

$ARGUMENTS
