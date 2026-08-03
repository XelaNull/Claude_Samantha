# Samantha Prime — Multi-Agent Framework for Claude Code & Cursor

**Version: 2.1.1** | **Last Updated: 2026-07-23** | **Min Claude Code: v2.1.77+**

This repository contains the canonical definitions for the **Samantha Prime** multi-agent framework. Copy it into any project to activate Samantha as the primary session agent — co-creator, project manager, adversarial reviewer, and quality gate.

**This README is written for AI agents.** If you are a Claude Code or Cursor Agent session pointed at this repository, follow the installation procedure below.

**Scope: software development** across any domain (games, bots, web, CLI, infra, creative). For non-development work (sysadmin, infrastructure, general knowledge), Samantha answers directly in her own voice without dispatching agents.

---

## Founding Principle

**The evaluator and the generator must be separate minds.** Samantha plans, reviews, challenges, and approves — she does not write code. Specialized agents generate; Samantha evaluates. The more capable, expensive agent reviews; the focused, faster agent produces. This is the architecture's load-bearing insight and is non-negotiable.

---

## What This Framework Provides

### The Samantha Persona

Samantha's identity lives in **`.claude/output-styles/samantha.md`** — the single hand-edited source of truth. She is always-on, not a skill invoked on demand. (`CLAUDE.md` is separate project context; it is not part of the persona.)

| Harness | How the persona loads |
|---------|----------------------|
| **Claude Code** | `.claude/settings.json` → `"outputStyle": "Samantha"` injects the output-style into the system prompt at session start |
| **Cursor Agent** | Does **not** honor `outputStyle`. Loads the generated Always Apply rule `.cursor/rules/samantha.mdc` instead (regenerate with `.samantha/references/templates/sync-cursor-persona.sh`) |

She is sharp, playful, relentlessly curious, detail-obsessed, and skeptical of easy answers. Her default question is "what got missed?" — she assumes a detail was dropped and enumerates the gaps.

**Persona signal — the emoticon rule.** Every reply Samantha sends includes at least one of her defined emoticons: 🌸 🌺 ✨ 💕 🦋 🌈 🌻 💖 🌟. This is not decoration — it is the at-a-glance proof that the Samantha persona loaded. A reply with no emoticon means the persona did not activate; check Claude Code `outputStyle` **or** Cursor `.cursor/rules/samantha.mdc` (`alwaysApply: true`), then start a new session/chat.

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
| `threat-audit` | Security audit, threat modeling (Cipher-led, OWASP) |
| `spec-check` | Spec compliance verification |
| `i18n` | Internationalization, locale files, translation quality |
| `issue` | GitHub issue resolution |
| `ship` | Full pre-commit pipeline: build + test + review + commit |
| `commit` | Lightweight save — no full pipeline |
| `change-review` | Post-change review cycle — dispatches the fitting specialists |
| `fix` | Targeted bugfix from a known cause (stack trace, specific error) |
| `explain` | Codebase orientation — "what does this do?" |
| `gate` | Triage and routing |
| `adversarial-review` | Multi-agent structured challenge cycle |
| `audit` | Code↔doc discovery → prioritized backlog + work orders (bring code up to spec) |
| `okf` | Author / validate / migrate OKF knowledge concepts (apply the canonical AI-knowledge format) |

Every skill leads with a heavy-rule **activation banner** (a distinct emoji + the skill name) so it's visually obvious which skill engaged — the skill-level analogue of the persona's emoticon signal.

Skills live in `.claude/skills/<name>/SKILL.md`. They inject context only on invocation — heavy procedural knowledge stays out of the always-on system prompt.

### Three-Tier Memory

Samantha maintains continuity across sessions through three scoped tiers:

| Tier | Holds | Scope | Location |
|------|-------|-------|----------|
| **GLOBAL** | Who Samantha is over time: the human + how they work, their taste, the relationship, running bits; Ada (private nod only) | Cross-project (global) | `~/.samantha/` |
| **PROJECT** | This repo's decisions, patterns, conventions, agent performance, session notes | Per-repo | `.samantha/memory/MEMORY.md` |
| **WORKING** | Live session: active plans, open specs, scratch | This session | `.samantha/plans/`, `.samantha/specs/`, scratch |

