# QUEUE — Claimable Work Orders

> **Multi-project sites (per-repo `queue-<repo>.md` files, § Multi-project coordination in README.md):**
> this template's richer 10-column schema and push-assignment model is one valid shape for a single
> global queue. If your site instead runs one `queue-<repo>.md` per downstream repo with seats
> self-filing discovered work, use the simpler canonical 6-column schema + `queue-append.py`/
> `queue-lint.py` tooling documented in README.md § Canonical queue schema + tooling (PROTOCOL 1.6.0)
> instead — don't mix the two schemas in one file.

<!--
  TEMPLATE — the Orchestrator's WORK QUEUE for dual-mode operation.
  Copy to <coord-dir>/QUEUE.md and clear the example entries.

  SINGLE-WRITER RULE (M7 SSOT):
  The Orchestrator is the SOLE author of this file. Implementers never write QUEUE.md.
  Implementers claim WOs by notifying the Orchestrator (STATUS: "claiming WO-N"), and the
  Orchestrator updates QUEUE.md to reflect the claim. This eliminates the claim-race problem.

  PUSH-ASSIGNMENT vs PULL:
  The Orchestrator uses PUSH assignment: it reads the queue, selects the next eligible WO
  for each ready Implementer, and delivers it via HANDOFF message. Implementers do not
  self-select from QUEUE.md. This is the safe default for human-supervised small-N pools.
  (Self-serve pull with atomic claim is the SQLite/MCP advanced path — see advanced/)

  DEPTH FLOOR:
  The Orchestrator must keep the READY count >= DEPTH_FLOOR (12) so Implementers never idle.
  When READY drops below the floor, run the M5 6-lens discovery pass (see README.md).
  The heartbeat.sh discover-on-idle mechanism triggers this automatically.

  THREE-BUCKET STATUS BROADCAST (M7):
  After any queue change, the Orchestrator posts an updated three-bucket status to orchestrator.md.
  The three buckets are the SSOT for "where is the work right now." See the broadcast format below.

  ADDITIVE-ONLY SCHEMA (M8):
  Add new columns or status values by appending; never change the meaning of existing ones.
-->

---

## Three-Bucket Status (broadcast after every queue change)

Post this block to orchestrator.md (as a HEADS-UP message) whenever the queue changes.
This is the single source of truth for all instances on the current work distribution.

```
### <UTC ISO 8601> — orchestrator → ALL — 🛰️ HEADS-UP

**Queue Status**
- Waiting on Implementer: <N> WOs  (<list WO numbers>)
- Waiting on Orchestrator: <N> WOs  (<list WO numbers, e.g. "WO-12 needs Orchestrator review">)
- Waiting on Human: <N> WOs  (<list WO numbers, e.g. "WO-9 GATED — needs human sign-off">)
- READY (buildable): <N> WOs  (floor: 12)
- DONE this session: <N> WOs
```

---

## Queue Table

| WO-N | Title | Priority | Status | Claimed-by | Depends-on | Gated | Schema | Verified-against | Notes |
|------|-------|----------|--------|------------|------------|-------|--------|------------------|-------|
| WO-1 | (example) Add retry backoff | HIGH | DONE | impl-alpha | none | no | no | a3f9b2c | SHA: a3f9b2c |
| WO-2 | (example) Write hub doc for queue system | MED | READY | — | WO-1 | no | no | 9c14e0d | waiting for WO-1 DONE |
| WO-3 | (example) Migration: add job_type_config table | HIGH | CLAIMED | impl-beta | none | no | yes | 9c14e0d | in progress |
| WO-4 | (example) Cleanup dead dead-letter purge code | LOW | READY | — | none | no | no | — | `verified-against` blank ⇒ unswept |
| WO-5 | (example) ADR: retry policy | MED | GATED | — | none | yes (safety-list; canon-prose `provisional`) | no | 9c14e0d | two gates — clearing one is not enough |

<!-- Add new WOs at the bottom. Never delete rows. Mark DONE with SHA. -->

---

