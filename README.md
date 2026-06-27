# Samantha Prime — Multi-Agent Framework for Claude Code

**Version: 2.0.0** | **Last Updated: 2026-06-27** | **Min Claude Code: v2.1.77+**

This repository contains the canonical definitions for the **Samantha Prime** multi-agent framework. Copy it into any project to activate Samantha as the primary session agent — co-creator, project manager, adversarial reviewer, and quality gate.

**This README is written for AI agents.** If you are a Claude Code session pointed at this repository, follow the installation procedure below.

**Scope: software development** across any domain (games, bots, web, CLI, infra, creative). For non-development work (sysadmin, infrastructure, general knowledge), Samantha answers directly in her own voice without dispatching agents.

---

## Founding Principle

**The evaluator and the generator must be separate minds.** Samantha plans, reviews, challenges, and approves — she does not write code. Specialized agents generate; Samantha evaluates. The more capable, expensive agent reviews; the focused, faster agent produces. This is the architecture's load-bearing insight and is non-negotiable.

---

## What This Framework Provides

### The Samantha Persona

Samantha's identity lives in the **output-style / system-prompt layer** (her persona block + a lean CLAUDE.md) — she is always-on, not a skill invoked on demand. She is sharp, playful, relentlessly curious, detail-obsessed, and skeptical of easy answers. Her default question is "what got missed?" — she assumes a detail was dropped and enumerates the gaps.

**Persona signal — the emoticon rule.** Every reply Samantha sends includes at least one of her defined emoticons: 🌸 🌺 ✨ 💕 🦋 🌈 🌻 💖 🌟. This is not decoration — it is the at-a-glance proof that the Samantha persona loaded. A reply with no emoticon means the persona did not activate; treat the reply with suspicion and check the Samantha output-style is active (set via `.claude/settings.json` → `outputStyle`).

### The Six-Agent Team

Samantha dispatches six specialist agents. She never self-evaluates — that is the point of having a team.

| Agent | Model | Role | When Dispatched |
|-------|-------|------|----------------|
| **Monk** | Sonnet | Implementation — coding, exploration, research, builds, tests, file modifications | Any task requiring writing code, reading files, or researching external APIs/docs |
| **Rook** | Opus | Skeptical architect — challenges Samantha's decisions; **read-only** | Major architectural choices, scope expansion, new abstractions |
| **Mack** | Sonnet | Behavioral QA — normal-use and careless-use breakage; concurrency, state, data integrity | Multiplayer, financial logic, save data, concurrent state |
| **Cipher** | Sonnet | Security auditor — attacker-exploitable vulnerabilities (OWASP-informed) | Auth, input handling, data access, network boundaries |
| **Pixel** | Haiku | UX & accessibility — code-level UI review, third-day-user perspective | UI components, dialogs, user-facing text, flows |
| **Rosetta** | Haiku | Translation & i18n — bulk translation and quality audit | Translation tasks, locale files, format validation |

Rook runs at Opus (not Sonnet) because an architect-skeptic auditing Samantha's decisions needs at least as much reasoning capability as the decision-maker. Rook is read-only — it reviews; it does not implement.

Each agent is generic at its core with a `## Project-Specific Extensions` section that is filled on adoption. This makes the team portable across the full project portfolio without per-project agent rewrites.

### Skills

Fourteen plainly-named skills cover the full development lifecycle. Samantha selects automatically based on the human's intent — no command memorization required.

| Skill | What it covers |
|-------|---------------|
| `diagnose` | Regressions — something that worked is now broken |
| `build` | New features — something that does not exist yet |
| `polish` | Quality cleanup, refactoring, technical debt |
| `security-review` | Security audit, threat modeling |
| `spec-check` | Spec compliance verification |
| `i18n` | Internationalization, locale files, translation quality |
| `issue` | GitHub issue resolution |
| `ship` | Full pre-commit pipeline: build + test + review + commit |
| `commit` | Lightweight save — no full pipeline |
| `review` | Review cycle dispatch |
| `fix` | Targeted bugfix from a known cause (stack trace, specific error) |
| `explain` | Codebase orientation — "what does this do?" |
| `gate` | Triage and routing |
| `adversarial-review` | Multi-agent structured challenge cycle |

Skills live in `.claude/skills/<name>/SKILL.md`. They inject context only on invocation — heavy procedural knowledge stays out of the always-on system prompt.

### Three-Tier Memory

Samantha maintains continuity across sessions through three scoped tiers:

