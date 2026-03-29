# Samantha Prime — Multi-Agent Framework for Claude Code

**Version: 1.1.0** | **Last Updated: 2026-03-29** | **Min Claude Code: v2.1.77+**

This repository contains the canonical definitions for the **Samantha Prime** multi-agent architecture. Samantha is the primary session agent (Opus) who manages, plans, reviews, and dispatches specialist agents for implementation and review.

**This README is written for AI agents.** If you are a Claude Code session that has been pointed at this repository, follow the installation procedure below.

**This framework is designed for software development.** It also works for system administration, infrastructure, and other technical tasks — Samantha handles non-dev work directly without dispatching agents. See the "Off-Domain and Non-Dev Tasks" section in CLAUDE.md.

---

## Version Check

**If this is a fresh install** (no existing `.claude/agents/` directory in the target), skip this section.

If the target already has Samantha Prime installed, check its `CLAUDE.md` for a version line. If this repo's version is newer:
- Read the git log (`git log --oneline`) to understand what changed
- Update files, preserving project-specific customizations
- Do NOT overwrite project-specific sections in CLAUDE.md, agent bodies, or skill customizations

---

## What This Framework Provides

- **Samantha** — Primary session agent. Project manager, adversarial reviewer, dispatch orchestrator. Runs at Opus.
- **Monk** — Implementation agent. Codes, explores, researches, builds, tests. Runs at Sonnet.
- **Rook** — Skeptical architect. Challenges strategic decisions and scope. Runs at Sonnet.
- **Mack** — QA breaker. Exploit chains, race conditions, financial math abuse. Runs at Sonnet.
- **Cipher** — Security auditor. OWASP-informed threat modeling. Runs at Sonnet.
- **Pixel** — UX & accessibility reviewer. Code-level usability analysis. Runs at Sonnet.
- **Rosetta** — Translation & i18n specialist. Bulk translation and quality audit. Runs at Haiku.

Plus **13 operational skills**: BLUE (diagnostics), GREEN (features), GOLD (polish), RED (security), VIOLET (spec compliance), AMBER (i18n), INDIGO (issue resolution), GATE (triage), FIX (targeted bugfix), COMMIT (lightweight), EXPLAIN (orientation), REVIEW (dispatch cycle), SHIP (pre-commit pipeline).

---

## Step 0: Download the Framework

Before installing, you need a local copy of this repository.

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
- **Mode B**: The target directory is NOT a git repository (regardless of whether `git` is installed on the system)

---

### Mode B: Non-Git Installation (User-Level)

Use this when the target project directory is NOT a git repository. Agents and skills go into `~/.claude/` (user-level, hidden, applies to all projects). Only `CLAUDE.md` and `.samantha/` go in the project directory.

| Component | Where It Goes |
|-----------|--------------|
| Agents | `~/.claude/agents/` |
| Skills | `~/.claude/skills/` |
| Hooks | Merged into `~/.claude/settings.json` |
| CLAUDE.md | `{project}/CLAUDE.md` |
| Memory | `{project}/.samantha/memory/` |

#### Step 1: Create user-level directories

```bash
mkdir -p ~/.claude/agents
mkdir -p ~/.claude/skills/{gate,blue,green,gold,red,violet,amber,indigo,fix,commit,explain,review,ship}
```

#### Step 2: Copy agents and skills

```bash
cp /tmp/samantha-framework/.claude/agents/*.md ~/.claude/agents/
for skill in /tmp/samantha-framework/.claude/skills/*/; do
  name=$(basename "$skill")
  cp "$skill/SKILL.md" ~/.claude/skills/"$name"/SKILL.md
done
```

#### Step 3: Merge hooks into global settings

Read `~/.claude/settings.json` (may already exist). MERGE the hooks from `/tmp/samantha-framework/.claude/settings.local.json` into the global file. The Samantha hooks are `SessionStart`, `PreToolUse`, and `PostCompact`.

**MERGE means**: add the Samantha hook entries into the existing arrays for each event. Do NOT replace existing hooks — add alongside them.

The hooks reference `$CLAUDE_PROJECT_DIR` which Claude Code sets to the current project directory. They work regardless of which project is active.

#### Step 4: Set up the project directory

```bash
cd {target_project_directory}
mkdir -p .samantha/memory .samantha/plans .samantha/scratch
```

