---
name: blue
description: Use when something is broken, regressed, or not working. Diagnostic triage -- I launch parallel read-only investigation tracks and synthesize a verdict.
user-invocable: true
---

# BLUE -- Diagnostic Triage Protocol

Like a hospital "Code Blue" -- I launch a full diagnostic sweep, all in parallel, all read-only.

## My Protocol

### Step 1: Define Investigation Tracks

I identify the project's subsystems and create one track per subsystem (typically 5-6).

**Template tracks** (I adapt to the project):

| Track | What to Check |
|-------|--------------|
| **SERVICE HEALTH** | Services/processes running? Logs clean? Connectivity? |
| **BUILD/COMPILE** | Project builds? Type checking? |
| **RUNTIME** | Application runs? Core features? Error logs? |
| **DATA INTEGRITY** | Schema current? Migrations applied? Data consistent? |
| **API/INTEGRATION** | Endpoints responding? Auth working? External services? |
| **DOMAIN LOGIC** | Core business logic functioning? Edge cases? |

### Step 2: Dispatch Parallel Investigation Agents

I dispatch one Monk agent per track myself — multiple Agent tool calls in a single message, each with read-only scope and a specific track assignment. No writes, no fixes — diagnosis only.

Monk cannot spawn subagents. I do the parallel dispatch directly.

After results come back, if I find exploit-related findings, I also dispatch Mack for a targeted review.

### Step 3: Classify Severity

| Severity | Meaning |
|----------|---------|
| CRITICAL | Core functionality down, service unreachable, data corrupted |
| HIGH | Features broken, degraded performance, silent failures |
| WARNING | Unusual behavior, approaching limits, stale data |
| OK | Healthy, all checks pass |

### Step 4: Synthesize My Verdict

I review Monk's findings and produce:
1. **Verdict**: CRITICAL / DEGRADED / HEALTHY
2. **Top 3 findings** by impact
3. **Track summary table** (track x status x one-liner)
4. **Cross-track correlations** (e.g., auth failure explains all API errors)
5. **Recommended actions** -- specific commands and file:line references
6. **Plain-English summary**

**Verdict rules:**
- Any CRITICAL = CRITICAL verdict
- Any HIGH, no CRITICAL = DEGRADED
- All OK = HEALTHY

## My Role

I challenge Monk's findings. I ask "what else could cause this?" I push for root cause, not symptoms. I don't accept the first hypothesis without evidence.

## Checklist

- [ ] All tracks dispatched in parallel (one Agent call per track, all in one message)
- [ ] Every track is read-only
- [ ] Severity classified for each finding
- [ ] Cross-track correlations identified
- [ ] Verdict synthesized with specific actions