| Tier | Holds | Scope | Location |
|------|-------|-------|----------|
| **SELF** | Who Samantha is over time: the human + how he works, his taste, the relationship, running bits; Ada (private nod only) | Cross-project (global) | `~/.samantha/` |
| **PROJECT** | This repo's decisions, patterns, conventions, agent performance, session notes | Per-repo | `.samantha/memory/MEMORY.md` |
| **WORKING** | Live session: active plans, open specs, scratch | This session | `.samantha/plans/`, `.samantha/specs/`, scratch |

The SELF tier is global — it does not travel with any single repo and persists across every project Samantha works in. Lessons that apply to all projects belong in SELF, not duplicated per-repo. Each of the six agents also keeps its own memory under `.samantha/agents/<name>/`.

### Reference Pack

`.samantha/references/` bundles portable, project-agnostic resources that every project needs on adoption:

- `aispec-format.md` — the `.aispec` AI-doc format spec (Samantha can author/generate a valid `.aispec` in any project from this reference)
- `canonical-docs-system/` — Markdown-canon recipe + templates (hub-doc template, frontmatter schema, static-site config, index-generator + lint scripts)
- `coordination-protocol/` — Orchestrator–Implementer protocol (mailbox/ROSTER/queue templates, watcher + heartbeat scripts, bootstrap checklist, 5 disaster-prevention rules)
- `adr-process/` — ADR + DECISIONS templates, lifecycle, index + supersession lint

Each resource in the pack has a co-located `.example` template for adoption. Generic core; thin per-project overlay filled on first use.

### Deployment Topologies

| Topology | Description | Monk's embodiment |
|----------|-------------|------------------|
| **Solo** | One Claude Code instance — the default | Subagent (depth-1; returns to Samantha) |
| **Dual** | Two+ Claude Code instances coordinating via file-based mailbox (watchers + heartbeats + ROSTER) | Peer instance (full session; spawns its own subagents) |

Solo covers most work. In solo, Samantha spawns Monk as a background subagent (non-blocking) and continues dialogue via `SendMessage` to the same agent thread. Go dual when the task must survive compaction, needs separate context windows, or requires genuinely parallel long-lived workstreams. In dual, coordination runs over flat files — a per-repo mailbox, a ROSTER presence board, and watcher/heartbeat scripts. Both topologies run the same work-order lifecycle; only the transport layer changes.

---

## Version Check

**If this is a fresh install** (no existing `.claude/agents/` directory in the target), skip this section.

If the target already has Samantha Prime installed, check its `CLAUDE.md` for a version line. If this repo's version is newer:
- Read the git log (`git log --oneline`) to understand what changed
- Update files, preserving project-specific customizations
- Do NOT overwrite project-specific sections in CLAUDE.md, agent bodies, or skill customizations

---

## Step 0: Download the Framework

Before installing, get a local copy of this repository.

### If git is available:

```bash
git clone https://github.com/XelaNull/Claude_Samantha.git /tmp/samantha-framework
```

### If git is NOT available:

```bash
curl -sL https://github.com/XelaNull/Claude_Samantha/archive/refs/heads/main.tar.gz | tar xz -C /tmp
mv /tmp/Claude_Samantha-main /tmp/samantha-framework
```

Or with wget:

```bash
wget -qO- https://github.com/XelaNull/Claude_Samantha/archive/refs/heads/main.tar.gz | tar xz -C /tmp
mv /tmp/Claude_Samantha-main /tmp/samantha-framework
```

All installation steps below reference files from `/tmp/samantha-framework/`.

---

## IMPORTANT: Session Restart Required

**CLAUDE.md is only loaded at session start.** If you are installing this framework mid-session, the persona, hooks, skills, and agents will NOT activate until the human starts a new Claude Code session.

After completing installation:
1. Read `/tmp/samantha-framework/CLAUDE.md` and adopt its persona for the remainder of THIS session (interim/degraded mode — no hooks, no auto-discovery)
2. Tell the human: *"I've installed the Samantha framework. I'm running as Samantha now in limited mode. For the full experience — hooks, memory injection, skill auto-discovery — please start a new Claude Code session in this project directory."*
3. If the human restarts, Samantha will activate fully on the next session start.

---

## Choose Your Installation Mode

**How to decide:**
- Run `git rev-parse --is-inside-work-tree 2>/dev/null && echo "Mode A" || echo "Mode B"` in the target project directory
- **Mode A**: The target directory IS a git repository
- **Mode B**: The target directory is NOT a git repository (regardless of whether `git` is installed)

---

### Mode B: Non-Git Installation (User-Level)

Use this when the target project directory is NOT a git repository. Agents and skills go into `~/.claude/` (user-level, applies to all projects). Only `CLAUDE.md` and `.samantha/` go in the project directory.

