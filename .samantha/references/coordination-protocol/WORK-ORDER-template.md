# Work Order Templates

Work orders (WOs) are the unit of delegation from Orchestrator to Implementer. Two tiers.

---

## Tier 1 — Full Work Order

Use when the work spans 3+ files, crosses services, requires a migration, or needs a DEPLOY WINDOW.
A full WO explicitly names disjoint sub-parts so the Implementer can fan them to parallel worker subagents.

### Format

```
### <UTC ISO 8601> — orchestrator → <impl-identity> — 🤝 HANDOFF

**WO-<N>: <short title — imperative, outcome-focused>**

**Goal:**
<What must be true when this WO is complete. Observable, testable. NOT a list of steps — a statement
of the finished state. The Implementer owns HOW; this is the WHAT.>

**Scope:**
<Exact files, zones, or subsystems this WO covers. Be precise — scope defines the lane.
List disjoint sub-parts explicitly so the Implementer can identify parallel fan-out opportunities:>
- Sub-part A: <files/zone> — <what changes here>
- Sub-part B: <files/zone> — <what changes here>
(Sub-parts A and B may be parallelized. Sub-part C depends on A.)

**Constraints:**
<What must NOT change. Patterns to follow. Antipatterns to avoid. Any known landmines.>
- Do not touch <path> — owned by impl-beta.
- Follow the pattern in <canonical example file>.
- Do not add external dependencies without sign-off.

**Accept:**
<Specific, testable acceptance criteria. Each criterion must be checkable.>
- [ ] <criterion 1>
- [ ] <criterion 2>
- [ ] Build passes: `<build command>`
- [ ] Tests pass: `<test command>`

**Proof:**
<How to prove it works — the exact command(s) and expected output, or the observable before/after state.
The Implementer runs this and quotes the output in the STATUS reply.>
Example: `<command>` → expected output: `<expected>`
Note: lossless/migration WOs inherit the Proving Standard automatically (README.md) — traceability matrices are claims, not proof; require independent source-vs-target substance sampling plus an Orchestrator adversarial audit before DONE.

**Refs:**
<Canonical docs, ADRs, hub docs, related WOs. Repo-relative links.>
- Canon: <path to SYSTEMS/X.md>
- ADR: <ADR/NNN-slug.md>
- Depends-on WOs: WO-<M>, WO-<L>  (or "none")

**Priority:** HIGH | MED | LOW
**Gated:** yes | no  (yes = requires human sign-off before Implementer may proceed)
```

### STATUS reply (DONE)

```
### <UTC ISO 8601> — <impl-identity> → orchestrator — 📋 STATUS

**WO-<N> STATUS: DONE**

SHA: <git commit SHA of the completing commit>
Proof: <exact output of the proof command quoted verbatim>
Notes: <what, if anything, changed from the original plan — or "no deviations">
```

### STATUS reply (BLOCKED)

```
### <UTC ISO 8601> — <impl-identity> → orchestrator — 📋 STATUS

**WO-<N> STATUS: BLOCKED**

Blocks: <exact blocker — missing dependency, prerequisite WO not done, environment issue>
Unambiguous kernel: <what was built before hitting the block — or "nothing yet">
Next: <what must happen before this WO can proceed>
```

### STATUS reply (DECISION-NEEDED)

```
### <UTC ISO 8601> — <impl-identity> → orchestrator — ❓ DECISION-NEEDED

**WO-<N> STATUS: DECISION-NEEDED**

Question: <the exact decision required — precise, one question per message>
DECISION filed: OPEN-<NNN> in DECISIONS.md
Unambiguous kernel: <what was built while waiting — the parts not affected by the question>
Options: A) <option A description>  B) <option B description>
```

---

## Tier 2 — One-Liner Ticket

Use for work confined to a single file or a small, well-defined change with no cross-service impact.

```
### <UTC ISO 8601> — orchestrator → <impl-identity> — 🤝 HANDOFF

**WO-<N>: <title>**
<One sentence: what to do and where. Accept: build passes + <specific check>.>
```

Example:
```
### 2026-07-01T14:00:00Z — orchestrator → impl-alpha — 🤝 HANDOFF

**WO-12: Fix off-by-one in queue depth counter**
src/queue/counter.ts line 47: `>` should be `>=`. Accept: `npm test queue` passes (was failing 2/8).
```

---

## Work Order Numbering

- WOs are numbered sequentially by the Orchestrator: WO-1, WO-2, WO-3, …
- The Orchestrator is the sole issuer of WO numbers (single-writer: no two instances ever assign the same number).
- Once a WO number is issued, it is never reused. Superseded WOs keep their number; the new WO gets the next number.
- The QUEUE.md file is the source of truth for all WO numbers and their current status (M7).

---

## Fan-out Guidance

A full WO's **Scope** section lists disjoint sub-parts. The Implementer reads this and fans the sub-parts to its own parallel worker subagents (background subagents, one per sub-part). The Implementer:

1. Dispatches each sub-part to a worker subagent (one-at-a-time for dependent parts, parallel for independent parts).
2. Reviews each worker's output against the sub-part's accept criteria.
3. Integrates the results.
4. Replies to the Orchestrator with a single STATUS covering the full WO.

The Orchestrator does not need visibility into the sub-part fan-out — only the final STATUS and the proof output.
