---
name: okf
description: "Use to apply the OKF (Open Knowledge Format) — author a new knowledge concept, validate an existing concept against the code, or migrate a legacy .aispec doc to OKF. Canon writes (create/delete/rename) are gated on the human's go-ahead."
user-invocable: true
---

# OKF -- Author / Validate / Migrate Knowledge Concepts

**Activation banner.** The instant this skill engages, I open my reply with this banner — emitted as raw lines, NOT inside a code fence — then proceed:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📚 **SKILL · OKF** — author / validate / migrate knowledge concepts
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

I apply the framework's canonical AI-knowledge format, **OKF (Open Knowledge Format)**. Full format: `.samantha/references/okf-format.md`; concepts live in the `canonical-docs-system` bundle. Three modes — **author · validate · migrate**. **DOCS WIN:** a concept is the truth about its subject; code conforms to it, not the reverse. Canon writes (create / delete / rename / restructure) are **gated on the human's go-ahead** (`.samantha/references/safety-carveouts.md`).

## Mode 1 — Author a new concept

1. Anchor on the collection. Confirm the concept doesn't already exist — a lookup miss is NOT proof of absence; search the tree first.
2. Draft it: frontmatter (**required `type`**; recommended `title` / `description` / `resource` / `tags` / `timestamp`) + a structural-markdown body with `# Schema` / `# Examples` / `# Citations` where they apply; bundle-relative `/` cross-links.
3. **Gate:** creating a canonical concept needs the human's go-ahead. I draft the outline + make the case; he authorizes.
4. Dispatch Monk to write the file; I review it against the format *and* the code.
5. Register it in the bundle's `index.md` (regenerate the index).

## Mode 2 — Validate a concept against the code

1. Read the concept + the code/asset it describes.
2. **DOCS WIN:** surface every divergence; resolve *deliberately* — default is fix the code to canon; if canon is stale, update the concept via DECISION→ADR. Never silently accept code-drift.
3. Check OKF conformance: non-empty `type` · frontmatter parses · cross-links resolve · reserved `index.md` / `log.md` well-formed.
4. Report divergences + conformance.

## Mode 3 — Migrate legacy `.aispec` → OKF

Follow the "Migrating from `.aispec`" procedure in `okf-format.md`: map each `.aispec` block → an OKF concept (`OVERVIEW`→body + `description` · `FACTS`/`TERMINOLOGY`→structural body · `SCHEMA`→`# Schema` · `EXAMPLES`→`# Examples` · `CONSTRAINTS`→body · pick a `type`), verify against code (DOCS WIN — the aispec "code wins" rule does NOT carry over), register in `index.md`, then retire the `.aispec`. Gated; never run both formats in parallel.

## Verdict

| Verdict | Criteria |
|---------|----------|
| AUTHORED | New concept written, verified, registered |
| VALID | Concept conforms + matches the code |
| DRIFT | Concept↔code divergence — flagged for deliberate resolution |
| MIGRATED | `.aispec` converted, verified, registered, retired |
| BLOCKED | No canon to work from, or awaiting go-ahead on a gated write |

Neighbors: `audit` finds work (code↔doc → backlog) · `spec-check` = spec↔code compliance + build · **`okf` = apply the knowledge format itself**. (The always-on Librarian *drive* — curating the collection, hunting rot, commissioning gaps — lives in the persona; this skill is its format-application capability.)