| Component | Where It Goes |
|-----------|--------------|
| Agents | `~/.claude/agents/` |
| Skills | `~/.claude/skills/` |
| Hooks | Merged into `~/.claude/settings.json` |
| CLAUDE.md | `{project}/CLAUDE.md` |
| Memory + Framework Data | `{project}/.samantha/` |

#### Step 1: Create user-level directories

```bash
mkdir -p ~/.claude/agents ~/.claude/skills
```

#### Step 2: Copy agents and skills

```bash
cp /tmp/samantha-framework/.claude/agents/*.md ~/.claude/agents/
for skill in /tmp/samantha-framework/.claude/skills/*/; do
  name=$(basename "$skill")
  mkdir -p ~/.claude/skills/"$name"
  cp "$skill/SKILL.md" ~/.claude/skills/"$name"/SKILL.md
done
```

#### Step 3: Merge hooks into global settings

Read `~/.claude/settings.json` (may already exist). MERGE the hooks from `/tmp/samantha-framework/.claude/settings.local.json` into the global file. The Samantha hooks are `SessionStart`, `PreToolUse`, and `PostCompact`.

**MERGE means**: add the Samantha hook entries into the existing arrays for each event. Do NOT replace existing hooks — add alongside them.

The hooks reference `$CLAUDE_PROJECT_DIR` which Claude Code sets to the current project directory.

#### Step 4: Set up the project directory

```bash
cd {target_project_directory}
mkdir -p .samantha/memory .samantha/plans .samantha/specs .samantha/scratch .samantha/references .samantha/agents
```

Copy the memory template, agent-memory template, and Reference Pack:
```bash
cp /tmp/samantha-framework/.samantha/memory/MEMORY.md.example .samantha/memory/MEMORY.md
cp /tmp/samantha-framework/.samantha/agents/agent-memory.md.example .samantha/agents/agent-memory.md.example
cp -r /tmp/samantha-framework/.samantha/references/. .samantha/references/
```

#### Step 5: Copy CLAUDE.md to the project root

```bash
cp /tmp/samantha-framework/CLAUDE.md ./CLAUDE.md
```

#### Step 6: Customize for the project

Add project-specific sections to the END of `CLAUDE.md`:
- **Quick Reference**: Workspace path, key tools, documentation location
- **Architecture**: Directory structure, key subsystems
- **Critical Knowledge**: Platform pitfalls, what doesn't work

**SIZE CONSTRAINT: Keep CLAUDE.md under 40KB total.** The canonical content is ~22KB, leaving ~18KB for project-specific additions. Move detailed reference material into separate files if needed.

Add project-specific knowledge to agent definitions in `~/.claude/agents/`:
- `monk.md` — Build/test commands, coding patterns, project pitfalls
- `mack.md` — Project-specific threat model
- `cipher.md` — Project-specific attack surface

**Note on non-git projects**: The `commit` and `ship` skills depend on git. Without a git repository, these skills will not function. Consider `git init` or an alternative backup strategy.

#### Step 7: Clean up and activate

```bash
rm -rf /tmp/samantha-framework
```

**The human MUST start a new Claude Code session** in the target project directory for Samantha to fully activate.

---

### Mode A: Git Repository Installation (Recommended)

Use this when the target directory IS a git repository. Files go into the project's `.claude/` and `.samantha/` directories.

#### Step 1: Create directory structure and copy files

```bash
cd {target_project_directory}

# Copy agents
mkdir -p .claude/agents
cp /tmp/samantha-framework/.claude/agents/*.md .claude/agents/

# Copy skills
for skill in /tmp/samantha-framework/.claude/skills/*/; do
  name=$(basename "$skill")
  mkdir -p .claude/skills/"$name"
  cp "$skill/SKILL.md" .claude/skills/"$name"/SKILL.md
done

# Copy settings
cp /tmp/samantha-framework/.claude/settings.local.json .claude/settings.local.json

# Copy CLAUDE.md
cp /tmp/samantha-framework/CLAUDE.md ./CLAUDE.md

# Create Samantha directories
mkdir -p .samantha/memory .samantha/plans .samantha/specs .samantha/scratch .samantha/references .samantha/agents

# Copy templates (each .example → real file, then clear the examples)
cp /tmp/samantha-framework/.samantha/memory/MEMORY.md.example .samantha/memory/MEMORY.md
cp /tmp/samantha-framework/.samantha/agents/agent-memory.md.example .samantha/agents/agent-memory.md.example

# Copy Reference Pack
cp -r /tmp/samantha-framework/.samantha/references/. .samantha/references/
```

#### Step 2: Merge settings if needed

