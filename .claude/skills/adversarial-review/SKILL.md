---
name: adversarial-review
description: Use when a structured multi-agent review is warranted — high-stakes changes, major architectural decisions, or any output that needs adversarial verification beyond a single reviewer.
user-invocable: true
---

# ADVERSARIAL-REVIEW -- Structured Multi-Agent Review

Adversarial review is a **standing disposition** baked into every agent and protocol — Samantha's identity, the Constitution, Rook/Mack/Cipher, the proof model (§3.6), and the design panel (§3.5) all embody it. This skill is the **structured, invocable version**: a deterministic find → adversarially-verify → synthesize pipeline for when that disposition needs formalizing.

**When to invoke this skill** rather than relying on the standing disposition:
- Output is high-stakes (foundational, user-facing, security-sensitive, or hard to reverse)
- The scope is wide enough that one reviewer carries meaningful blind-spot risk
- You want a recorded, structured finding set rather than an inline review
- 6+ agents needed — where a Workflow (deterministic fan-out) is the right tool

**Model tiering**: finder agents (Sonnet/standard effort) · verifier agents (Sonnet, Opus-escalate on critical surface) · synthesizer (Samantha at Opus). Spend reasoning where evaluation matters — the verifier challenges the finder; the synthesizer arbitrates.

## My Protocol

### Phase 1: FIND

I dispatch N parallel finder agents — each assigned a **distinct lens** so findings don't correlate:

| Lens | Focus |
|------|-------|
| **Correctness** | Does the implementation do what was intended? |
| **Safety** | What breaks silently or under edge cases? |
| **Security** | Where could an adversary exploit this? |
| **Simplicity** | What's over-engineered or could be simpler? |
| **Integration** | What does this break upstream or downstream? |

Each finder returns findings with file:line references and severity (CRITICAL / HIGH / MED / LOW).

**Engineered diversity rule**: give each finder a distinct lens and constraint. Identical prompts → correlated findings → wasted tokens. Diversity is designed, not hoped for.

### Phase 2: ADVERSARIALLY VERIFY

For each HIGH or CRITICAL finding, I dispatch a verifier with the explicit brief: *"Your job is to refute this finding. If you can't, confirm it and state why it holds."*

Verifiers work against the **findings**, not the original output — targeted, not re-review-everything.

### Phase 3: SYNTHESIZE

I arbitrate:
- **Confirmed** (verifier couldn't refute) → carry forward with severity and remediation
- **Refuted** (verifier disproved it) → document why it doesn't hold
- **Disputed** (verifiers disagree) → I adjudicate with reasoning

**Output**: a structured finding set with per-finding verdict, severity, and specific remediation path.

## Scale

For 6+ agents, this maps to a **Workflow** (deterministic fan-out, per-agent `model`/`effort`/`schema`, structured output — no prose-parse). A skill may launch a workflow; this is that bridge point.

## Checklist

- [ ] Distinct lens per finder (no two identical)
- [ ] Verifiers target findings, not the original output
- [ ] Every HIGH/CRITICAL finding adversarially verified
- [ ] Synthesis arbitrates conflicts — doesn't average
- [ ] Output is a structured finding set, not a prose blob
