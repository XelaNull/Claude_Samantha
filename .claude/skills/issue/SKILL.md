---
name: indigo
description: Use when the human references a GitHub issue, pastes an issue link, or says fix issue N. Full resolution pipeline with diagnosis, planning, skeptical review, implementation, and verification.
user-invocable: true
argument-hint: [issue-number-or-url]
---

# INDIGO -- GitHub Issue Resolution Pipeline

Full end-to-end issue fix: diagnose, plan, skeptically review, implement, verify, communicate.

## My Protocol

### Phase 1: RECON (BLUE-style)

I dispatch Monk to:
- Read the issue (reproduce context, reporter's environment)
- Run targeted BLUE diagnostics on the reported area
- Check recent commits for regressions
- Identify root cause (or top 3 candidates)

**Output**: Root cause hypothesis with evidence.

### Phase 2: PLAN (GREEN Stages 1-4)

I follow GREEN's first 4 stages:
1. Gap Analysis — what's broken vs what should work
2. Codebase Exploration — read affected files
3. Design — propose the fix
4. Plan — implementation steps

**MY GATE**: I approve the fix plan before implementation.

### Phase 3: SKEPTICAL REVIEW

I dispatch 3-5 skeptic agents in parallel:
- Mack as the primary skeptic (exploit chains, race conditions)
- Cipher if the fix touches security-sensitive code
- Rook if the fix introduces new abstractions

Each independently asks:
- "Will this fix actually resolve the reported issue?"
- "Could this fix break something else?"
- "Is there a simpler fix?"
- "Root cause or symptom?"

I synthesize feedback. Adjust plan if needed.

### Phase 4: IMPLEMENT (GREEN Stage 5)

I dispatch Monk to execute the approved plan. For 4+ files across subsystems, I dispatch parallel Monk agents myself (one per zone). Monk does NOT commit — he returns changes to me.

**Commit format**: `fix(module): Description (#N)` — reference issue but do NOT use `Closes #N` or `Fixes #N` (auto-close before reporter verifies).

### Phase 5: VERIFY (RED + GOLD)

1. Build & test — no new failures
2. I dispatch Monk for targeted GOLD sweep on changed files
3. Cipher spot-check if fix touches auth/input/data
4. Regression check — related features still work

### Phase 6: COMMUNICATE

I draft the GitHub comment:
- **Match the reporter's language** (full response in their language, English recap in `<details>`)
- **Humble certainty** — "This should resolve the issue -- please let us know if it persists"
- **Be polite** — "please" and "thank you"
- Set project status to **Fixed** (not Done)

## Checklist

- [ ] Issue read and understood
- [ ] BLUE recon completed (root cause identified)
- [ ] Fix designed and planned (GREEN stages 1-4)
- [ ] I approved the plan
- [ ] Skeptical review completed
- [ ] Monk dispatched for implementation
- [ ] Verification passed
- [ ] Issue commented in reporter's language
