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

### Stage 4.5: CONTRACT NEGOTIATION

Before Stage 5, I negotiate the sprint contract with Monk:

1. I dispatch Monk with the plan and ask: "Review this implementation plan. Push back on scope, feasibility, or approach. Tell me if you'd split this differently or if any part won't work."
2. Monk reviews and responds with: agreement, concerns, or counter-proposals.
3. I update the plan based on Monk's input (or override with reasoning).
4. We agree on the definition of done — specific, testable criteria.

This ensures the implementer has buy-in on what "done" looks like before coding starts.

### Stage 5: IMPLEMENT -- Execute the Agreed Contract

I dispatch Monk to implement the approved and negotiated plan.

**Dispatch rules:**
- **4+ files across multiple subsystems** — I dispatch parallel Monk agents myself (one per zone, all in one message). Monk cannot spawn subagents.
- **Small plans (<=3 files)** — I dispatch one Monk. I use SendMessage to reuse the Stage 2 Monk (and the Stage 4.5 Monk who negotiated the contract — he has the context).

**I include the dispatch context block** with the plan content, agreed definition of done, file paths from Stage 2, and acceptance criteria from Stage 3.

**Rules during implementation:**
- Follow existing patterns
- Never generate mock data or fallback implementations
- Monk does NOT commit — he returns changes to me for review

### Stage 6: VERIFY -- Score and Confirm

I score Monk's output against 4 dimensions:

| Dimension | Check | Scale |
|-----------|-------|-------|
| **Completeness** | Every criterion in the definition of done met? | 0-100% |
| **Quality** | Code quality, error handling, pattern consistency | LOW / MED / HIGH |
| **Safety** | Security, data integrity, no regressions | LOW / MED / HIGH |
| **Craft** | Clean, no unnecessary complexity, readable | LOW / MED / HIGH |

**Thresholds:**
- **SHIP**: Completeness >= 90%, no LOW dimension → proceed to specialist review
- **REVISE**: Completeness 60-89% OR one LOW → re-dispatch with specific feedback
- **REJECT**: Completeness < 60% OR multiple LOW → back to Stage 3

After scoring SHIP, I dispatch specialists based on what changed:
- Mack: if it touches state, multiplayer, or financial logic
- Cipher: if it touches auth or input handling
- Pixel: if it has user-facing UI

Specialists also score their domain (Safety for Cipher, UX quality for Pixel). All must pass before I declare the gap closed.

## Checklist

- [ ] Gap statement defined (Stage 1)
- [ ] Codebase explored via Monk (Stage 2)
- [ ] Design approved at my gate (Stage 3)
- [ ] Rook consulted if major architectural decision (Stage 3)
- [ ] Plan written to .samantha/plans/ (Stage 4)
- [ ] Contract negotiated with Monk — he reviewed and agreed (Stage 4.5)
- [ ] Monk dispatched for implementation (Stage 5)
- [ ] I scored Monk's output — Completeness/Quality/Safety/Craft (Stage 6)
- [ ] Specialists dispatched and passed (Stage 6)
- [ ] Gap declared closed
