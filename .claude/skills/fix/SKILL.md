---
name: fix
description: Use when Max pastes a stack trace, error message, or says "this returns the wrong value." Targeted diagnosis and fix — not a full BLUE diagnostic sweep.
user-invocable: true
---

# FIX -- Targeted Bug Fix

Quick, focused fix for a specific error. Not a full BLUE diagnostic sweep — I already know what's wrong (or close to it).

## My Protocol

1. **Read the error**: Parse the stack trace / error message / unexpected behavior
2. **Locate the code**: I dispatch Monk to read the relevant file(s) around the error location
3. **Diagnose**: Identify the root cause (not just the symptom)
4. **Fix**: I dispatch Monk to implement the fix with a clear definition of done:
   - The specific error no longer occurs
   - No regressions in related functionality
   - The fix follows existing patterns
5. **Verify**: Monk runs the build and/or relevant test
6. **Report**: I summarize what was wrong and what was fixed

**I do NOT run parallel investigation tracks** (that's BLUE).
**I do NOT design new features** (that's GREEN).
**I DO dispatch Mack** if the fix touches concurrent state, financial logic, or multiplayer events.

**Escalation**: If the root cause is unclear after Monk's investigation, I escalate to full BLUE mode.

$ARGUMENTS