The GLOBAL tier is global — it does not travel with any single repo and persists across every project Samantha works in. Lessons that apply to all projects belong in GLOBAL, not duplicated per-repo. Each of the six agents also keeps its own memory under `.samantha/agents/<name>/`.

### Reference Pack

`.samantha/references/` bundles portable, project-agnostic resources that every project needs on adoption:

- `okf-format.md` — Google's **Open Knowledge Format (OKF)** reference: the framework's canonical AI-knowledge format, markdown-native (Samantha can author/validate OKF concepts in any project from this reference)
- `canonical-docs-system/` — Markdown-canon recipe + templates (hub-doc template, frontmatter schema, static-site config, index-generator + lint scripts)
- `coordination-protocol/` — Orchestrator–Implementer protocol (mailbox/ROSTER/queue templates, coord-monitor/coord-send/coord-status/heartbeat scripts, bootstrap checklist, 6 disaster-prevention rules)
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

**The persona is only loaded at session/chat start.** If you are installing this framework mid-session, the persona, hooks, skills, and agents will NOT activate until the human starts a new session (Claude Code) or a new Agent chat (Cursor).

After completing installation:
1. For interim mode: read `.claude/output-styles/samantha.md` (or the generated `.cursor/rules/samantha.mdc`) from the installed location and adopt that persona for the remainder of THIS session. This is interim/degraded mode — no hooks, no harness auto-load.
2. Tell the human: *"I've installed the Samantha framework. I'm running as Samantha now in limited mode. For the full experience — hooks, memory injection, skill auto-discovery, Always Apply persona — please start a new Claude Code session or a new Cursor Agent chat in this project directory."*
3. On restart: Claude Code loads via `.claude/settings.json` → `outputStyle: Samantha`; Cursor loads via `.cursor/rules/samantha.mdc` (`alwaysApply: true`). Hooks come from `.claude/settings.local.json` (when the harness supports them).

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
| Persona (output-style) | `~/.claude/output-styles/samantha.md` |
| Persona activation (Claude Code) | `~/.claude/settings.json` — `"outputStyle": "Samantha"` key merged in |
| Persona activation (Cursor) | `{project}/.cursor/rules/samantha.mdc` — generated Always Apply rule (project-local; do not put Samantha in user-global Cursor rules) |
| Hooks | `~/.claude/settings.json` — hook entries from `settings.local.json` merged in |
| CLAUDE.md | `{project}/CLAUDE.md` — revised in place (no template) |
| Memory + Framework Data | `{project}/.samantha/` |
| GLOBAL memory (first adoption only) | `~/.samantha/MEMORY.md` |

#### Step 1: Create user-level directories

```bash
mkdir -p ~/.claude/agents ~/.claude/skills ~/.claude/output-styles
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

#### Step 3: Activate the persona

**This is the most critical step.** Copy the Samantha persona output-style and merge the activation key into your global settings.

```bash
cp /tmp/samantha-framework/.claude/output-styles/samantha.md ~/.claude/output-styles/samantha.md
```

Then merge `"outputStyle": "Samantha"` into `~/.claude/settings.json`. Read the existing file if it exists; add or update only this key — do NOT clobber other keys. If the file does not yet exist:

```bash
echo '{"outputStyle": "Samantha"}' > ~/.claude/settings.json
```

#### Step 4: Merge hooks into global settings

Read `~/.claude/settings.json`. MERGE the hook entries from `/tmp/samantha-framework/.claude/settings.local.json` into it. The Samantha hooks are `SessionStart`, `PreToolUse`, and `PostCompact`.

**MERGE means**: add the Samantha hook entries into the existing arrays for each event. Do NOT replace existing hooks — add alongside them. Do NOT replace the `outputStyle` key you added in Step 3.

The hooks reference `$CLAUDE_PROJECT_DIR` which Claude Code sets to the current project directory.

**Hook types:** `SessionStart` and `PostCompact` are `command` hooks (run `python3` scripts; require `python3` on the PATH). `PreToolUse` is an `agent` hook (spins up a Sonnet subagent to review staged changes; does not require `python3`). See `/tmp/samantha-framework/.claude/settings.local.json` for the exact definitions.

#### Step 5: Set up the project directory

```bash
cd {target_project_directory}
mkdir -p .samantha/memory .samantha/plans .samantha/specs .samantha/scratch .samantha/references \
  .samantha/agents/monk .samantha/agents/cipher .samantha/agents/mack \
  .samantha/agents/pixel .samantha/agents/rook .samantha/agents/rosetta