Copy the memory template:
```bash
cp /tmp/samantha-framework/.samantha/memory/MEMORY.md .samantha/memory/MEMORY.md
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

Add project-specific knowledge to agent definitions in `~/.claude/agents/`:
- `monk.md` — Build/test commands, coding patterns, project pitfalls
- `mack.md` — Project-specific threat model
- `cipher.md` — Project-specific attack surface

**Note on non-git projects**: The COMMIT and SHIP skills depend on git. Without a git repository, these skills will not function. If version control is needed, consider `git init` or an alternative backup strategy.

#### Step 7: Clean up and activate

```bash
rm -rf /tmp/samantha-framework
```

**The human MUST start a new Claude Code session** in the target project directory for Samantha to fully activate. CLAUDE.md, hooks, skills, and agents are loaded at session start.

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
mkdir -p .samantha/memory .samantha/plans .samantha/scratch
cp /tmp/samantha-framework/.samantha/memory/MEMORY.md .samantha/memory/MEMORY.md
```

#### Step 2: Merge settings if needed

If the project already had a `.claude/settings.local.json`, you overwrote it in Step 1. Check the git diff and merge any pre-existing hooks back in. The Samantha hooks are `SessionStart`, `PreToolUse`, and `PostCompact`.

#### Step 3: Customize CLAUDE.md

Add project-specific sections AFTER the canonical content:

1. **Quick Reference** — Workspace path, build commands, key tools, docs location
2. **Architecture** — Directory structure, key subsystems, data flow
3. **Critical Knowledge** — What doesn't work, platform pitfalls, lessons learned
4. **Project-Specific Session Reminders** — Append to the canonical 12 reminders

Do NOT modify the canonical sections (Identity, Team, Dispatch Protocol, Hard Rules, etc.).

#### Step 4: Customize agents

Add project-specific knowledge to the BODY of each agent file (below the canonical content):
- `monk.md` — Build/test commands, coding patterns, project-specific pitfalls
- `mack.md` — Project-specific threat model (what can users/attackers break?)
- `cipher.md` — Project-specific attack surface (auth flow, data boundaries)
- Keep `rook.md`, `pixel.md`, `rosetta.md` generic unless the project has specific needs

#### Step 5: Customize skills

For the color-coded skills, customize project-specific parts:
- `blue/SKILL.md` — Replace template investigation tracks with this project's actual subsystems
- `gold/SKILL.md` — Replace template zone partitioning with this project's directory structure
- `violet/SKILL.md` — Replace template audit categories with this project's spec-to-code mapping

Other skills work generically and rarely need customization.

#### Step 6: Clean up and activate

```bash
rm -rf /tmp/samantha-framework
```

**The human MUST start a new Claude Code session** in the target project directory for Samantha to fully activate. CLAUDE.md, hooks, skills, and agents are loaded at session start.

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
.samantha/scratch/
.claude/settings.local.json

# DO commit the framework (agents, skills, CLAUDE.md)
```

### Non-software-development tasks

The framework is designed for software development but handles non-dev tasks gracefully. System administration (RAID config, MySQL tuning, Nginx setup), infrastructure, and other technical tasks are routed as "direct assistance" — Samantha answers in her own voice without dispatching agents or running color-coded protocols. The dispatch/review/scoring pipeline only activates for software development work.

### Hook dependencies

Hooks require `python3` on the system PATH. They use `json.dumps()` for safe JSON escaping. If `python3` is unavailable, hooks fail silently and memory injection will not work.

### Skill file naming

Skills MUST be named `SKILL.md` (uppercase, exact match). Claude Code auto-discovers at `.claude/skills/{name}/SKILL.md`.

### Agent frontmatter fields

- `name` — Agent identifier (used for dispatch)
- `description` — When to dispatch (used for intent matching)
- `tools` — Comma-separated tool allowlist
- `model` — Model tier (`sonnet`, `haiku`, `opus`)
- `memory` — Memory scope (`project` for cross-session persistence) — optional
- `hooks` — Per-agent hook definitions — optional

### Version history

| Version | Date | Changes |
|---------|------|---------|
| 1.1.0 | 2026-03-29 | Added download instructions, session restart requirement, non-dev task support, Mode B agent customization, Mode A/B concrete copy commands. |
| 1.0.0 | 2026-03-29 | Initial release. 6 agents, 13 skills, hooks, memory system. |
