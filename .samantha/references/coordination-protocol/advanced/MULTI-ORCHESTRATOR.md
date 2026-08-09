# Multi-orchestrator topology — design memo (Phase 3)

Status: **DESIGN ONLY** · PROTOCOL provision for a future major · **not implemented**  
Date: 2026-08-09 · Companion to PROTOCOL 1.3.0 star mode

## Constraint today (load-bearing)

**One active orchestrator writer per coord-dir.** Spokes watch that hub's outbox. Single-writer-per-file + STAR watch set remain the correctness core.

## Why provision for >1 orchestrator

- Separate humans/sessions each acting as hub for disjoint project sets
- HA / handoff when the primary hub session dies
- Organizational split (e.g. one hub per product line) without merging buses

## Options (pick later via ADR — do not freestyle)

### A — Zone-split hubs (same coord-dir)

Two orchestrator identities (`orchestrator-sectorwars`, `orchestrator-aiclient`), each sole writer of its own outbox. Spokes watch **only the hub that owns their project**. A thin `PROJECTS.md` (still single-writer — designate a meta-owner or alternate) maps project → hub identity.

| Pros | Cons |
|------|------|
| One bus directory | Watch-set rules get harder; risk of spoke watching wrong hub |
| Shared deploy-window semantics need a meta-channel | Who broadcasts `ALL`? |

### B — Federated stars (one coord-dir per star)

Each project/workspace has its own star. Orchestrators peer via an optional **hub-bus** (second STAR among hubs only).

| Pros | Cons |
|------|------|
| Clean isolation (matches project filter instincts) | Cross-project WOs need explicit federation messages |
| Failure domains separate | More arming surface |

### C — Active/standby HA

One writer at a time; standby mirrors presence and takes over on WATCHER-DOWN + human/auto fence.

| Pros | Cons |
|------|------|
| Minimal protocol change | Not true parallelism; fencing must be airtight |

## Recommendation to carry forward

Prefer **B (federated stars)** for multi-project isolation, with **project-scoped spoke filter (1.3.0)** covering the common "one hub, many projects" case without a second orchestrator. Introduce a second orchestrator only when two humans must hub concurrently — then ADR-pick A vs B.

## Non-goals until ADR

- Spoke-to-spoke watching across projects
- Automatic leader election without human supervision
- sqlite-mcp cutover as a substitute for topology clarity

## Open questions for the human

1. Is the pain multi-*human* hubs or multi-*project* under one human hub? (1.3.0 project filter targets the latter.)
2. If two hubs: same machine/coord-dir (A) or separate buses (B)?
