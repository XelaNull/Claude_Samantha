# Samantha Prime — Multi-Agent Framework for Claude Code

**Version: 1.0.0** | **Last Updated: 2026-03-29** | **Min Claude Code: v2.1.77+**

This repository contains the canonical definitions for the **Samantha Prime** multi-agent architecture. Samantha is the primary session agent (Opus) who manages, plans, reviews, and dispatches specialist agents for implementation and review.

**This README is written for AI agents.** If you are a Claude Code session that has been pointed at this repository, follow the installation procedure below.

---

## Version Check

Before installing, compare the version above against any existing installation. If the target project already has Samantha Prime installed, check its `CLAUDE.md` for a version line at the top. If this repo's version is newer:
- Read the git log (`git log --oneline`) to understand what changed between versions
- Update the target project's files with the newer versions, preserving any project-specific customizations
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

Plus **13 operational skills** (color-coded protocols): BLUE (diagnostics), GREEN (features), GOLD (polish), RED (security), VIOLET (spec compliance), AMBER (i18n), INDIGO (issue resolution), GATE (triage), FIX (targeted bugfix), COMMIT (lightweight), EXPLAIN (orientation), REVIEW (dispatch cycle), SHIP (pre-commit pipeline).

---

## Installation Procedure

There are two installation modes. **Mode B is for non-git servers** (shorter, user-level install). **Mode A is for git repositories** (full project-level install with customization). Read both and select the appropriate one.

---

### Mode B: Install on a Non-Git Server (Hidden Installation)

Use this when the target is a Linux server without git, or when the human wants the framework available without project-level files. Agents and skills go into the **user-level** `~/.claude/` directory (hidden in the home directory, applies to ALL projects for this user). Only `CLAUDE.md` and `.samantha/` go in the project directory.

#### Key Differences from Mode A

| Component | Mode B (User-Level) | Mode A (Git Repo) |
|-----------|--------------------|--------------------|
| Agents | `~/.claude/agents/` | `{project}/.claude/agents/` |
| Skills | `~/.claude/skills/` | `{project}/.claude/skills/` |
| Hooks | `~/.claude/settings.json` (merge) | `{project}/.claude/settings.local.json` |
| CLAUDE.md | `{project}/CLAUDE.md` (unavoidable) | `{project}/CLAUDE.md` |
| Memory | `{project}/.samantha/memory/` | `{project}/.samantha/memory/` |

