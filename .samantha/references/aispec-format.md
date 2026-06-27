# `.aispec` Format Specification

A terse, **AI-consumption** doc format. Fact-density over human readability. Designed so an AI agent can ingest one file and have a complete, unambiguous picture of a system, process, or domain — without hunting through prose.

---

## Block Vocabulary

Every `.aispec` file is structured as ALL-CAPS headers followed by a colon. Required and optional standard blocks:

| Block | Purpose | Notes |
|-------|---------|-------|
| `OVERVIEW:` | 2–3 sentence summary of what this spec covers | The **only** block where prose is permitted |
| `FACTS:` | Every true, load-bearing statement about the subject | Every line `*`-prefixed; one fact per line; no prose |
| `TERMINOLOGY:` | Definitions used throughout this spec | `* TERM — definition` per line |
| `FILES:` | Canonical paths, optional `:line-range`, `-` for tree notation | One path per line; include role/purpose |
| `SCHEMA:` | Data shapes, database tables, API payloads | `table.column: type, constraints` notation |
| `CONSTRAINTS:` | Guard rails — what NOT to suggest or do in this domain | Negative assertions; one per line |
| `EXAMPLES:` | Minimal worked instances | Short; demonstrate edge cases, not just happy-path |

Domain files extend with custom ALL-CAPS blocks as needed. Examples: `ENDPOINTS:`, `EVENTS:`, `STATES:`, `SHIP_STATS:`. Any block name is valid as long as it is ALL-CAPS and followed by a colon.

---

## Style Rules

1. **Strong assertions.** Every line states a fact as true without hedge words ("should", "might", "could"). If it is not definitely true, it does not belong.
2. **No hedging.** "Generally", "usually", "typically" are banned. Qualified facts should include the condition: `* Caching disabled when TTL=0 (not "usually disabled")`.
3. **One concept per line.** A line with two facts is a line waiting to become a bug. Split it.
4. **No prose outside `OVERVIEW:`.** All blocks except `OVERVIEW:` are lists or tables. If you are writing a sentence in `FACTS:`, rewrite it as an assertion.
5. **`*`-prefix every `FACTS:` entry.** The `FACTS:` block reads as a bullet list; every item starts with `* `.

---

## Built-In Rules

These rules are part of the format itself — they apply to every `.aispec` file:

- **Do not modify without permission.** An `.aispec` is authoritative. Ad-hoc edits without explicit go-ahead corrupt trust in the collection.
- **Authoritative in-scope.** An `.aispec` for system X is the truth about X. It does not speak for other systems.
- **When doc and code diverge, CODE WINS.** *(This is the format's own defensive rule — written to guard against doc drift in the collection where these specs originated. It is deliberately preserved here.)*
  - **⚠️ Samantha INVERTS this rule → DOCS WIN.** She keeps canon trustworthy by rigorous curation (the Librarian drive). A code↔doc divergence is never silently accepted: the default presumption is the code drifted and should be corrected to match the spec; if the spec is stale, it is updated deliberately (DECISION → ADR) and the code follows. The "code wins" defensive posture is what you get when docs rot; Samantha refuses that surrender. See spec §3.
- **Never call them "documentation" to end users.** These are AI knowledge artifacts — designed for agent ingest, not human browsing. The distinction matters for how they are maintained and where they live.

---

## Worked Example (Generic Domain)

This example uses a fictional "task queue" to demonstrate the format without referencing any real project.

```
OVERVIEW:
The TaskQueue processes background jobs submitted by any service. Jobs are
claimed by workers, executed exactly once, and acknowledged on completion.
Failed jobs retry up to MAX_ATTEMPTS before entering the dead-letter zone.

FACTS:
* Job states: pending → claimed → complete | failed → dead-letter.
* Worker claims a job by writing its ID atomically; no two workers may claim the same job.
* Claim TTL is 30 seconds; expired claims revert to pending automatically.
* MAX_ATTEMPTS is 3 (configurable per job type via job_type_config table).
* Dead-letter jobs are retained for 7 days, then purged.
* Priority values: 1 (highest) … 10 (lowest); default is 5.

TERMINOLOGY:
* Claim — the act of a worker locking a job for exclusive processing.
* Dead-letter — a job that has exhausted MAX_ATTEMPTS and will not retry.
* Claim TTL — the window within which a worker must acknowledge or the claim expires.

FILES:
* queue/worker.ts — worker loop: claim, execute, ack.
* queue/schema.sql — jobs and job_type_config table definitions.
* queue/dead_letter.ts — dead-letter retention and purge logic.

SCHEMA:
* jobs.id: uuid, primary key.
* jobs.state: enum(pending,claimed,complete,failed,dead-letter), not null.
* jobs.claimed_by: uuid nullable — worker ID; null when unclaimed.
* jobs.attempt_count: int, default 0.
* job_type_config.type: varchar, primary key.
* job_type_config.max_attempts: int, default 3.

CONSTRAINTS:
* Never set jobs.state directly from application code — use the queue API functions only.
* Do not read the dead-letter zone without pagination; it may contain millions of rows.
* Do not raise claim TTL above 120 seconds without capacity analysis.

EXAMPLES:
* Submit a job: `queue.submit({ type: 'send-email', payload: {...}, priority: 3 })`
* Retry a dead-letter job manually: `queue.requeue(jobId)` — resets attempt_count to 0.
```

---

## Adoption note

When adding `.aispec` files to a project, place them in a predictable directory (e.g. `specs/` or `.aispec/`) and register them in the project's doc index. The index generator should cover `.aispec` files the same as Markdown hub docs — a miss in the index is a registration bug, not proof of absence.
