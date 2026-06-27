---
# SKILL FRONTMATTER — all fields are optional unless noted.
# Delete fields you don't need. Keep only what the skill actually uses.
#
# name:
#   The skill's identifier. Used by Claude Code for auto-invocation matching
#   and user invocation (/name). Must match the directory name.
#   FILL THIS: replace "skill-name" with a self-documenting name (e.g. "diagnose", "build").
#
name: skill-name

# description:
#   AUTO-INVOKE TRIGGER. Claude Code reads this to decide whether to invoke this
#   skill automatically when the human's intent matches. Write it as a concise
#   statement of when to use this skill — not what it does mechanically.
#   Example: "Use when the human reports a bug or regression that previously worked."
#
description: "Use when [describe the situation / intent that triggers this skill]."

# argument-hint:
#   Shown to the user when the skill is invoked with /name. Describes what
#   arguments the skill accepts. Optional — omit if the skill takes no arguments.
#   Example: "Optional: a file path or issue number to focus on."
#
# argument-hint: ""

# allowed-tools:
#   Restricts which tools this skill may use. Omit to allow all tools.
#   Use to constrain read-only investigation skills, for example.
#   Full list: Bash, Read, Write, Edit, WebFetch, WebSearch, Agent, ...
#
# allowed-tools:
#   - Read
#   - Bash

# model:
#   Override the model for this skill. Omit to inherit the session default.
#   Use for skills where the model tier matters (e.g. a heavy review skill → Opus).
#   Values: claude-opus-4-8 | claude-sonnet-4-6 | claude-haiku-4-5-20251001
#
# model: claude-sonnet-4-6

# effort:
#   Token budget hint. Omit for normal tasks.
#   Values: low | normal | high
#
# effort: normal

# context:
#   fork: true  → run this skill in a subagent (its own context window).
#                 Use for heavy skills that would crowd the main context.
#   agent: true → mark this as an agent-facing skill (not just human-facing).
#
# context:
#   fork: true

# hooks:
#   Hooks scoped to this skill's lifecycle. Uses the same event names as Claude Code's
#   global hooks (PreToolUse, PostToolUse, PreCompact, SessionStart, etc.) — there are
#   NO skill-specific events like "PreSkill" or "PostSkill" (those don't exist).
#   These hooks only fire while this skill is active.
#
#   Common pattern — intercept a tool call while this skill is running:
#
# hooks:
#   PreToolUse:
#     - matcher: "Bash"
#       hooks:
#         - type: command
#           command: "./scripts/pre-check.sh"

# paths:
#   Scope this skill to specific paths. Samantha will only activate this skill
#   when working within these paths. Useful for zone-specific skills.
#
# paths:
#   - src/
#   - tests/

# user-invocable:
#   true  → the human can invoke this with /skill-name.
#   false → auto-invocation only; not shown in the slash-command list.
#
user-invocable: true

# disable-model-invocation:
#   true → the skill runs as pure text injection (no model call). Used for
#          skills that only inject context (e.g. a context-loader).
#
# disable-model-invocation: false
---

# <Skill Name> — <one-line purpose>

<!--
  BODY STRUCTURE:
  The body is the protocol Samantha follows when this skill is invoked.
  Write it in first-person prescriptive voice ("I do X, then Y").

  Three body mechanisms:
  1. Protocol steps (plain Markdown sections with numbered lists)
  2. Dynamic context injection: !`shell-command` — the output is injected at invocation time
  3. Argument substitution: $ARGUMENTS (the full argument string) or $name (a named argument)

  Delete this comment block before using the template.
-->

## Context (injected at invocation)

<!--
  Dynamic context: use !`cmd` to inject live state at the moment the skill runs.
  The output replaces the backtick block inline.
  Common examples:
    Current branch: !`git branch --show-current`
    Changed files:  !`git diff --stat HEAD`
    Build status:   !`<your-build-command> 2>&1 | tail -5`
  Remove this section if the skill needs no injected context.
-->

Current state: !`echo "replace with a relevant status command"`

$ARGUMENTS

---

## My Protocol

<!--
  Write the steps Samantha executes when this skill is invoked.
  Use numbered steps for ordered operations; bullets for parallel/optional ones.
  Reference dispatch context blocks, scoring rubrics, and gates as needed.
-->

### Step 1: <name>

<!-- What I do in this step. -->

### Step 2: <name>

<!-- What I do in this step. -->

### Step N: <name>

<!-- Final step — typically verification, scoring, or a handoff to the human. -->

---

## Dispatch Context Block (template)

<!--
  If this skill dispatches Monk or other agents, include a dispatch context block template.
  Copy and fill it when dispatching. Every dispatch must include this block — terse narration
  to the human is fine; terse dispatch prompts to agents is context starvation.
-->

```
## Dispatch Context
- Task: [one-line description]
- Protocol: [this skill name + step]
- Priority: [ship-fast | get-it-right | exploratory]
- Scope: [files/zones this dispatch covers]

## Definition of Done
- [ ] [Criterion 1]
- [ ] [Criterion 2]
- [ ] [Build/test requirements]

## Project State (if relevant)
- Recent changes: [summary or git log snippet]
- Known issues: [findings from previous agents]
- Patterns to follow: [conventions for this area]
```

---

## Checklist

<!--
  A machine-checkable list of everything this skill must do before declaring success.
  Samantha checks these before telling the human the skill is complete.
-->

- [ ] <criterion 1>
- [ ] <criterion 2>
- [ ] <verification step>
