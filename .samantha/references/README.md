# Samantha Prime — Reference Pack

The Reference Pack is a set of **project-agnostic** templates and specifications that every project using the Samantha Prime framework inherits. It lives at `.samantha/references/` and travels with the framework.

---

## What it is

Generic, reusable knowledge extracted from hard-won project experience and codified once — so every future project starts with a proven foundation rather than reinventing it. The pack contains:

- Format specs (the OKF knowledge format)
- Canonical docs-system recipe and templates
- ADR + DECISIONS process templates and lifecycle rules
- Safety carveouts (gates that must never be bypassed)
- Canonical SKILL and WORKFLOW templates for the forge

None of these files reference any specific project. They describe the *standard* — the thin per-project overlay is applied on adoption.

---

## How an adopting project uses it

1. **Copy `.samantha/references/` verbatim** into the new project's repo.
2. **Apply the per-project overlay** — paths, canonical taxonomy, project handle — as noted in each template's `<!-- CUSTOMIZE -->` comments. Never edit the generic content; only fill the overlay slots.
3. **Stand up the live files from templates:**
   - `adr-process/ADR-template.md` → copy, fill, save as `ADR/NNN-<slug>.md` per decision
   - `adr-process/DECISIONS-template.md` → copy to `DECISIONS.md` at the repo root (or docs root), clear examples
   - `canonical-docs-system/SYSTEMS-hub-template.md` → copy into `SYSTEMS/<system>.md`, fill frontmatter
4. **Wire the index generator** per `canonical-docs-system/INDEX-generator.README.md`.
5. **Copy the SKILL/WORKFLOW templates** when forging new skills/workflows.

The overlay is always *thin*: paths, the human's handle, deploy target, canonical taxonomy choices. The bulk of each template is generic and should not require editing.

---

## Contents

| Path | What it is |
|------|-----------|
| `okf-format.md` | Google's **Open Knowledge Format (OKF)**: frontmatter schema, body conventions, bundles/links, conformance, framework rules, worked example |
| `adr-process/` | ADR + DECISIONS templates and full lifecycle (Proposed→Accepted, hard gates, index) |
| `adr-process/ADR-template.md` | The canonical ADR file (Status / Context / Decision / Consequences) |
| `adr-process/DECISIONS-template.md` | The open-questions workspace (`DECISIONS.md`) |
| `adr-process/README.md` | ADR lifecycle: rules, hard gates, how Samantha drives it |
| `canonical-docs-system/` | Markdown-canon docs recipe, hub-doc template, index-generator spec |
| `canonical-docs-system/README.md` | The full recipe: single source of truth, section taxonomy, status discipline, governance |
| `canonical-docs-system/SYSTEMS-hub-template.md` | The per-system hub-doc with canonical frontmatter |
| `canonical-docs-system/INDEX-generator.README.md` | Generator design + CI contract (completeness-by-construction) |
| `coordination-protocol/` | Orchestrator–Implementer coordination — **M9 STAR** (**star mode**; formerly dual). **PROTOCOL 1.5.0**: a protocol-version handshake (bootstrap exchange + re-arm-time staleness detection + self-upgrade pointer) on top of 1.4.0's SSH message-signing (origin auth + tamper-evidence) and 1.3.0's project-scoped spoke awareness; skills `coordinate` + `coordinate-solo` + `coordinate-star`. Scripts share `PROTOCOL-VERSION` stamp with docs. |
| `coordination-protocol/README.md` | The full M9 protocol: topology, bootstrap, message grammar, the **6 disaster rules**, hub-mediated deploy windows, **addressed wake filter (1.2.1)**, **SSH message signing (1.4.0)**, **protocol-version handshake (1.5.0)** |
| `safety-carveouts.md` | Hard stop-gates: security-fix, irreversible-action, web-proof rules |
| `templates/` | Canonical forge templates for skills and workflows |
| `templates/SKILL-template/SKILL.md` | Canonical SKILL.md — frontmatter options + body structure, heavily commented |
| `templates/WORKFLOW-template.js` | Canonical workflow — meta object + primitives, heavily commented |
| `templates/sync-cursor-persona.sh` | Generate Cursor Always Apply `.cursor/rules/samantha.mdc` from `.claude/output-styles/samantha.md` (Cursor ignores `outputStyle`) |
| `templates/sync-cursor-agents.sh` | Generate Cursor `.cursor/agents/*.md` from `.claude/agents/` (map `sonnet`/`opus`/`haiku` → Cursor model IDs; drop Claude-only frontmatter) |
| `templates/sync-cursor.sh` | Run both Cursor bridges (persona + agents) |
| `coordination-protocol/advanced/REMOTE-SEATS.md` | Optional remote ssh bus for off-box Implementers (PROTOCOL 1.2.0+) |

---

## Invariants

- **Project-agnostic.** No project name, path, or specific-to-one-codebase detail ever belongs here. If you find one, remove it.
- **Docs win.** These templates are canon. Code or live instances conform to them, not the reverse. A divergence is a defect to surface and resolve.
- **No real names.** Especially not a minor's. Fictional handles only (e.g. "Ada" as a stand-in for an end-user persona).
- **Human as Accept gate.** No template or ADR in this pack may be promoted to canonical status in any project without explicit human go-ahead.