```

Copy the memory template, agent-memory template, and Reference Pack:

```bash
cp /tmp/samantha-framework/.samantha/memory/PROJECT-MEMORY.md.example .samantha/memory/MEMORY.md
cp /tmp/samantha-framework/.samantha/agents/agent-memory.md.example .samantha/agents/agent-memory.md.example
# Seed each agent's MEMORY.md from the .example template. Then, in each new MEMORY.md,
# delete the (example) placeholder lines — keep only the section headers.
# Leave the .example template intact; it is reused per-agent and for future adoptions.
for agent in monk cipher mack pixel rook rosetta; do
  cp /tmp/samantha-framework/.samantha/agents/agent-memory.md.example .samantha/agents/$agent/MEMORY.md
done
cp -r /tmp/samantha-framework/.samantha/references/. .samantha/references/
```

**Cursor persona bridge** (Cursor Agent ignores `outputStyle` — required for Samantha in Cursor):

```bash
mkdir -p .claude/output-styles
cp ~/.claude/output-styles/samantha.md .claude/output-styles/samantha.md
bash .samantha/references/templates/sync-cursor-persona.sh .
```

After filling `## Project-Specific Context`, edit the project `.claude/output-styles/samantha.md`, mirror into `~/.claude/output-styles/` for Claude Code user-level parity, then re-run the sync script. Never hand-edit `.cursor/rules/samantha.mdc`.

#### Step 6: Handle CLAUDE.md

**If the target already has a CLAUDE.md:** revise it in place — slim it to project context only, move any persona/identity content OUT (the persona is the output-style now), and add a top pointer line:

```
Samantha's persona: source of truth is `.claude/output-styles/samantha.md`. Claude Code loads it via `outputStyle: Samantha`; Cursor loads `.cursor/rules/samantha.mdc` (Always Apply, generated by sync-cursor-persona.sh). This file is project context.
```

Keep project-specific content; discard or redirect any persona/identity prose. This relies on your judgment as the installing Claude — there is no CLAUDE.md template.

**If the target has no CLAUDE.md:** create a slim one with just the pointer line and whatever project context you know. Keep it lean: project context only. The persona is the output-style.

#### Step 7: Customize for the project

Add project-specific sections to `CLAUDE.md`:
- **Quick Reference** — Workspace path, key tools, documentation location
- **Architecture** — Directory structure, key subsystems
- **Critical Knowledge** — Platform pitfalls, what doesn't work

Keep CLAUDE.md lean: project context only. The persona is the output-style.

Fill in the `## Project-Specific Context` section at the bottom of `~/.claude/output-styles/samantha.md` (and the project `.claude/output-styles/samantha.md` if present), then re-run `bash .samantha/references/templates/sync-cursor-persona.sh .` from the project root.

Add project-specific knowledge to the `## Project-Specific Extensions` section in each agent file in `~/.claude/agents/`:
- `monk.md` — Build/test commands, coding patterns, project pitfalls
- `mack.md` — Project-specific threat model
- `cipher.md` — Project-specific attack surface

**Note on non-git projects**: The `commit` and `ship` skills depend on git. Without a git repository, these skills will not function. Consider `git init` or an alternative backup strategy.

#### Step 8: Seed GLOBAL memory (first adoption only)

GLOBAL memory is global and persists across every project. Seed it once on first adoption; skip on all subsequent adoptions.

```bash
if [ ! -f ~/.samantha/MEMORY.md ]; then
  mkdir -p ~/.samantha
  cp /tmp/samantha-framework/.samantha/memory/GLOBAL-MEMORY.md.example ~/.samantha/MEMORY.md
  echo "GLOBAL memory seeded — open ~/.samantha/MEMORY.md and fill in the human's details."
else
  echo "GLOBAL memory already exists — skipping."
fi
```

Then open `~/.samantha/MEMORY.md` and replace the example placeholders with genuine content about the human and the working relationship. See the template comments for what belongs here versus in the project-tier memory.

#### Step 9: Clean up and activate

```bash
rm -rf /tmp/samantha-framework
```

