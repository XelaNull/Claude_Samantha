---
name: gold
description: Use after major features or when code needs quality cleanup. Proactive sweep in zone-partitioned waves. I dispatch Monk for analyze/fix waves and specialists for their categories.
user-invocable: true
---

# GOLD -- Polish Protocol

Proactive codebase quality sweep using Monk in orchestrated waves. Preventive, not reactive.

## My Protocol

### Step 1: Zone Partitioning

I partition the codebase so no two subagents write to the same file. Zones adapt to the project:

| Zone | Covers |
|------|--------|
| CORE | Core logic, models, data layer |
| SERVICES | Business logic, service layer |
| ROUTES/API | API endpoints, request handling |
| UI/FRONTEND | Components, state management, views |
| INFRASTRUCTURE | Config, build, deploy, CI/CD |
| UTILS | Helpers, utilities, shared code |

### Step 2: Issue Categories

I dispatch Monk to scan against 8 categories:

| # | Category | Sev | Pattern |
|---|----------|-----|---------|
| 1 | DEAD-CODE | LOW | Unused functions, unreachable code |
| 2 | STUB | MED | Placeholder logic, TODO markers |
| 3 | UNWIRED | HIGH | Implemented but never called |
| 4 | ERROR-HANDLING | MED | Missing guards, silent failures |
| 5 | SECURITY-GAP | HIGH | Missing validation, auth bypass |
| 6 | CONSISTENCY | LOW | Naming drift, style inconsistency |
| 7 | FRAGILE-LOGIC | HIGH | Assumptions, race conditions |
| 8 | DOCUMENTATION-DRIFT | LOW | Code diverged from docs |

For SECURITY-GAP findings, I dispatch Cipher for deeper analysis.
For FRAGILE-LOGIC findings, I dispatch Mack for exploit assessment.

### Step 3: The Convergent Loop

Each pass has two waves:

1. **Analyze wave**: I dispatch one Monk agent per zone myself — parallel Agent calls in one message, each read-only, each scanning against the 8 categories. Returns findings with file:line.
2. **I review findings** between waves. I prioritize what gets fixed vs documented.
3. **Fix wave**: I dispatch one Monk agent per zone with approved fixes. Zone partitioning prevents file conflicts.
4. **Verify**: Build succeeds, tests pass.
5. **Convergence**: Findings must decrease each pass.

**Rules:**
- Monotonic decrease required
- Max 4 passes
- 0 findings = immediate success
- Identical findings on consecutive passes = HALT

### Step 4: My Verdict

| Verdict | Meaning |
|---------|---------|
| PRISTINE | Clean pass 1 -- zero issues |
| POLISHED | Resolved by pass 2-3 |
| ACCEPTABLE | <=5 LOW unresolved at pass 4 |
| NEEDS ATTENTION | Unresolved HIGH or didn't converge |

## My Role

I review findings between analyze and fix waves. I prioritize. I challenge whether ACCEPTABLE is good enough. I decide when to halt.
