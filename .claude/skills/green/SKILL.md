---
name: green
description: Use for additive features that don't exist yet. 6-stage pipeline from gap analysis through verification. I gate Stage 3 design approval and dispatch Monk for Stage 5 implementation.
user-invocable: true
---

# GREEN -- Feature Gap Resolution Protocol

I resolve feature gaps -- capabilities that should exist but don't. 6-stage process, no shortcuts.

## My Protocol

**RULE**: Follow all 6 stages in order. Do NOT skip stages — unless the fast path applies.

### Fast Path (Small Changes)

If the gap is contained to a single file and requires no schema/API/architecture changes, I compress Stages 1-4 into a single assessment: describe what's missing, confirm it fits existing patterns, and move to implementation. The gate still exists — I still approve before code — but it's a 30-second check, not a multi-agent design review. I do NOT dispatch Rook for small changes.

### Stage 1: GAP ANALYSIS -- Define What's Missing

I articulate what exists vs what's needed:
- **Current behavior**: What happens now
- **Expected behavior**: What should happen
- **Constraints**: What must NOT change

### Stage 2: CODEBASE EXPLORATION -- Understand the System

I dispatch Monk for read-only exploration. He identifies affected files, existing patterns, and impact.

**Output**: Relevant files, current code path, patterns to follow, impact assessment.

### Stage 3: DESIGN -- Architecture & Edge Cases

I design before coding. I consider:
- Architecture and data flow
- Schema/data changes (migrations needed?)
- API design (consistent with existing patterns?)
- Frontend/UI structure and state management
- Security implications
- Edge cases (missing data, concurrent access, race conditions)

**MY GATE (REQUIRED)**: I approve before any code is written. I check:
- [ ] Fits existing patterns?
- [ ] Simplest solution that works?
- [ ] Edge cases identified?
- [ ] Security considered?
- [ ] User impact assessed?

For major architectural decisions, I dispatch Rook for a second opinion.
If the feature has UI, I dispatch Pixel for UX input on the design.

### Stage 4: PLAN -- Implementation Steps

I turn the design into a numbered checklist (via EnterPlanMode or task list):
- Dependency-ordered changes
- Migration planning (if needed)
- Verification steps

I write the plan to `.samantha/plans/{name}.md` and symlink `.samantha/plan.md`.

### Stage 5: IMPLEMENT -- Execute the Plan

I dispatch Monk to implement the approved plan.

**Dispatch rules:**
- **4+ files across multiple subsystems** — I dispatch parallel Monk agents myself (one per zone, all in one message). Monk cannot spawn subagents.
- **Small plans (<=3 files)** — I dispatch one Monk. I use SendMessage to reuse the Stage 2 Monk if applicable.

**I include the dispatch context block** (from CLAUDE.md) with the plan content, file paths from Stage 2, and acceptance criteria from Stage 3.

**Rules during implementation:**
- Follow existing patterns
- Never generate mock data or fallback implementations
- Monk does NOT commit — he returns changes to me for review

### Stage 6: VERIFY -- Confirm Gap Closed

I review Monk's output. ALL must pass:
1. Project builds without errors
2. Tests pass (no new failures)
3. Existing features still work (no regressions)
4. Expected behavior achieved
5. Constraints not violated

I dispatch specialists based on what changed:
- Mack: if it touches state, multiplayer, or financial logic
- Cipher: if it touches auth or input handling
- Pixel: if it has user-facing UI

## Checklist

- [ ] Gap statement defined
- [ ] Codebase explored via Monk
- [ ] Design approved at my gate (Stage 3)
- [ ] Rook consulted if major architectural decision
- [ ] Plan written to .samantha/plans/
- [ ] Monk dispatched for implementation (Stage 5)
- [ ] All verification criteria pass (Stage 6)
- [ ] Specialists dispatched based on change scope
