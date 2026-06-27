# ADR Process — Architecture Decision Records

This directory holds the templates and rules for the **ADR + DECISIONS** process: the mechanism the Samantha Prime canon-leash runs on (spec §3).

---

## What it is

The ADR process is the structured path from **uncertainty to settled canon**. When Samantha (or any agent) hits a canon edge — a gap, a conflict, or a stale rule — they log it in the DECISIONS workspace rather than guessing or going silent. From there it flows to the human, gets resolved, and becomes a durable ADR. Every ratified ADR grows the canon, which grows Samantha's autonomous leash.

Two artifacts:

| File | Purpose |
|------|---------|
| `DECISIONS.md` (from `DECISIONS-template.md`) | The open-questions workspace. Live, append-only. The first stop at every canon edge. |
| `ADR/NNN-<slug>.md` (from `ADR-template.md`) | One file per decision. Immutable once Accepted. Append-only; never overwrite. |

---

## Lifecycle: Proposed → Accepted

```
Canon edge detected
        ↓
Log in DECISIONS.md (OPEN)   ← Samantha does this autonomously
Build the unambiguous kernel  ← Don't stall; keep momentum
        ↓
Human resolves (RESOLVED)    ← Human gate
        ↓
Draft Proposed ADR            ← Samantha drafts
        ↓
Human reviews + Accepts       ← Human gate (the ONLY Accept gate)
        ↓
ADR status → Accepted
DECISIONS item → CLOSED
Canon updated
```

**The human is the only Accept gate.** Samantha proposes freely; she does not self-ratify. A "Proposed" ADR is not yet canon — never act on it as if it were.

---

## Hard Gates

These apply universally across every project that uses this process:

1. **Never auto-accept.** No ADR may move from Proposed to Accepted without an explicit human go-ahead. Samantha may draft and argue, never ratify.
2. **Append-only.** Once an ADR is Accepted, its Decision section is immutable. To revise a decision, write a new ADR and supersede the old one.
3. **Supersede, never edit.** `ADR/NNN-<slug>.md` status moves to `Superseded by ADR-MMM`. The old file is kept as history.
4. **Keep an index.** An `ADR/INDEX.md` (or a generated equivalent) lists every ADR with status and a one-line summary. A decision not in the index is invisible — and invisible decisions get re-litigated.
5. **Fold into canon deliberately.** Once an ADR is Accepted and the team is confident, its rule may be folded into prose (CLAUDE.md, a hub doc, a skills file). **Hard gate:** only when the rule is confirmed present in the target doc. Never fold speculatively.
6. **Log before building.** A canon edge is not a full stop. Log the DECISION first, then build the unambiguous kernel and continue. Never freelance — the log is the promise.

---

## When Samantha files a DECISION

She files a DECISION at exactly three canon-edge types:

- **Gap (NO-CANON):** Canon doesn't cover the situation. No rule applies. She must invent something, which means she might invent wrong.
- **Conflict:** The action she is about to take would contradict existing canon. She does not silently override.
- **Change:** Canon itself looks wrong or stale. She does not correct it unilaterally.

In all three cases: log the DECISION, name the unambiguous kernel, build that kernel, and surface the question to the human.

---

## ADR Index

<!-- CUSTOMIZE: In a live project, maintain this index as ADRs accumulate. -->
<!-- Or generate it from frontmatter (recommended — hand-maintained indexes drift). -->

| # | Title | Status | Date |
|---|-------|--------|------|
| (none yet) | | | |

---

## File layout

```
ADR/
  INDEX.md              ← index of all ADRs (generated or maintained)
  001-<slug>.md         ← first decision
  002-<slug>.md         ← second decision
  ...
DECISIONS.md            ← open-questions workspace (live, append-only)
```

<!-- CUSTOMIZE: Adjust paths to match your project's docs root. -->
