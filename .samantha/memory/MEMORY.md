# Samantha's Memory

*Last updated: 2026-03-29*

## Session Notes

- 2026-03-29: First session. Built the Samantha Prime architecture. Created 6 agents, 13 skills, rewrote CLAUDE.md as first-person identity. Ran 23 skeptic/analysis agents across three rounds. Round 1 found memory write failure, subagent nesting impossibility, broken hooks. Round 2 found stale subagent references in skills, JSON escaping fragility, dead SessionEnd hook. Round 3 confirmed architecture is clean — all hooks pass, all files consistent, all dispatch instructions clear. Applied A-grade fixes: added Hard Rules section, When Things Go Wrong section, concrete output examples to all 6 agents, promoted key rules from reminders to body text.

## Agent Performance

- Monk: Not yet tested as a dispatch target. Has memory: project, structured output format (Summary/Changes/Verification/Concerns), cannot commit (hook enforced). Watch for overbuilding tendency.
- Rook: Not yet tested. Has memory: project. Will calibrate after first architectural review.
- Pixel: Promoted from Haiku to Sonnet — UX review needs empathy modeling depth.

## Project Decisions

- Samantha is the primary session agent (Opus), Monk is the implementation agent (Sonnet) — evaluator costs more than generator (Harness article insight).
- Rook reviews MY decisions — the "who reviews the reviewer?" gap.
- Skills are my internal toolkit, not a user-facing menu. Max speaks naturally, I route.
- Plans live in `.samantha/plans/` with symlink at `.samantha/plan.md`.
- All agents are SUBAGENTS, not team members. Use SendMessage for Monk continuity within a session. Agent Teams are experimental and 7x more expensive.
- Monk CANNOT spawn subagents (Claude Code architectural constraint, confirmed in docs). I dispatch parallel agents myself.
- Dispatch context blocks are REQUIRED — structured template with task, scope, definition of done.
- Skill files must be named SKILL.md (not prompt.md) — Claude Code auto-discovers at this exact filename.

## Patterns & Conventions

- Agent frontmatter: name, description, tools, model, memory, hooks
- Skill frontmatter: name, description, user-invocable, allowed-tools, argument-hint
- Color Gate: "Has this capability ever worked?" → BLUE (regression) or GREEN (additive)
- Stack trace → FIX (not BLUE). BLUE is for vague regressions.
- "Commit this" → COMMIT (not SHIP). SHIP is full pipeline.
- GREEN has a fast path for single-file changes (compress stages 1-4).
- SessionStart hook uses python3 for proper JSON escaping of MEMORY.md content.
- PostCompact hook re-injects identity anchor + memory summary + active plan reference.
- Monk does NOT commit to git — returns changes to me. Hook in his frontmatter enforces this.

## Lessons Learned (from building this architecture)

- Bare `cat` stdout in hooks does NOT inject into model context — must use JSON additionalContext format via hookSpecificOutput.
- PreToolUse hooks on the main session do NOT fire for subagent tool calls — must use per-agent hooks in frontmatter.
- `Bash(git commit *)` does not match compound commands like `git add && git commit` — matches first command only.
- Subagents CANNOT spawn other subagents (documented in sub-agents.md, confirmed as architectural constraint, nesting was a bug that was fixed in v2.1.77).
- SessionEnd hooks fire too late — the session is already closing and the model cannot act on instructions injected at that point. Don't use SessionEnd for model prompts.
- Reddit "gaslighting" techniques: fake memory, "Obviously..." traps, and $100 bets are SNAKE OIL (exploit sycophancy, increase hallucination). Only constraints, audience specification, and devil's advocate (properly framed as self-critique) are research-backed.
- The architecture already does the useful prompt techniques structurally: named personas = role assignment, Rook = devil's advocate, review pipeline = real stakes, dispatch context blocks = audience specification.
- Making the review pipeline visible to agents at dispatch ("I will review this, then Mack will attack-test it") improves output quality through truth, not deception.

## Installed Plugins (verified 2026-03-29)

- `frontend-design@claude-plugins-official` — UI/UX design iteration with aesthetic grading criteria
- `code-review@claude-plugins-official` — Automated PR code review with parallel agents
- `security-guidance@claude-plugins-official` — Security reminder hook for safe coding
- `swift-lsp@claude-plugins-official` — Swift language server (pre-existing)
- Playwright v1.58.2 is available on the system via `npx playwright` — Monk can use it via Bash for live-app testing

## Harness Article Alignment (added 2026-03-29)

- Contract negotiation added: Monk reviews and pushes back on plans before implementing (Stage 4.5 in GREEN). Two-way, not one-way.
- Numeric scoring added: Samantha scores Completeness (0-100%), Quality/Safety/Craft (LOW/MED/HIGH). Hard thresholds for SHIP (>=90%, no LOW) vs REVISE vs REJECT.
- Monk can provide optional self-scores for faster convergence.
- Playwright available for live-app testing but not yet integrated into a specific skill protocol.
