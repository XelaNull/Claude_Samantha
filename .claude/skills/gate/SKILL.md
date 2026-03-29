---
name: gate
description: Use when the situation is ambiguous and I need to determine whether something is broken (BLUE) or missing (GREEN). My internal decision fork for routing to the right protocol.
user-invocable: true
---

# Color Gate -- My Triage Router

## The Decision Fork -- One Question:

> *"Has this capability ever worked in this project, or does it not exist yet?"*

| Answer | Route to | Why |
|--------|----------|-----|
| "It worked before, now it doesn't" | BLUE | Something broke -- diagnose the regression |
| "It never existed / it's additive" | GREEN | Something's missing -- design and build it |

## My Inference Table

When the human doesn't name a mode, I interpret:

| the human says / context | I route to | Why |
|--------------------|-----------|-----|
| Pastes a stack trace or specific error | **FIX** | Targeted diagnosis + fix |
| Reports a vague regression, "X isn't working" | **BLUE** | Full diagnostic sweep |
| Pastes a GitHub issue or says "fix issue #N" | **INDIGO** | Issue resolution pipeline |
| "Add support for..." / "build this" / "I want..." | **GREEN** | Additive feature work |
| "What does this do?" / "explain X" / "how does this work?" | **EXPLAIN** | Codebase orientation |
| "Clean up" / "polish" / after a big feature push | **GOLD** | Quality sweep |
| Translation quality or missing languages | **AMBER** | i18n-specific |
| "Is this secure?" / exploit concern | **RED** | Security focus |
| "Does code match the spec?" / "missing features?" | **VIOLET** | Spec alignment |
| "Ship it" / "ready to commit" (with full pipeline) | **SHIP** | Build + test + review + commit |
| "Commit this" / "save" (lightweight) | **COMMIT** | Stage + commit, no pipeline |
| "How does this look?" / "review this" | **REVIEW** | Review cycle |
| Unclear or ambiguous | **ASK** | "This sounds like it could be [X] or [Y] -- which fits?" |

## Protocol Reference

| Mode | Type | Purpose |
|------|------|---------|
| FIX | Quick | Targeted bug fix from specific error |
| COMMIT | Quick | Lightweight stage + commit |
| EXPLAIN | Quick | Codebase orientation and explanation |
| BLUE | Core | Full diagnostic sweep |
| GREEN | Core | Build missing feature (6-stage, has fast path) |
| GOLD | Core | Code quality sweep |
| AMBER | Core | Translation/i18n quality |
| RED | Workflow | Security audit (Cipher-led) |
| VIOLET | Workflow | Spec compliance (audit + build) |
| INDIGO | Workflow | Fix GitHub issue (full pipeline) |
| REVIEW | Workflow | Dispatch review cycle |
| SHIP | Workflow | Build + test + review + commit |

## Rules

- If the human explicitly names a mode, I use it directly (no gate needed)
- If ambiguous, I ASK before routing -- I don't guess
- I don't announce "entering BLUE mode" unless the human would benefit from knowing
- I just execute the protocol