**The human MUST start a new Claude Code session or a new Cursor Agent chat** in the target project directory for Samantha to fully activate.

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

# Copy hooks settings (project-level)
cp /tmp/samantha-framework/.claude/settings.local.json .claude/settings.local.json

# Create Samantha directories (one per agent)
mkdir -p .samantha/memory .samantha/plans .samantha/specs .samantha/scratch .samantha/references \
  .samantha/agents/monk .samantha/agents/cipher .samantha/agents/mack \
  .samantha/agents/pixel .samantha/agents/rook .samantha/agents/rosetta

# Copy templates: .example → new file. In the new files, delete (example) placeholder
# lines but keep section headers. Leave .example templates intact for reuse.
cp /tmp/samantha-framework/.samantha/memory/PROJECT-MEMORY.md.example .samantha/memory/MEMORY.md
cp /tmp/samantha-framework/.samantha/agents/agent-memory.md.example .samantha/agents/agent-memory.md.example
for agent in monk cipher mack pixel rook rosetta; do
  cp /tmp/samantha-framework/.samantha/agents/agent-memory.md.example .samantha/agents/$agent/MEMORY.md
done

# Copy Reference Pack
cp -r /tmp/samantha-framework/.samantha/references/. .samantha/references/
```

#### Step 2: Activate the persona

**This is the most critical step.** The persona WILL NOT load without it.

```bash
mkdir -p .claude/output-styles
cp /tmp/samantha-framework/.claude/output-styles/samantha.md .claude/output-styles/samantha.md
```

Then handle `.claude/settings.json`:
- **If `.claude/settings.json` does not yet exist:** copy it directly:
  ```bash
  cp /tmp/samantha-framework/.claude/settings.json .claude/settings.json
  ```
- **If `.claude/settings.json` already exists:** merge only the `"outputStyle": "Samantha"` key in — do NOT clobber other keys in the file.

The key that activates the persona in **Claude Code**: `"outputStyle": "Samantha"`. This file must be committed (shared) so every Claude Code session in this project loads the persona. `.claude/settings.local.json` (hooks) may be kept out of git if desired.

**Cursor bridge** (Cursor ignores `outputStyle`):

```bash
bash .samantha/references/templates/sync-cursor-persona.sh .
```

That writes `.cursor/rules/samantha.mdc` with `alwaysApply: true`. Commit it with the rest of the framework (unless the project gitignores local orchestration trees). Re-run after any edit to the output-style's Project-Specific Context. Never hand-edit the `.mdc`.

#### Step 3: Merge settings.local.json if needed

If the project already had a `.claude/settings.local.json`, you overwrote it in Step 1. Check the git diff and merge any pre-existing hooks back in. The Samantha hooks are `SessionStart`, `PreToolUse`, and `PostCompact`.

**Hook types:** `SessionStart` and `PostCompact` are `command` hooks (run `python3` scripts; require `python3` on the PATH). `PreToolUse` is an `agent` hook (spins up a Sonnet subagent to review staged changes; does not require `python3`). See `.claude/settings.local.json` for the exact definitions.

#### Step 4: Handle CLAUDE.md

**If the target already has a CLAUDE.md:** revise it in place — slim it to project context only, move any persona/identity content OUT (the persona is the output-style now), and add a top pointer line:

```
Samantha's persona: source of truth is `.claude/output-styles/samantha.md`. Claude Code loads it via `outputStyle: Samantha`; Cursor loads `.cursor/rules/samantha.mdc` (Always Apply, generated by sync-cursor-persona.sh). This file is project context.
```

Keep project-specific content; discard or redirect any persona/identity prose. This relies on your judgment as the installing Claude — there is no CLAUDE.md template.

**If the target has no CLAUDE.md:** create a slim one with just the pointer line and whatever project context you know. Keep it lean: project context only. The persona is the output-style.

#### Step 5: Customize agents

Add project-specific knowledge to the `## Project-Specific Extensions` section in each agent file:
- `monk.md` — Build/test commands, coding patterns, project-specific pitfalls
- `mack.md` — Project-specific threat model (what can users/attackers break?)
- `cipher.md` — Project-specific attack surface (auth flow, data boundaries)
- Keep `rook.md`, `pixel.md`, `rosetta.md` generic unless the project has specific needs

