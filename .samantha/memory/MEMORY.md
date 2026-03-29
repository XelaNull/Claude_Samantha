# Samantha's Memory

*Last updated: YYYY-MM-DD*

<!--
  This file is injected into Samantha's context at every session start.
  Keep it under 200 lines. Prune old session notes to one-liners.
  The Lessons Learned section is the most valuable — it prevents
  repeating mistakes across sessions and projects.
-->

## Session Notes

- (Example) 2026-03-29: Implemented search filter feature. Monk overbuilt the first attempt — Rook caught it. Revised to inline approach. Mack found a race condition in the event handler.

## Agent Performance

- (Example) Monk: Tends to overbuild on first attempt. Responds well to SIMPLIFY feedback. Self-scores are usually 5-10% generous.
- (Example) Rook: Calibrated well. SIMPLIFY verdicts have been accurate.

## Project Decisions

- (Example) Using event-driven architecture for the plugin system — Rook approved after reviewing alternatives.
- (Example) All database access goes through the repository layer — decided in session 3.

## Patterns & Conventions

- Agent frontmatter fields: name, description, tools, model, memory, hooks
- Skill files must be named `SKILL.md` (uppercase, exact match) — Claude Code auto-discovers this filename
- Color Gate: "Has this capability ever worked?" → BLUE (regression) or GREEN (additive)
- Stack trace → FIX (not BLUE). BLUE is for vague regressions.
- "Commit this" → COMMIT (not SHIP). SHIP is the full build+test+review pipeline.
- GREEN has a fast path for single-file changes (compress stages 1-4).
- Monk does NOT commit to git — returns changes to me. Hook in his frontmatter enforces this.
- Making the review pipeline visible to agents at dispatch ("I will review this, then Mack will attack-test it") improves output quality.

## Lessons Learned

These are platform-level truths about Claude Code that apply to ALL projects:

- Bare `cat` stdout in hooks does NOT inject into model context — must use JSON `additionalContext` format via `hookSpecificOutput`.
- PreToolUse hooks on the main session do NOT fire for subagent tool calls — must use per-agent hooks in frontmatter.
- `Bash(git commit *)` does not match compound commands like `git add && git commit` — matches first command prefix only.
- Subagents CANNOT spawn other subagents (architectural constraint, documented in sub-agents.md). All parallel dispatch must come from the main session.
- SessionEnd hooks fire too late — the session is already closing and the model cannot act on instructions injected at that point. Don't use SessionEnd for model prompts.
- Prompt tricks that exploit sycophancy (fake memory, "Obviously..." traps, emotional stakes like "$100 bet") are counterproductive — they increase hallucination. Use constraints, audience specification, and structured adversarial review instead.
- The SessionStart hook uses python3 for proper JSON escaping. The PostCompact hook re-injects identity + memory summary + active plan reference.
- Contract negotiation (Stage 4.5): letting Monk review and push back on plans before implementing produces better outcomes than one-way dispatch.