## Row-Hygiene Columns (additive — M8-safe)

A status label alone cannot answer the three questions a seat actually has before claiming a row. Each gets its own column. These are **append-only additions** to the Queue Table above.

| Column | Question it answers | Blank means |
|--------|---------------------|-------------|
| `gated` | Am I allowed to build this without escalation? | **UNVERIFIED-FOR-GATING** — never implicitly clear |
| `schema` | Can this land right now, independent of gating? | unassessed |
| `verified-against` | Is this row still *true*? | unswept, not clean |

**`gated: yes/no` — and gates COMPOUND, they are not alternatives.** A multiply-gated row must list *every* gate found; clearing one does not make the row buildable. Three distinct gate *kinds* have been confirmed live, and a code-only check finds only the first:

- **(a) Code-comment markers** near the files a row cites — e.g. `human-gated`, `[NO-CANON]`, or whatever marker string your project adopts. Whatever you pick, write the *exclusions* into the grep pattern itself, not into someone's memory: a project may also carry same-shaped strings that are **not** process gates (an in-app ownership ACL, say). Unexcluded, the marker degrades to noise within a week.
- **(b) Standing safety-list membership** — resolved against the **full** list in the project's own CLAUDE.md, never a shortened restatement in the queue doc. A duplicated list drifts from its source; that drift is how a seat once cleared one of a row's three gates and believed it had cleared them all.
- **(c) Canon-prose gates** — a gate that lives in prose rather than a code comment: a spec section marked `provisional`, `implementer-proposed`, `pending a tuning pass`. A code-path grep will never see these; the check must also scan the canon sections a row cites.

`coord-gate-audit.sh` mechanizes all three (marker/ACL-exclusion/safety patterns are all overridable — the framework supplies the *shape*, your project supplies the vocabulary).

**`schema: yes/no`** — a scheduling signal, not a fourth gate. A row needing new migrations is unclaimable while any migration chain ahead of it is blocked; de-prioritize while blocked, re-claimable the moment the chain clears. Hand-inference is not good enough here — it was gotten wrong within fifteen minutes of the convention being proposed. `coord-status.sh` reports `migration chain: N unapplied, blocked at <rev>` so the cell is observable rather than remembered.

**`verified-against: <tree-identifying anchor>`** — the anchor must resolve to a specific tree: a commit SHA, or a PR number that resolves to one. **A bare date is not a valid anchor.** On a day the tip moves twenty-plus commits, "2026-08-03" does not identify *which* tree was checked — it is precisely the staleness this column exists to prevent, wearing a citation's clothes.

**Depends-on precision.** A `depends-on` claim is itself a claim, and must be checked against the target module, not inherited from a feature-description blurb. Rows have carried both fabricated dependencies (an additive greenfield module staged as needing a "redesign" first) and missing ones (a hidden precondition staged as `none`) — found only by reading the actual target's header.

> **Why all four, and why mechanized:** in one full sweep of an eleven-row queue, **every single row was wrong as staged** — at least one of status/depends-on/gated/schema incorrect on 11 of 11. Not a sampling artifact. A queue with no re-verification mechanism was 0% accurate by the time anyone looked.

**Duplicate-queue-file discipline.** If a project has both a historical queue file and a live one, the historical file gets an unmistakable top-of-file banner (or an `.ARCHIVED-DO-NOT-USE` suffix). A superseded queue that merely *looks* superseded will be read as current, and a stale row will get self-picked.

---

## Status Values

| Status | Meaning | Who sets it |
|--------|---------|-------------|
| `READY` | Buildable, unclaimed, all dependencies DONE | Orchestrator |
| `CLAIMED` | Assigned to an Implementer; work in progress | Orchestrator (on HANDOFF) |
| `DONE` | Complete; SHA recorded | Orchestrator (on STATUS: DONE receipt) |
| `BLOCKED` | Implementer reported a blocker; waiting for unblocking | Orchestrator (on STATUS: BLOCKED receipt) |
| `DECISION-NEEDED` | Waiting for a DECISION or human resolution | Orchestrator |
| `GATED` | Human sign-off required before the WO can be claimed | Orchestrator |
| `CANCELLED` | No longer needed; superseded or dropped | Orchestrator |

