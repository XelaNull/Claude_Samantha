# Plan: Coordination as skill-based modes (Solo + Star)

Status: **PHASE 5 (rollout) DONE on disk** · seats need **re-arm** · **still no git push**  
PROTOCOL **1.4.0**

## Phases

| Phase | Status |
|-------|--------|
| 0–4 | Complete on Prime |
| **5 Rollout** | Nebuspace + XelaNull hubs updated; live Nebuspace processes stopped; re-arm checklist in `Nebuspace/.samantha/ROLLOUT-PROTOCOL-1.3.0.md` |
| 6+ | Deferred TODOs only (SSH msg auth, memory redesign) until human prioritizes |

## Phase 5 actions taken

1. Stopped Nebuspace monitors/heartbeats via pidfiles (M2).
2. Backed up prior scripts under `.claude/backup-pre-1.3.0-*`.
3. Copied 1.3.0 suite + `PROTOCOL-VERSION` + filter + presence into hub `.claude/`.
4. Synced `references/coordination-protocol/` (preserved Nebuspace `HARNESS-*` / `VOTE-LOG`).
5. Added `coordinate*` skills to hubs + implementer repos that had skills dirs.
6. Seeded `.presence` / `project:` for sectorwars + aiclient seats.
7. XelaNull updated (was idle — no stop needed).

## Your next step (human / seat agents)

Re-arm each Nebuspace seat per `ROLLOUT-PROTOCOL-1.3.0.md`. Confirm banner `PROTOCOL 1.3.0` + `project=…`. Smoke cross-project silence.

## Shipped since

- **SSH message authenticity** — shipped in PROTOCOL 1.4.0 (2026-08-09): `coord-keygen.sh` / `coord-verify.sh`, `coord-send.sh` always signs, `coordination-precommit-hook.sh` hard-blocks on invalid/non-exempt-unsigned mail (forward-only), bootstrap key handshake folded into `bootstrap-identity.sh` + the Orchestrator's `ASSIGN-IDENTITY` reply.

## Still deferred

- Memory redesign
- Git commit/push of Prime (ask when ready)
