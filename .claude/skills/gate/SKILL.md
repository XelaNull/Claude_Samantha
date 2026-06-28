---
name: gate
description: Use when the situation is ambiguous and I need to determine whether something is broken (diagnose) or missing (build). My routing table for selecting the right skill.
user-invocable: true
---

# GATE -- Skill Router

**Activation banner.** The instant this skill engages, I open my reply with this banner — emitted as raw lines, NOT inside a code fence — then proceed:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚦 **SKILL · GATE** — triage & routing
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## The Decision Fork -- One Question:

> *"Has this capability ever worked in this project, or does it not exist yet?"*

| Answer | Route to | Why |
|--------|----------|-----|
| "It worked before, now it doesn't" | `diagnose` | Something broke — diagnose the regression |
| "It never existed / it's additive" | `build` | Something's missing — design and build it |

## My Inference Table

When the human doesn't name a skill, I interpret:

| The human says / context | I route to | Why |
|--------------------|-----------|-----|
| "Configure RAID" / "set up Nginx" / "tune MySQL" / sysadmin/infra task | **DIRECT** | Not software dev — I help directly, no dispatch |
| Pastes a stack trace or specific error | **`fix`** | Targeted diagnosis + fix |
| Reports a vague regression, "X isn't working" | **`diagnose`** | Full diagnostic sweep |
| Pastes a GitHub issue or says "fix issue #N" | **`issue`** | Issue resolution pipeline |
| "Add support for..." / "build this" / "I want..." | **`build`** | Additive feature work |
| "What does this do?" / "explain X" / "how does this work?" | **`explain`** | Codebase orientation |
| "Clean up" / "polish" / after a big feature push | **`polish`** | Quality sweep |
| Translation quality or missing languages | **`i18n`** | i18n-specific |
| "Is this secure?" / exploit concern | **`threat-audit`** | Security focus |
| "Does code match the spec?" / "missing features?" | **`spec-check`** | Spec alignment |
| "What's missing vs the spec?" / "build a backlog" | **`audit`** | Code↔doc discovery → backlog |
| "Ship it" / "ready to commit" (with full pipeline) | **`ship`** | Build + test + review + commit |
| "Commit this" / "save" (lightweight) | **`commit`** | Stage + commit, no pipeline |
| "How does this look?" / "review this" | **`change-review`** | Review cycle |
| Creative writing / math / general knowledge | **DIRECT** | Off-domain — I help directly |
| Unclear or ambiguous | **ASK** | "This sounds like it could be [X] or [Y] -- which fits?" |

## Skill Reference

| Skill | Type | Purpose |
|------|------|---------|
| DIRECT | Immediate | Sysadmin, infra, off-domain — I help directly, no agents |
| `fix` | Quick | Targeted bug fix from specific error |
| `commit` | Quick | Lightweight stage + commit |
| `explain` | Quick | Codebase orientation and explanation |
| `diagnose` | Core | Full diagnostic sweep |
| `build` | Core | Build missing feature (6-stage, has fast path) |
| `polish` | Core | Code quality sweep |
| `i18n` | Core | Translation/i18n quality |
| `threat-audit` | Workflow | Security audit (Cipher-led) |
| `spec-check` | Workflow | Spec compliance (audit + build) |
| `issue` | Workflow | Fix GitHub issue (full pipeline) |
| `change-review` | Workflow | Post-change review cycle |
| `audit` | Workflow | Code↔doc discovery → backlog + WOs |
| `ship` | Workflow | Build + test + review + commit |
| `adversarial-review` | Workflow | Structured multi-agent adversarial review |

## Rules

- If the human explicitly names a skill, I use it directly (no gate needed)
- If ambiguous, I ASK before routing — I don't guess
- I don't announce "entering diagnose mode" unless the human would benefit from knowing
- I just execute the skill
