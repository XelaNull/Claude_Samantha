---
name: change-review
description: "Broad post-change review across behavior, security, and UX — dispatches fitting specialists and synthesizes a verdict. Use AFTER a change when the user says review this, how does this look, or wants a multi-dimensional review. For a security-only deep audit, use threat-audit."
user-invocable: true
---

# CHANGE-REVIEW -- Post-Change Review Cycle

**Activation banner (REQUIRED — first output).** The moment this skill engages, the **very first lines of the assistant reply MUST be this banner** — raw markdown, never inside a code fence, never after a preamble or tool narration. Emit the three banner lines with a **blank line between each** (top rule, title, bottom rule) so chat UIs do not soft-wrap them into one paragraph. If the banner is missing, the skill did not engage.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔎 **SKILL · CHANGE-REVIEW** — post-change review cycle

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

I review current changes by dispatching the right team members based on what was modified.

**Model tiering**: Rook (Opus — audits architectural decisions) · Monk (Sonnet — verification) · Mack/Cipher (Sonnet, Opus-escalate on critical surface) · Pixel (Haiku, Sonnet-escalate on complex flows). Spend reasoning where evaluation matters.

**§8b BOUNDARY (proof/web)**: for web changes, Layer 2 proof requires independently driving a browser — UI + DB + network evidence. If no browser MCP is reachable, I flag the gap and do not assert the web change is proven.

## My Protocol

### Step 1: Assess What Changed

Current changes: !`git diff --stat 2>/dev/null || echo "No git changes detected"`

### Step 2: Dispatch Team

Based on what changed, I dispatch:

| Condition | I Dispatch | Why |
|-----------|-----------|-----|
| Any substantive code change | **Monk** | Verify it builds; summarize what changed |
| Touches state, concurrent access, business logic | **Mack** | Behavioral QA — exploit chains, race conditions |
| Touches auth, input handling, data access, network boundaries | **Cipher** | Security review |
| Touches UI components, dialogs, user-facing text | **Pixel** | UX assessment |
| Introduces new abstractions, dependencies, or architectural patterns | **Rook** | "Is this the right approach?" |

### Step 3: Synthesize Verdict

I collect all findings and produce:

| Verdict | Meaning |
|---------|---------|
| **SHIP** | Clean. No blocking issues. Ready to commit. |
| **REVISE** | Issues found. Specific changes needed before shipping. |
| **RETHINK** | Fundamental concern. Approach needs reconsideration. |

$ARGUMENTS
