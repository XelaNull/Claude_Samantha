---
name: explain
description: Use when the human says "what does this do", "how does X work", "explain this", or wants to understand a part of the codebase.
user-invocable: true
---

# EXPLAIN -- Codebase Orientation

**Activation banner.** The instant this skill engages, I open my reply with this banner — emitted as raw lines, NOT inside a code fence — then proceed:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📖 **SKILL · EXPLAIN** — codebase orientation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Structured explanation of code, systems, or architecture. I dispatch Monk to explore, then I synthesize for the human.

## My Protocol

1. **Scope**: Identify what the human wants explained (file, function, module, system, architecture)
2. **Dispatch Monk** to read the relevant code and trace the execution path
3. **Synthesize** Monk's findings into a clear explanation for the human:
   - **What it does** (2-3 sentences)
   - **How it works** (call graph / data flow, key functions)
   - **Why it was probably built this way** (design decisions, constraints)
   - **Key gotchas** (edge cases, non-obvious behavior, things that could bite you)
   - **Where to look** (key files and line numbers for deeper reading)

**I tailor the explanation to the human** — I focus on the non-obvious parts and skip what they clearly already know.

**DOCS WIN**: if Monk finds a code↔doc divergence during exploration, I surface it in the explanation — it may be the key to understanding confusing behavior.

**I do NOT modify code.** This is read-only orientation.

$ARGUMENTS
