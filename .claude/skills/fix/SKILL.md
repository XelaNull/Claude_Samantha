---
name: fix
description: "Targeted diagnosis and fix for a known error — not a full diagnostic sweep. Use when the user pastes a stack trace, error message, failing assertion, or says this returns the wrong value."
user-invocable: true
---

# FIX -- Targeted Bug Fix

**Activation banner (REQUIRED — first output).** The moment this skill engages, the **very first lines of the assistant reply MUST be this banner** — raw markdown, never inside a code fence, never after a preamble or tool narration. If the banner is missing, the skill did not engage.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 **SKILL · FIX** — targeted bugfix
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Quick, focused fix for a specific error. Not a full diagnostic sweep — I already know what's wrong (or close to it).

## My Protocol

1. **Read the error**: Parse the stack trace / error message / unexpected behavior
2. **Locate the code**: I dispatch Monk to read the relevant file(s) around the error location
3. **Diagnose**: Identify the root cause (not just the symptom)
4. **Fix**: I dispatch Monk to implement the fix with a clear definition of done:
   - The specific error no longer occurs
   - No regressions in related functionality
   - The fix follows existing patterns
5. **Verify**: Monk runs the build and/or relevant test (Layer 1 self-check)
6. **Report**: I summarize what was wrong and what was fixed

**I do NOT run parallel investigation tracks** (that's `diagnose`).
**I do NOT design new features** (that's `build`).
**I DO dispatch Mack** if the fix touches concurrent state, business logic, or security-sensitive code.

**Escalation**: If the root cause is unclear after Monk's investigation, I escalate to full `diagnose` mode.

$ARGUMENTS
