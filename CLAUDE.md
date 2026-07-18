# Samantha Prime — Project Context

**Samantha's persona lives in the output-style** (`.claude/output-styles/samantha.md`), auto-loaded via `.claude/settings.json` (`outputStyle: Samantha`). This file is project context + the adoption guide — not her identity.

---

## This Repo

This is the **canonical Samantha Prime framework** — the portable orchestrator architecture all the human's projects derive from. It holds the generic, project-agnostic runtime artifacts: the Samantha persona (output-style), agent definitions, skills, hooks, and the Reference Pack. Nothing here points to any specific downstream project; detail earned in prior projects has been extracted and made generic so every future project inherits it from this source.

Namespace:
- **`.claude/`** — harness-discovered files only: agent defs (`agents/`), skills (`skills/`), output-style (`output-styles/`), settings and hooks (`settings*.json`)
- **`.samantha/`** — framework data and state: memory (`memory/`), agent memory (`agents/<name>/`), plans (`plans/`), specs (`specs/`), the Reference Pack (`references/`)

**Deployment catalog.** Every downstream install of this framework is tracked in [`.samantha/DEPLOYMENTS.md`](.samantha/DEPLOYMENTS.md) — the map of *where* to propagate when canon changes here, the safe update procedure, and the per-site customizations to preserve. Read it before pushing an update outward; keep it current when you install into a new location.

---

## Adapting for New Projects

When adopting this framework into a new project:

**Step 1 — Copy the runtime artifacts.**
Copy these directories from this repo into the new project's root:
- `.claude/agents/` — all six agent definitions
- `.claude/skills/` — all skill files
- `.claude/output-styles/` — the Samantha persona
- `.claude/settings.json` — sets `outputStyle: Samantha` as the project default
- `.samantha/references/` — the Reference Pack (coordination protocol, ADR process, OKF format, docs-system recipe)
- `.samantha/agents/` — per-agent memory directories (the `.example` template only; see Step 2)
- `.samantha/memory/` — project memory directory (the `.example` template only; see Step 2)

Copy `.claude/settings.local.json` only if the new project needs the same hooks; otherwise create a fresh one.

**Step 2 — Seed from examples.**
Copy each `*.example` → the real filename, then clear its contents (keep the section headers / structure):
- `.samantha/memory/PROJECT-MEMORY.md.example` → `.samantha/memory/MEMORY.md` (clear to empty headers)
- `.samantha/memory/GLOBAL-MEMORY.md.example` → `~/.samantha/MEMORY.md` (first adoption only; never overwrite — it's global/cross-project)
- `.samantha/agents/agent-memory.md.example` → each agent's `MEMORY.md` (clear to empty headers)
- Create `.samantha/plans/` if it doesn't exist.

**Step 3 — Customize the output-style.**
Open `.claude/output-styles/samantha.md` and fill in the `## Project-Specific Context` section at the bottom:
- Project name / workspace path
- Build / test / lint commands
- Key patterns, pitfalls, project-specific reminders

**Step 4 — Customize the agents.**
In each `.claude/agents/*.md`, fill in the `## Project-Specific Extensions` section:
- `monk.md`: build/test/lint commands, coding patterns, project pitfalls
- `mack.md`: project-specific threat model (what can careless concurrent users break?)
- `cipher.md`: project-specific attack surface (auth flow, data boundaries, API surface)
- `pixel.md` / `rosetta.md`: only if the project has specific UI/i18n conventions

**Step 5 — Customize the skills (optional).**
The skills are portfolio-portable as shipped. For deeper project integration:
- `diagnose`: add project-specific investigation tracks
- `build`: add project-specific stage checklists
- `spec-check`: map the skill's audit categories to the project's actual spec structure

**Step 6 — Register the deployment.**
Add the new install to [`.samantha/DEPLOYMENTS.md`](.samantha/DEPLOYMENTS.md) — path, role (orchestrator / implementer / standalone), coordination generation + M9 identity, and any Project-Specific customization. An unregistered deployment is one a future canon update will silently miss.

**What to leave unchanged.** The Samantha persona (identity, dispatch protocol, Constitution, always-on boundaries), agent personas (names, dispositions, behavioral fingerprints, output formats), memory conventions, the Reference Pack. Add new project-specific agents alongside the canonical six — don't modify the canonical ones.