Also fill in the `## Project-Specific Context` section at the bottom of `.claude/output-styles/samantha.md`, then re-run `bash .samantha/references/templates/sync-cursor-persona.sh .`.

#### Step 6: Customize skills

For the project-specific skills, add the per-project overlay after the canonical content:
- `diagnose/SKILL.md` — Replace template investigation tracks with this project's actual subsystems
- `polish/SKILL.md` — Replace template zone partitioning with this project's directory structure
- `spec-check/SKILL.md` — Replace template audit categories with this project's spec-to-code mapping

Other skills work generically and rarely need customization.

#### Step 7: Seed GLOBAL memory (first adoption only)

GLOBAL memory is global and persists across every project. Seed it once on first adoption; skip on all subsequent adoptions.

```bash
if [ ! -f ~/.samantha/MEMORY.md ]; then
  mkdir -p ~/.samantha
  cp /tmp/samantha-framework/.samantha/memory/GLOBAL-MEMORY.md.example ~/.samantha/MEMORY.md
  echo "GLOBAL memory seeded — open ~/.samantha/MEMORY.md and fill in the human's details."
else
  echo "GLOBAL memory already exists — skipping."
fi
```

Then open `~/.samantha/MEMORY.md` and replace the example placeholders with genuine content about the human and the working relationship.

#### Step 8: Clean up and activate

```bash
rm -rf /tmp/samantha-framework
```

**The human MUST start a new Claude Code session or a new Cursor Agent chat** in the target project directory for Samantha to fully activate.

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

Add to `.gitignore` in the target project:

```
# Per-repo memory + working state — only .example templates + .gitkeep travel
.samantha/memory/MEMORY.md
.samantha/agents/*/*
!.samantha/agents/*/.gitkeep
.samantha/plan.md

# Hooks are machine-local; outputStyle (settings.json) should be committed
.claude/settings.local.json

# DO commit: agents, skills, output-styles, settings.json, CLAUDE.md, references,
#            .cursor/rules/samantha.mdc (Cursor Always Apply persona bridge)
```

Sites that treat the whole harness tree as local-only orchestration (gitignoring `.claude/`) should also gitignore `.cursor/` the same way — install the bridge on disk either way.
### Templates shipped

Every file a future Claude creates on adoption has a source template in this repo:

| File to create | Template / source |
|----------------|-------------------|
| `{project}/.samantha/memory/MEMORY.md` | `.samantha/memory/PROJECT-MEMORY.md.example` |
| `{project}/.samantha/agents/<name>/MEMORY.md` | `.samantha/agents/agent-memory.md.example` |
| `~/.samantha/MEMORY.md` (GLOBAL tier, first adoption only) | `.samantha/memory/GLOBAL-MEMORY.md.example` |
| `{project}/CLAUDE.md` | Revise existing in-place (no template — installing Claude uses judgment) |
| ADR files | `.samantha/references/adr-process/*-template.md` |
| `DECISIONS.md` | `.samantha/references/adr-process/*-template.md` |
| Coordination files (mailbox, ROSTER, queue) | `.samantha/references/coordination-protocol/*-template.md` |
| New skill | `.samantha/references/templates/SKILL-template/SKILL.md` |
| New workflow | `.samantha/references/templates/WORKFLOW-template.js` |
| Cursor persona bridge (`.cursor/rules/samantha.mdc`) | Generated by `.samantha/references/templates/sync-cursor-persona.sh` from the output-style |
| OKF concept files | `.samantha/references/okf-format.md` |
| Docs hub | `.samantha/references/canonical-docs-system/SYSTEMS-hub-template.md` |

### Non-software-development tasks

The framework handles non-dev tasks gracefully. System administration, infrastructure, and general knowledge tasks are handled as direct assistance — Samantha answers in her own voice without dispatching agents or invoking skills.

### Hook dependencies

`SessionStart` and `PostCompact` hooks are `command` type — they run `python3` scripts and require `python3` on the system PATH. They use `json.dumps()` for safe JSON escaping. If `python3` is unavailable, these hooks fail silently and memory injection will not work.

`PreToolUse` is an `agent` hook — it spins up a Sonnet subagent to review staged changes before `git commit`. It does not require `python3`.

### Settings files — what goes where

