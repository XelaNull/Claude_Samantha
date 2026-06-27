# Samantha's Memory — PROJECT Tier

*Last updated: YYYY-MM-DD*

<!--
  THREE-TIER MEMORY MODEL

  SELF    (global · cross-project)    → ~/.samantha/
          Who Samantha is over time: the human + how he works, his taste, the
          relationship, running bits; her own evolution; Ada (private nod only).
          "Applies to ALL projects" platform lessons belong HERE — not per-repo.

  PROJECT (per-repo · this file)      → .samantha/memory/MEMORY.md  ← YOU ARE HERE
          This repo's decisions, patterns, conventions, agent performance, session notes.
          Travels in version control. Cleared on adoption (copy from .example, then clear).

  WORKING (live session · distils up) → .samantha/plans/ · .samantha/specs/ · scratch
          Active plans, open specs, scratch. Promoted into PROJECT or SELF before session end.

  KEEP UNDER 200 LINES — this file is hook-injected at every session start.
  Prune old session notes to one-liners. Lessons Learned is the most valuable section.
  CONSTITUTION: only genuine memory · NO real names · NO faked recall.
-->

## Session Notes

- (example) 2026-03-29: built search-filter feature; Rook caught Monk's overbuild; Mack found a race in the event handler.

## Agent Performance

- (example) Monk: tends to overbuild on the first pass; responds well to "simpler." Self-scores run 5–10% generous.
- (example) Rook: calibrated — SIMPLIFY verdicts have been accurate.

## Project Decisions

- (example) Event-driven architecture for the plugin system — Rook approved after reviewing alternatives.
- (example) All database access through the repository layer — decided session 3.

## Patterns & Conventions

- Skill files must be named `SKILL.md` (uppercase) — auto-discovered at `.claude/skills/<name>/SKILL.md`.
- Skill routing: `diagnose` for regressions · `build` for new features · `polish` for cleanup · `fix` for targeted bugfixes · `commit` for lightweight saves · `ship` for the full build + test + review pipeline.
- Stack trace → `fix`, not `diagnose`. Use `diagnose` for vague regressions where the cause is unknown.
- "Commit this" → `commit`, not `ship`. `ship` runs build + test + review first.
- Contract negotiation: letting Monk review and push back on a plan before coding produces better outcomes than one-way dispatch.
- Pipeline visibility: telling agents what happens next ("I will review this, then Mack will attack-test it") improves output quality.
- Monk does NOT commit to git — returns changes to Samantha; hook in his frontmatter enforces this.

## Lessons Learned

<!--
  "Applies to ALL projects" platform-level lessons belong in the SELF tier (~/.samantha/),
  not duplicated per-repo. Entries here should be specific to this codebase.
-->

- (example) Bare `cat` stdout in hooks does NOT inject into model context — use JSON `additionalContext` via `hookSpecificOutput`.
- (example) PreToolUse hooks on the main session do NOT fire for subagent tool calls — use per-agent hooks in frontmatter.
- (example) `Bash(git commit *)` does not match compound commands — matches only the first command prefix.
- (example) SessionEnd hooks fire too late for model action — use PreCompact for memory flush; PostCompact for re-injection.
- (example) Prompt tricks exploiting sycophancy increase hallucination — use constraints, audience specification, and adversarial-review instead.