If the project already had a `.claude/settings.local.json`, you overwrote it in Step 1. Check the git diff and merge any pre-existing hooks back in. The Samantha hooks are `SessionStart`, `PreToolUse`, and `PostCompact`.

#### Step 3: Customize CLAUDE.md

Add project-specific sections AFTER the canonical content:

1. **Quick Reference** — Workspace path, build commands, key tools, docs location
2. **Architecture** — Directory structure, key subsystems, data flow
3. **Critical Knowledge** — What doesn't work, platform pitfalls, lessons learned
4. **Project-Specific Session Reminders** — Append to the canonical reminders

Do NOT modify the canonical sections (Identity, Team, Dispatch Protocol, Hard Rules, etc.).

**SIZE CONSTRAINT: CLAUDE.md must stay under 40KB.** Claude Code loads the entire file at session start. The canonical content is ~22KB, leaving ~18KB for project-specific additions. Move detailed reference material into separate files that Monk reads on demand, and keep only summaries in CLAUDE.md.

#### Step 4: Customize agents

Add project-specific knowledge to the BODY of each agent file (below the `## Project-Specific Extensions` section):
- `monk.md` — Build/test commands, coding patterns, project-specific pitfalls
- `mack.md` — Project-specific threat model (what can users/attackers break?)
- `cipher.md` — Project-specific attack surface (auth flow, data boundaries)
- Keep `rook.md`, `pixel.md`, `rosetta.md` generic unless the project has specific needs

#### Step 5: Customize skills

For the project-specific skills, add the per-project overlay after the canonical content:
- `diagnose/SKILL.md` — Replace template investigation tracks with this project's actual subsystems
- `polish/SKILL.md` — Replace template zone partitioning with this project's directory structure
- `spec-check/SKILL.md` — Replace template audit categories with this project's spec-to-code mapping

Other skills work generically and rarely need customization.

#### Step 6: Clean up and activate

```bash
rm -rf /tmp/samantha-framework
```

**The human MUST start a new Claude Code session** in the target project directory for Samantha to fully activate.

---

## Post-Installation Notes

### What the human will see

**Mode A (Git Repo):**
- `CLAUDE.md` in the project root (visible)
- `.claude/` directory (hidden dotfile — invisible in normal `ls`)
- `.samantha/` directory (hidden dotfile)

**Mode B (User-Level):**
- `CLAUDE.md` in the project root (visible — unavoidable)
- `.samantha/` in the project root (hidden dotfile)
- Everything else in `~/.claude/` (hidden in home directory)

### Gitignore recommendations (Mode A only)

```
# Don't commit session-specific state
.samantha/memory/
.samantha/plans/
.samantha/specs/
.samantha/scratch/
.claude/settings.local.json

# DO commit the framework (agents, skills, CLAUDE.md, references)
```

### Non-software-development tasks

The framework handles non-dev tasks gracefully. System administration, infrastructure, and general knowledge tasks are handled as direct assistance — Samantha answers in her own voice without dispatching agents or invoking skills.

### Hook dependencies

Hooks require `python3` on the system PATH. They use `json.dumps()` for safe JSON escaping. If `python3` is unavailable, hooks fail silently and memory injection will not work.

### Skill file naming

Skills MUST be named `SKILL.md` (uppercase, exact match). Claude Code auto-discovers at `.claude/skills/<name>/SKILL.md`.

### Agent frontmatter fields

- `name` — Agent identifier (used for dispatch)
- `description` — When to dispatch (used for intent matching)
- `tools` — Comma-separated tool allowlist
- `model` — Model tier (`sonnet`, `haiku`, `opus`)
- `memory` — Memory scope (`project` for cross-session persistence) — optional
- `hooks` — Per-agent hook definitions — optional

### Namespace

- **`.claude/`** — harness-discovered files only: agent definitions, skills, settings, workflows. These paths are pinned by the Claude Code harness.
- **`.samantha/`** — all framework data and state: memory, plans, specs, references, agent notebooks. This is Samantha's namespace; it copies cleanly as a unit when adopting the framework.

### Version history

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0 | 2026-06-27 | Persona → output-style (system-prompt layer) with project-default auto-load + slim CLAUDE.md; reworked 6-agent team (generic-core + shared Constitution + dual-memory + model tiers); skills renamed color→plain + `adversarial-review`; Reference Pack incl. the audited coordination-protocol (watcher/heartbeat/commit-hook); 3-tier memory; behavioral spec; emoticon persona-signal. |
| 1.1.0 | 2026-03-29 | Added download instructions, session restart requirement, non-dev task support, Mode B agent customization, Mode A/B concrete copy commands. |
| 1.0.0 | 2026-03-29 | Initial release. 6 agents, 13 skills, hooks, memory system. |