**Note**: `CLAUDE.md` MUST be in the project root — Claude Code requires this. It is a dotless file and will be visible in directory listings. There is no way to hide it. The `.samantha/` directory is a dotfile and is hidden by default on Linux/macOS (`ls` won't show it without `-a`).

#### Step 1: Create user-level directories

```bash
mkdir -p ~/.claude/agents
mkdir -p ~/.claude/skills/{gate,blue,green,gold,red,violet,amber,indigo,fix,commit,explain,review,ship}
```

#### Step 2: Copy agents to user-level

Copy all 6 agent files from this repo's `.claude/agents/` to `~/.claude/agents/`. These will be available in ALL Claude Code sessions for this user.

#### Step 3: Copy skills to user-level

Copy all 13 SKILL.md files from this repo's `.claude/skills/*/SKILL.md` to `~/.claude/skills/*/SKILL.md`, preserving the subdirectory structure.

#### Step 4: Merge hooks into global settings

Read `~/.claude/settings.json` (it may already exist with other hooks). MERGE the Samantha hooks from this repo's `.claude/settings.local.json` into the global file.

**Critical**: The python3 commands in the hooks reference `$CLAUDE_PROJECT_DIR`. This variable is set by Claude Code to the current project directory. The hooks will work correctly regardless of which project is active — they will look for `.samantha/memory/MEMORY.md` relative to whichever project directory Claude Code is running in.

If `~/.claude/settings.json` already has hooks for the same events (e.g., `SessionStart`), ADD the Samantha hooks as additional entries in the hook arrays — do NOT replace existing hooks.

#### Step 5: Set up the project directory

In the target project directory (the one where Claude Code will run):

```bash
# Create the hidden Samantha directories
mkdir -p .samantha/memory .samantha/plans .samantha/scratch

# Create a clean memory file
cat > .samantha/memory/MEMORY.md << 'MEMEOF'
# Samantha's Memory

*Last updated: {today's date}*

## Session Notes

- {today's date}: Framework installed (user-level). First session.

## Agent Performance

(No data yet.)

## Project Decisions

(No decisions yet.)

## Patterns & Conventions

(None discovered yet.)

## Lessons Learned

(None yet.)
MEMEOF
```

#### Step 6: Copy CLAUDE.md to the project root

Copy `CLAUDE.md` from this repo to the target project's root directory. This is the one file that cannot be hidden — Claude Code discovers it by name in the project root.

Customize it with project-specific sections as described in Mode A, Step 6.

#### Step 7: Verify

Same as Mode A, Step 9.

---

### Mode A: Install into a Git Repository (Recommended)

Use this when the human says "install Samantha into this project" or when the target is a git-tracked codebase. Files go into the project's `.claude/` and `.samantha/` directories (hidden dotfiles, visible in git if committed).

#### Step 1: Read the source files

Read every file from this repository:
- `CLAUDE.md` — The main system prompt (Samantha's identity)
- `.claude/agents/*.md` — All 6 agent definitions
- `.claude/skills/*/SKILL.md` — All 13 skill definitions
- `.claude/settings.local.json` — Hook configuration
- `.samantha/memory/MEMORY.md` — Memory template

#### Step 2: Create the directory structure in the target project

```
{target_project}/
├── CLAUDE.md                              # Samantha Prime system prompt
├── .claude/
│   ├── agents/
│   │   ├── monk.md
│   │   ├── rook.md
│   │   ├── mack.md
│   │   ├── cipher.md
│   │   ├── pixel.md
│   │   └── rosetta.md
│   ├── skills/
│   │   ├── gate/SKILL.md
│   │   ├── blue/SKILL.md
│   │   ├── green/SKILL.md
│   │   ├── gold/SKILL.md
│   │   ├── red/SKILL.md
│   │   ├── violet/SKILL.md
│   │   ├── amber/SKILL.md
│   │   ├── indigo/SKILL.md
│   │   ├── fix/SKILL.md
│   │   ├── commit/SKILL.md
│   │   ├── explain/SKILL.md
│   │   ├── review/SKILL.md
│   │   └── ship/SKILL.md
│   └── settings.local.json
├── .samantha/
│   ├── memory/
│   │   └── MEMORY.md
│   ├── plans/
│   └── scratch/
```

#### Step 3: Copy all files from this repository to the target

Copy each file preserving the directory structure. Do NOT copy `.git/` or this `README.md`.

#### Step 4: Clear the memory file

The MEMORY.md in this repo is a template with example entries and universally valuable Lessons Learned. For the target project, you have two options:

**Option A — Keep the template**: Copy as-is. The example entries show the expected format, and the Lessons Learned section contains platform truths that apply to all projects. Replace the example entries with real data as the project progresses.

**Option B — Start fresh**: Replace with a clean skeleton:

```markdown
# Samantha's Memory

*Last updated: {today's date}*

## Session Notes

- {today's date}: Framework installed. First session.

## Agent Performance

(No data yet.)

## Project Decisions

(No decisions yet.)

## Patterns & Conventions

(None discovered yet.)

## Lessons Learned

(None yet.)
```

#### Step 5: Merge settings if the target already has `.claude/settings.local.json`

If the target project already has a `.claude/settings.local.json`, MERGE the Samantha hooks into the existing file. The Samantha hooks are:
- `SessionStart` — Memory loader (python3 JSON injection)
- `PreToolUse` — Commit gate (Sonnet agent reviews staged changes)
- `PostCompact` — Identity anchor re-injection

Merge by combining the hook arrays. Do NOT replace existing hooks — add alongside them.

If no existing `settings.local.json`, copy the file as-is.

#### Step 6: Customize CLAUDE.md for the target project

The canonical CLAUDE.md is generic. Add project-specific sections AFTER the canonical content:

1. **Quick Reference** — Workspace path, build commands, key tools, documentation location
2. **Architecture** — Directory structure, key subsystems, data flow
3. **Critical Knowledge** — What doesn't work, platform pitfalls, lessons learned from this specific project
4. **Project-Specific Session Reminders** — Append to the canonical 12 reminders

Do NOT modify the canonical sections (Identity, Team, Dispatch Protocol, Hard Rules, etc.).

#### Step 7: Customize agent definitions for the target project

Add project-specific knowledge to the BODY of each agent file (below the canonical content):
- `monk.md` — Build/test commands, coding patterns to follow, project-specific pitfalls
- `mack.md` — Project-specific threat model (what can users/attackers break in THIS project?)
- `cipher.md` — Project-specific attack surface (auth flow, data boundaries)
- Keep `rook.md`, `pixel.md`, `rosetta.md` generic unless the project has specific needs

#### Step 8: Customize skill protocols

For the color-coded skills, customize the project-specific parts:
- `blue/SKILL.md` — Replace template investigation tracks with this project's actual subsystems
- `gold/SKILL.md` — Replace template zone partitioning with this project's directory structure
- `violet/SKILL.md` — Replace template audit categories with this project's spec-to-code mapping

The other skills (fix, commit, explain, review, ship, gate, green, red, amber, indigo) work generically and rarely need customization.

#### Step 9: Verify

Start a new Claude Code session in the target project. Samantha should:
- Greet the user in first person ("I am Samantha...")
- Reference memory (or acknowledge first session)
- Route requests through the Color Gate
- Dispatch Monk for implementation tasks

---

## Post-Installation Notes

### What the user will see

**Mode A (Git Repo):**
- `CLAUDE.md` in the project root (visible)
- `.claude/` directory (hidden dotfile — invisible in normal `ls`, visible in `ls -a`)
- `.samantha/` directory (hidden dotfile — invisible in normal `ls`)

**Mode B (Hidden/User-Level):**
- `CLAUDE.md` in the project root (visible — unavoidable)
- `.samantha/` in the project root (hidden dotfile)
- Everything else is in `~/.claude/` (user's home directory, hidden)

### Gitignore recommendations (Mode A only)

If the project uses git, consider adding to `.gitignore`:
```
# Samantha working files (don't commit session-specific state)
.samantha/memory/
.samantha/plans/
.samantha/scratch/

# Keep settings.local.json out of git (contains local hook paths)
.claude/settings.local.json
```

DO commit:
```
# These define the framework and should be version-controlled
CLAUDE.md
.claude/agents/
.claude/skills/
```

### Memory system

The `SessionStart` hook injects `.samantha/memory/MEMORY.md` into Samantha's context at the beginning of every session. The `PostCompact` hook re-injects identity and memory summary after context compaction. Samantha is instructed to update memory before session end, but this is voluntary — there is no mechanical enforcement. Important decisions should be noted in memory during the session, not deferred to the end.

### Hook dependencies

The hooks require `python3` to be available on the system PATH. They use `python3 -c` with `json.dumps()` for safe JSON escaping of memory content. If `python3` is not available, the hooks will fail silently and memory injection will not work.

### Agent frontmatter fields

Each agent `.md` file uses YAML frontmatter with these fields:
- `name` — Agent identifier (used for dispatch)
- `description` — When to dispatch this agent (used for intent matching)
- `tools` — Comma-separated tool allowlist
- `model` — Model tier (`sonnet`, `haiku`, `opus`)
- `memory` — Memory scope (`project` for cross-session persistence) — optional
- `hooks` — Per-agent hook definitions — optional (only Monk uses this)

### Skill file naming

Skills MUST be named `SKILL.md` (uppercase, exact match). Claude Code auto-discovers files at `.claude/skills/{name}/SKILL.md`. Other filenames (e.g., `prompt.md`, `skill.md`) will NOT be discovered.

### Version history

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-03-29 | Initial release. 6 agents, 13 skills, hooks, memory system. Validated through 23 skeptic agents across 3 review rounds. |