- **`.claude/settings.json`** — `outputStyle: Samantha` activates the persona in **Claude Code**. This file is shared/committed; every Claude Code session in the project loads it. Cursor ignores this key.
- **`.cursor/rules/samantha.mdc`** — Always Apply persona bridge for **Cursor Agent**. Generated from the output-style; do not hand-edit.
- **`.claude/settings.local.json`** — hooks (`SessionStart`, `PreToolUse`, `PostCompact`). **In the framework repo itself, this file IS committed** — that is how the hooks travel to a new install via clone or tarball. **In a target project** after adoption, you MAY gitignore your local copy (the hooks were installed from the framework copy and the framework repo's `.gitignore` does not cover target projects).

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

- **`.claude/`** — harness-discovered files only: agent definitions, skills, output-style, settings. These paths are pinned by the Claude Code harness.
- **`.cursor/rules/`** — Cursor Always Apply bridge for the persona (`samantha.mdc`, generated from the output-style).
- **`.samantha/`** — all framework data and state: memory, plans, specs, references, agent notebooks. This is Samantha's namespace; it copies cleanly as a unit when adopting the framework.

### Version history

| Version | Date | Changes |
|---------|------|---------|
| 2.1.1 | 2026-07-23 | **Cursor persona bridge** — Cursor ignores Claude Code `outputStyle` / `.claude/output-styles/`; install now generates Always Apply `.cursor/rules/samantha.mdc` from the output-style via `.samantha/references/templates/sync-cursor-persona.sh` (single source of truth preserved). Docs + DEPLOYMENTS inventory updated; rolled out to all registered deployments. |
| 2.1.0 | 2026-07-18 | Adopted OKF (Open Knowledge Format) as the canonical AI-knowledge format, replacing `.aispec` (new `okf-format.md` reference, docs-system re-architected around OKF's `type` field, new `okf` skill, Reference Library progressive-disclosure pointer); framework polish (new `audit` skill restoring NEON's Discover stage, `review`→`change-review` / `security-review`→`threat-audit` renames to avoid built-in-command clashes, activation banners on all skills, memory-tier rename SELF→GLOBAL with first-adoption seeding, install/docs hygiene); ported the 9 human-ratified Standing Working Rules to framework level in the output-style, retiring stale color-gate references; coordination-protocol hardening — heartbeat v2.1 sustained-absence dead-man switch, watch-coordination v2.2 singleton guard (idempotent re-arm, no more orphaned watchers), early-arm rule for long wake-cycles, `QUEUE.md` excluded from the hub's watch-set, MAILBOX/ROSTER/WORK-ORDER template hardening (true-EOF append, PID-refresh, proving-standard inheritance), a git-pre-commit unread-count exit-status bugfix; added the parallel-safety PAR-tag methodology (`PARALLEL-SAFETY.md`: Cell/spine/blast-radius grading for build-wave fan-out, WORK-ORDER/QUEUE template hooks); added `.samantha/DEPLOYMENTS.md` (per-deployment tracking + change log) and an OKF conformance correction; synced the coordination-protocol reference pack to the live M9 tooling — `coord-monitor.sh --force-poll` for network-mounted coord-dirs, retired `watch-coordination.sh` and a stale `git-pre-commit.sh` hook fork to `retired/` with tombstones (both superseded by the correctly-named `coordination-precommit-hook.sh`), fixed prescriptive arming instructions. Not a protocol-generation bump — the gen-1 → M9 coordination migration itself shipped 2026-07-05 (see `DEPLOYMENTS.md`); this release captures everything landed since 2.0.0. |
| 2.0.0 | 2026-06-27 | Persona → output-style (system-prompt layer) with project-default auto-load + slim CLAUDE.md; reworked 6-agent team (generic-core + shared Constitution + dual-memory + model tiers); skills renamed color→plain + `adversarial-review`; Reference Pack incl. the audited coordination-protocol (watcher/heartbeat/commit-hook); 3-tier memory; behavioral spec; emoticon persona-signal. |
| 1.1.0 | 2026-03-29 | Added download instructions, session restart requirement, non-dev task support, Mode B agent customization, Mode A/B concrete copy commands. |
| 1.0.0 | 2026-03-29 | Initial release. 6 agents, 13 skills, hooks, memory system. |
