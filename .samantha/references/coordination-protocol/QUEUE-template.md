# QUEUE — Claimable Work Orders

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

| WO-N | Title | Priority | Status | Claimed-by | Depends-on | Notes |
|------|-------|----------|--------|------------|------------|-------|
| WO-1 | (example) Add retry backoff | HIGH | DONE | impl-alpha | none | SHA: a3f9b2c |
| WO-2 | (example) Write hub doc for queue system | MED | READY | — | WO-1 | waiting for WO-1 DONE |
| WO-3 | (example) Migration: add job_type_config table | HIGH | CLAIMED | impl-beta | none | in progress |
| WO-4 | (example) Cleanup dead dead-letter purge code | LOW | READY | — | none | |
| WO-5 | (example) ADR: retry policy | MED | GATED | — | none | Needs human sign-off |

<!-- Add new WOs at the bottom. Never delete rows. Mark DONE with SHA. -->

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
