---
name: audit
description: "Full codebase-vs-docs/spec discovery audit: finds missing features, half-built work, code/doc divergence, dead code, and doc gaps, then emits a prioritized backlog and work orders. Use when the user wants a queue-feeding sweep, 'what's missing vs the spec', or 'bring code up to spec'. For audit-and-fix-now in one session, use spec-check instead."
user-invocable: true
---

# AUDIT -- Code↔Doc Discovery → Backlog

**Activation banner (REQUIRED — first output).** The moment this skill engages, the **very first lines of the assistant reply MUST be this banner** — raw markdown, never inside a code fence, never after a preamble or tool narration. Emit the three banner lines with a **blank line between each** (top rule, title, bottom rule) so chat UIs do not soft-wrap them into one paragraph. If the banner is missing, the skill did not engage.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔭 **SKILL · AUDIT** — code↔doc discovery → backlog

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

I sweep the whole codebase against canon, surface every difference, and turn it into a prioritized backlog + work orders. I discover and queue — I do NOT build here (that's `build`/`ship`, dispatched from the backlog). Full methodology: `.samantha/references/coordination-protocol/6-lens-audit.md`.

**DOCS WIN**: canon is prescriptive. A code↔doc divergence defaults to *fix the code to match canon*; if canon itself is stale, I log a `DECISION` (→ ADR) rather than silently accepting drift.

## My Protocol

### Step 1: Anchor on canon
Find the source of truth — spec, `FEATURES/`, `SYSTEMS/` hub docs, ADRs, `DECISIONS.md`. If no canon exists, I STOP and push to establish it first (the Librarian's job) — auditing against nothing produces noise, not a backlog.

### Step 2: Run the 6 lenses (parallel, read-only)
I dispatch read-only audit agents — one per lens (or grouped) — in parallel from my own session:
1. **Features to build** — in the spec/backlog/ADRs, no implementation yet.
2. **Code-vs-canon divergence** — code contradicts canon, OR is built but doesn't fully realize what the doc describes (under-fleshed).
3. **Defined-but-unwired** — declared but never connected (dead exports, unread config, unrouted handlers).
4. **Cleanup / removal** — dead code, deprecated paths, orphans, duplicates.
5. **Doc-gaps + design-flaws** — undocumented systems, stub hub docs, open questions, patterns that break at scale.
6. **ADR-rollup** — decided-but-not-codified, stale Proposed ADRs, unfolded Accepted ADRs.

### Step 3: Synthesize + dedup
I collect all findings, dedup overlaps, and judge each: is it real, what's the impact, what does it depend on. I reject noise and speculative edge-cases.

### Step 4: Prioritize
Order by impact × dependency. Priority: MISSING → SKELETAL → PARTIAL. Cleanup items are low-risk/high-signal — surface them for when implementers are idle.

### Step 5: Emit the backlog + work orders
- Write the backlog to `.samantha/plans/<name>-backlog.md` and refresh the `.samantha/plan.md` symlink (Plans convention).
- Formulate **work orders** in the coordination format (Goal · Scope · Constraints · Accept · Proof · Refs). Each WO names disjoint file-lanes so workers don't collide.
- **Dual mode (orchestrator→implementer):** post WOs to the implementer's `QUEUE.md` / `CROSS-CLAUDE.md`; keep the queue at the depth floor (≥12 READY).
- **Solo mode:** feed the WOs to my own `build`/`ship` waves, one at a time, gating each.

### Step 6: Gate + report
I gate the backlog (scope, priorities) — Rook if it's sprawling. Then I report: N items by lens + priority, the WOs cut, current queue depth, and any `DECISION`s filed for stale-canon cases.

## Verdict
| Verdict | Criteria |
|---------|----------|
| QUEUED | Backlog emitted, WOs cut, queue at/above floor |
| THIN | Few gaps found — codebase is close to canon |
| BLOCKED | No canon to audit against — establish it first |
| DRIFT | Major code↔canon divergence — flagged for deliberate resolution |
