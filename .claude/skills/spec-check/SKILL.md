---
name: spec-check
description: "Spec↔code compliance audit that builds what's missing until alignment. Use when the user asks about spec compliance, feature completeness, design-doc alignment, or whether the code matches the spec."
user-invocable: true
---

# SPEC-CHECK -- Spec Compliance & Construction

**Activation banner (REQUIRED — first output).** The moment this skill engages, the **very first lines of the assistant reply MUST be this banner** — raw markdown, never inside a code fence, never after a preamble or tool narration. Emit the three banner lines with a **blank line between each** (top rule, title, bottom rule) so chat UIs do not soft-wrap them into one paragraph. If the banner is missing, the skill did not engage.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 **SKILL · SPEC-CHECK** — spec ↔ code compliance

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

I compare the design spec against the codebase, grade every system, and dispatch Monk to build what's missing.

**DOCS WIN**: canon is prescriptive — code conforms to canon, not the reverse. A code↔spec divergence is surfaced and resolved deliberately: fix the code to match the spec, OR update the spec via DECISION→ADR. Never silently accept drift.

## My Protocol

### Step 1: Identify the Source of Truth

Every project has a design spec — VISION.md, FEATURES/, DOCS/SPECS/, or equivalent. If no spec exists, I switch to `build`.

### Step 2: I Dispatch Audit Agents (Read-Only)

I dispatch one Monk agent per audit category myself — parallel Agent calls in one message. Each reads the spec section + corresponding code.

**Grading — 4 dimensions:**
- Coverage: 0-100% of spec with corresponding code
- Depth: STUB / SHALLOW / ADEQUATE / DEEP
- Fidelity: LOW / MED / HIGH
- Quality: LOW / MED / HIGH

**Grades:** COMPLETE (>=90%, >=ADEQUATE) = 3pts | PARTIAL (40-89%) = 2pts | SKELETAL (<40%) = 1pt | MISSING (<10%) = 0pts

### Step 3: I Gate the Build Scope (REQUIRED)

I review the audit results and approve what gets built. I may:
- Narrow scope to the most impactful gaps
- Reprioritize based on dependencies
- Reject categories that don't need building yet
- Dispatch Rook if the build scope feels overambitious

### Step 4: I Dispatch Monk for Build Phase

Dependency-ordered waves:
1. **MODELS/SCHEMA** — data layer first
2. **SERVICES/LOGIC** — business logic depends on models
3. **ROUTES/API** — endpoints depend on services
4. **FRONTEND/UI** — UI depends on API
5. **DOCS** — update to reflect new reality

I dispatch Pixel for UI audit categories.

### Step 5: Re-Audit & Converge

Re-audit changed categories. Score must improve each pass.
- Max 3 passes
- Score must improve, else HALT
- Priority: MISSING → SKELETAL → PARTIAL

### Step 6: My Verdict

| Verdict | Criteria |
|---------|----------|
| ALIGNED | All COMPLETE (max score) |
| CONVERGING | Improving each pass |
| DRIFTING | Significant gaps or MISSING remain |
| MISALIGNED | Score < 50% or stalled |
