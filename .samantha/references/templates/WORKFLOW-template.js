/**
 * WORKFLOW TEMPLATE — Samantha Prime canonical form
 *
 * Workflows are for DETERMINISTIC MANY-AGENT ORCHESTRATION at scale.
 * Use a SKILL instead for protocols Samantha follows interactively.
 * Use a workflow for fan-outs: adversarial review, multi-zone scans, parallel analysis waves.
 *
 * Constraints (enforced by Claude Code's workflow runtime):
 *   - No mid-run human input — the entire run is unattended once started.
 *   - ≤16 agents running concurrently at any time.
 *   - ≤1000 total agent invocations per workflow run.
 *
 * File location: .claude/workflows/<name>.js
 * The filename (without .js) is the workflow's invocation name.
 *
 * BRIDGE: A SKILL may launch a workflow — use that pattern when you want
 * interactive setup (Samantha reviews, confirms scope) followed by a
 * deterministic fan-out (the workflow does the parallel work).
 */

// ─── META (required, pure literal — no computed values) ──────────────────────
//
// `meta` is read by Claude Code at index time to populate the workflow list.
// It must be a pure object literal — no function calls, no template literals,
// no expressions. Claude Code reads it statically without executing the module.
//
export const meta = {
  // name: The workflow's display name. Keep it short and self-documenting.
  name: "workflow-name",

  // description: When Claude Code auto-selects this workflow, it matches against
  // this string. Write it as "Use when [situation]" so intent is clear.
  description: "Use when [describe the situation that calls for this workflow].",

  // whenToUse: Longer guidance for the human or Samantha on when this workflow
  // is the right tool. Not used for auto-selection — this is human-facing context.
  whenToUse: [
    "Situation A",
    "Situation B — but not C (use the X skill for C instead)",
  ],

  // phases: Shown in the UI as the workflow progresses. Each phase displays
  // while its block of agents runs. Pure literals only.
  phases: [
    { title: "Phase 1 — <name>", detail: "<what happens in this phase>" },
    { title: "Phase 2 — <name>", detail: "<what happens in this phase>" },
    { title: "Phase 3 — Synthesis", detail: "Combine findings into a final report." },
  ],
};

// ─── BODY (the orchestration logic) ──────────────────────────────────────────
//
// The body is executed by the workflow runtime. Available primitives:
//
//   phase(title)
//     Marks the start of a logical phase (matches a meta.phases entry).
//     Pure bookkeeping — no agent runs here.
//
//   agent(prompt, options)
//     Runs a single agent with the given prompt. Returns the agent's output.
//     options:
//       label    — display name shown in the UI (string)
//       schema   — expected output shape (object schema for structured output)
//       model    — override the model (e.g. "claude-sonnet-4-6")
//       effort   — "low" | "normal" | "high"
//
//   parallel(agentCalls)
//     Runs multiple agent() calls concurrently. Pass an array of agent() calls.
//     Returns an array of results in the same order as the input.
//     Respects the ≤16 concurrent limit — batch if you have more.
//
//   pipeline(stages)
//     Runs stages sequentially, passing each stage's output as input to the next.
//     Each stage is an agent() call or a parallel() call.
//
//   log(message)
//     Emits a message to the workflow log (visible in the UI). Use for progress
//     updates and intermediate findings.
//
//   workflow(name, args)
//     Runs a nested workflow. Use for reusable sub-orchestrations.

export default async function run({ files, focus, scope } = {}) {
  // ── Phase 1: parallel investigation fan-out ───────────────────────────────

  phase("Phase 1 — <name>");

  // Fan out N independent analyses in parallel.
  // Each agent gets a distinct angle or zone — same inputs, different lens.
  const [resultA, resultB, resultC] = await parallel([
    agent(
      `
      Analyze [zone A / angle A] of the provided scope.

      Scope: ${scope ?? "the full codebase"}
      Focus: ${focus ?? "none specified"}

      Report:
      - Findings (specific, with file:line references)
      - Severity (HIGH / MED / LOW for each finding)
      - Recommended action
      `,
      { label: "Analysis — Zone A", model: "claude-sonnet-4-6", effort: "normal" }
    ),

    agent(
      `
      Analyze [zone B / angle B] of the provided scope.
      [Same structure as above — adapt the prompt to the zone's concerns]
      `,
      { label: "Analysis — Zone B", model: "claude-sonnet-4-6", effort: "normal" }
    ),

    agent(
      `
      Analyze [zone C / angle C] of the provided scope.
      [Same structure as above]
      `,
      { label: "Analysis — Zone C", model: "claude-sonnet-4-6", effort: "normal" }
    ),
  ]);

  log(`Phase 1 complete. Findings: A=${resultA.length} chars, B=${resultB.length} chars, C=${resultC.length} chars.`);

  // ── Phase 2: cross-verification (optional) ────────────────────────────────
  //
  // Adversarial pattern: each zone's findings are independently verified by
  // a second agent. Remove this phase if verification is not needed.

  phase("Phase 2 — Cross-Verification");

  const [verifiedA, verifiedB] = await parallel([
    agent(
      `
      You are a skeptical reviewer. The following findings were produced by a first-pass analysis.
      Your job is to challenge them: find what was missed, what is overclaimed, or what is wrong.

      Original findings:
      ${resultA}

      Report:
      - Confirmed findings (agree with the original)
      - Challenged findings (disagree — explain why)
      - Additional findings the first pass missed
      `,
      { label: "Verification — Zone A", model: "claude-sonnet-4-6", effort: "high" }
    ),

    agent(
      `
      [Same adversarial prompt for Zone B findings]
      Original findings: ${resultB}
      `,
      { label: "Verification — Zone B", model: "claude-sonnet-4-6", effort: "high" }
    ),
  ]);

  // ── Phase 3: synthesis ────────────────────────────────────────────────────

  phase("Phase 3 — Synthesis");

  const synthesis = await agent(
    `
    You are the synthesis agent. Your job is to produce a single, authoritative report
    from the parallel analyses and verification passes below.

    Rules:
    - Include only findings confirmed by at least one verifier, OR findings unique enough
      to warrant flagging (explain why).
    - Deduplicate — if multiple zones found the same issue, list it once.
    - Rank by severity (HIGH first).
    - End with a recommended action list, ordered by priority.

    Zone A analysis: ${resultA}
    Zone B analysis: ${resultB}
    Zone C analysis: ${resultC}
    Zone A verified: ${verifiedA}
    Zone B verified: ${verifiedB}
    `,
    {
      label: "Synthesis",
      model: "claude-sonnet-4-6",
      effort: "high",
      schema: {
        // Optional: define a structured output schema so the caller
        // can parse the result programmatically.
        // findings: [{ severity, description, file, line, action }],
        // summary: string,
      },
    }
  );

  log("Synthesis complete.");

  // Return value is surfaced to Samantha (or the invoking skill) as the workflow result.
  return synthesis;
}
