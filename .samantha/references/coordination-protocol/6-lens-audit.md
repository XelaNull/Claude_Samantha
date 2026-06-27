# 6-Lens Discovery Audit (M5)

The Orchestrator's standing duty when idle and the work queue is below the depth floor (≥12 READY contracts). Each lens finds a distinct class of work. Running all six in sequence covers the full surface without overlap.

---

## When to Run

- **Triggered automatically** by `heartbeat.sh` (discover-on-idle) when queue READY count < 12.
- **Triggered manually** at session start (always check the queue depth after arming).
- **Triggered by instinct** when the codebase feels "half-built" or the backlog looks thin.

---

## The Six Lenses

### Lens 1 — Features to Build

**Question:** What is in the spec, backlog, or ADRs that has not yet been implemented?

Look for:
- Items in `BACKLOG.md` with status PLANNED or TODO.
- Spec sections marked `📐` (planned) or `🚧` (in progress but stalled).
- ADRs with a "Consequences → follow-on work" section that has no corresponding WO.
- Feature docs in `FEATURES/` with no corresponding implementation footprint in the code.

Output: new WOs for each identified gap. Write them to QUEUE.md (Orchestrator-only write).

---

### Lens 2 — Code-vs-Canon Divergence

**Question:** Where does the code contradict a canonical hub doc, ADR, or settled spec?

Look for:
- Hub docs (`SYSTEMS/X.md`) that describe a behaviour the code no longer implements.
- ADRs marked Accepted whose rule is not yet present in the codebase.
- Comments in the code that say "TODO: align with spec" or similar.
- Type signatures / APIs that differ from what the DATA_MODELS docs describe.

Output: WOs to align the code to canon, OR DECISION entries if canon itself may be stale.
**Never silently accept code drift as truth.** (Docs win — see safety-carveouts.md.)

---

### Lens 3 — Defined-but-Unwired

**Question:** What has been declared but never connected?

Look for:
- Functions, classes, or modules exported but never imported anywhere.
- Event handlers or hooks registered but no emitter triggers them.
- Config keys defined in a schema but never read by the code.
- CLI commands listed in a help string but not implemented.
- Migrations that ran but whose new columns are never accessed.

Output: integration WOs (wire the thing up) or cleanup WOs (remove the dead declaration).

---

### Lens 4 — Cleanup / Removal

**Question:** What should be deleted?

Look for:
- Dead code: functions/files with zero call-sites and no test coverage.
- Deprecated paths: code marked `@deprecated` or `# DEPRECATED` still in production paths.
- Orphaned files: files not referenced from any import, build target, or test.
- Stale migrations: migration files for schema states that have since been superseded.
- Duplicate implementations: two functions doing the same thing — pick one, remove the other.

Output: cleanup WOs. These are low-risk, high-signal — prioritize them when Implementers are available.

---

### Lens 5 — Doc/Canon Gaps + Design Flaws

**Question:** What is undocumented, mis-documented, or designed in a way that will cause problems?

Look for:
- Systems with no hub doc in `SYSTEMS/`.
- Hub docs that are stubs (less than one meaningful section of actual content).
- DECISIONS.md items that have stayed OPEN for more than one sprint without progress.
- Spec sections marked `❓ OPEN` — these are known unknowns that need a decision.
- Design patterns that work now but will break at scale (e.g. a full-table-scan used in a hot path).
- Missing error handling: code paths with no error branch that callers assume are infallible.

Output: WOs for doc work + DECISION entries for open questions. Filing a DECISION is always within canon — do it autonomously; the human resolves it.

---

### Lens 6 — ADR Rollup

**Question:** What has been decided but not yet codified or folded into canon?

Look for:
- DECISIONS.md items with status RESOLVED but no ADR filed.
- ADRs in Proposed status with no recent activity (drive them to Accepted or mark them superseded).
- Accepted ADRs whose rule has not yet been folded into the relevant hub doc, CLAUDE.md, or skill.
  (Hard gate: only fold when the rule is confirmed present in the target doc.)
- Accepted ADRs whose Consequences section listed follow-on work that has no corresponding WO.

Output: ADR filing WOs, ADR-fold WOs. These keep the decision log from becoming a debt pile.

---

## Output Format

For each lens, post discovered WOs directly to QUEUE.md (Orchestrator-only write). Use this format:

```
| WO-<N> | [Lens <1-6>] <title> | <priority> | READY | — | <depends-on or none> | discovered via 6-lens |
```

After the full pass, post a queue-status three-bucket broadcast to `orchestrator.md` so all Implementers see the updated depth.

---

## Depth Floor

**Keep QUEUE.md at ≥12 READY (buildable, unclaimed) contracts.** This is the depth floor. A single discovery pass should aim to fill the queue to 2× the floor (24 WOs) to provide a margin before the next pass is needed.

The floor exists so a fast Implementer never drains the queue and idles while the Orchestrator catches up.