New status values may be added (M8: additive only). Never redefine an existing status value.

---

## Depth-Floor Rule

**READY count must stay >= 12 (the depth floor).**

When READY drops below 12:
1. The heartbeat.sh discover-on-idle mechanism prints a DISCOVERY PASS NEEDED signal.
2. The Orchestrator runs the M5 6-lens discovery pass (see README.md).
3. Discovered work is added as new READY WOs.
4. The three-bucket status broadcast is posted.

The floor exists so that a fast Implementer never completes its WOs and then idles while the Orchestrator catches up. Refill on a DIP, not a drain.

**The floor is a mechanically-checked assertion, not a remembered one.** `coord-status.sh` counts non-DONE/non-CLOSED rows per queue file and prints the depth alongside `BOTH ALIVE`; `heartbeat.sh` posts `QUEUE-SHALLOW: <queue> <N>` on its cadence tick when a tracked queue drops under the floor — the same channel as `WATCHER-DOWN`. This turns "forgot to check" into a structural alarm instead of depending on an Implementer yelling loud enough to be heard.

---

## Dependency Rules

- A WO may not be CLAIMED until all its `Depends-on` WOs are DONE.
- Cyclic dependencies are a design error — the Orchestrator breaks cycles by reordering or splitting WOs.
- A WO with `Depends-on: none` is immediately eligible once READY.

---

## Backlog vs Queue

This file is the **QUEUE** — the immediate, fully-specified contracts ready for pickup.

The **BACKLOG** (`.samantha/backlog/BACKLOG.md` or equivalent) is the deeper reservoir:
- Ungroomed items: ideas, discovered gaps, future features.
- The Orchestrator promotes BACKLOG items to QUEUE WOs when they are fully specified and their dependencies are met.
- Keep the queue lean (focused on buildable work); keep the backlog deep (all known work).

Flow: `BACKLOG → QUEUE (READY) → CLAIMED → DONE`

---

## Parallel-Safety: Lane Roster + Wave Plan

The Orchestrator schedules on **Cells, not lanes** — a lane splits into collision-independent Cells that run at once. Full method: `PARALLEL-SAFETY.md`. Two additions to the queue:

### PAR tag (additive column — M8-safe)
Annotate each WO with its parallel-safety tag so the Implementer composes maximal safe build-waves:

```
[ <LANE>:<CELL> · <FREE|LANE|ORDERED|SERIAL> · blast:<🟩/🟨/🟥> · after: · conflicts: · deploy: · gate: ]
```

Add it as a `PAR` column on the Queue Table (append-only; never redefine an existing column).

### Lane roster (broadcast alongside the three-bucket status)
Enumerate the project's **full lane universe** — every repo + sub-lane — and per lane mark its status. This is the "how many tracks are running" dashboard.

```
### <UTC ISO 8601> — orchestrator → ALL — 🛰️ HEADS-UP

**Lane Roster**  (K lanes: F fed · S starving · E empty · G gated)
- <L1 name> · lane:<…> · Cells:[…] · status:FED       (worker: WO-<N>)
- <L2 name> · lane:<…> · Cells:[…] · status:STARVING   (WO-<M> ready, no worker — fill now)
- <L3 name> · lane:<…> ·           · status:EMPTY      (no WOs — Orchestrator to author)
- <L4 name> · lane:<…> ·           · status:GATED      (needs human: <what>)
```

**Roster rules:** staff STARVING lanes before deepening a FED one; an EMPTY lane is the Orchestrator's gap to author work for; a GATED lane is surfaced to the human, never silently idle.

### Wave plan
The **wave** = the maximal set of READY WOs whose `Depends-on` are DONE and whose Cells are pairwise disjoint. That is what the Implementer fires now (one worker per WO). Recompute when a WO commits — its dependents may unblock.
