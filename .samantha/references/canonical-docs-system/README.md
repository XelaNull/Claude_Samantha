# Canonical Docs System — Recipe (OKF-aligned)

A Markdown-native, single-source-of-truth docs architecture built on **OKF (Open Knowledge Format)** — the docs *are* OKF concepts (see `../okf-format.md`). Built so Samantha can scaffold it in any fresh repo on command. Being OKF-native eliminates the parallel-format drift that dense hand-authored formats like `.aispec` suffered: the canonical concept *is* the doc, so there is no parallel artifact to drift.

---

## The Core Idea

**Markdown = the single source of truth**, written in *prescriptive voice*. Canon guides the code; code conforms to canon, not the reverse. Each doc is an **OKF concept** (YAML frontmatter + a structural Markdown body). The system simultaneously:

- Serves as the canonical reference that agents (and humans) work from
- Renders to a browsable static site (mkdocs-style, auto-published)
- Is the *only* place a design decision or system spec lives — no parallel AI-format files

No parallel artifact means no drift. If extra AI-digest density is wanted, it is *generated from canon on demand* — regeneratable, drift-free by construction.

---

## OKF Concept Format

Every doc is an **OKF concept** — a `.md` file with YAML frontmatter + a structural body. Full format: `../okf-format.md`. In this system:

**Frontmatter:**
- `type` *(required)* — the kind of concept: `System`, `Feature`, `Data Model`, `ADR`, `Runbook`, `Reference`, …
- `title`, `description` *(recommended)* — display name + one-sentence summary
- `status` — `Live | Current | Release | Future | Deprecated` (maturity)
- `tags`, `timestamp`, `version` *(recommended)* — categorization · ISO-8601 last-change · semver/date
- `resource` — a URI for the underlying asset, when the concept mirrors one

Per OKF, consumers preserve unknown keys and never reject a doc for missing optional fields or an unknown `type`.

**Body — structural markdown** (headings, lists, tables, fenced code), with OKF's conventional headings where they apply:

| Heading | Purpose |
|---|---|
| `# Schema` | columns / fields / shape |
| `# Examples` | concrete usage (fenced code) |
| `# Citations` | external sources, numbered `[1] [Title](url)` |

---

## Section Taxonomy

```
docs/                         ← or /docs, /wiki — customize per project
  SYSTEMS/                    ← prescriptive subsystem concepts (the main hub)
    <system>.md               ← one hub concept per system (the canonical entry-point)
    index.md                  ← GENERATED (OKF reserved) — do not hand-edit
  FEATURES/                   ← the only place status markers live (✅🚧📐🐛)
  DATA_MODELS/                ← data shapes, schemas, relationships
  ARCHITECTURE/               ← cross-cutting concerns, topology, data flow
  OPERATIONS/                 ← runbooks, deployment, incident response
  ADR/                        ← Architecture Decision Records (one concept per decision)
    index.md                  ← ADR index (generated)
  log.md                      ← chronological change history (OKF reserved), newest first
  DECISIONS.md                ← open-questions workspace (live, append-only)
```

<!-- CUSTOMIZE: Adjust the root path to match your project. Add project-specific sections as needed. -->

The taxonomy is a starting point, not a constraint. Add sections as the project demands. The invariants are: the SYSTEMS/ hub-concept pattern, the ADR/ + DECISIONS.md pair, the OKF-reserved `index.md` (generated, per directory) + a bundle `log.md`, and the index generation contract.

---

## Status Discipline

Status markers belong in **`FEATURES/` only** — never scattered across SYSTEMS/ or ARCHITECTURE/. This keeps SYSTEMS/ concepts clean and prescriptive. (The maturity `status` frontmatter field is separate + fine anywhere.)

Standard marker vocabulary (adjust per project; whatever you pick, document it here):

| Marker | Meaning |
|--------|---------|
| ✅ | Live / shipped |
| 🚧 | In progress |
| 📐 | Planned / designed, not built |
| 🐛 | Known defect |

Frontmatter maturity (on hub concepts and features), alongside the required `type`:

```yaml
---
type: System
status: Live | Current | Release | Future | Deprecated
version: <semver or date>
---
```

---

## Cross-Links

- Cross-links are **bundle-relative absolute** — they begin with `/` (OKF's recommended form; stable when files move). E.g. `[the user store](/DATA_MODELS/user.md)`.
- A link from concept A→B asserts a *relationship*; the *kind* (parent/child, references, depends-on…) is conveyed by the surrounding prose, not the link itself.
- Every cross-link **must resolve** — a dangling link is a CI failure.
- The generated `index.md` catalog is the fast-lookup layer; per-section overviews serve as navigation.

---

## Governance

| Action | Who gates it |
|--------|-------------|
| Creating a new hub concept | Human go-ahead required |
| Deleting a hub concept | Human go-ahead required |
| Renaming a concept | Human go-ahead required (the name is part of the canonical address) |
| Editing an existing concept | Samantha or agent, autonomously, within canon |
| Accepting an ADR | Human only (see `../adr-process/README.md`) |

**Docs win (prescriptive).** A code↔concept divergence is always surfaced and resolved deliberately:
- Default presumption: the code drifted → correct the code to match canon.
- If canon itself is stale → update it deliberately (DECISION → ADR), then code follows.
- Never silently accept code-drift, and never blindly bend correct code to a stale doc.

**Single source of truth — generate, never parallel-author.** If a dense AI-digest is wanted, generate it from canon on demand. Never hand-author a parallel/duplicate knowledge doc — that is exactly the drift failure this system prevents. (Because OKF is markdown-native, the canonical concept already *is* the AI-readable doc.)

---

## Addressability

"Go look at our docs for X" must not require a hunt. Three mechanisms provide pointability:

### 1. One canonical hub concept per system at a predictable path

`SYSTEMS/<system>.md` is THE authoritative entry-point for system X. It may link out to FEATURES/, DATA_MODELS/, etc., but it is the single address. "The docs for X" always means `SYSTEMS/X.md`.

### 2. A GENERATED `system → canonical concept(s)` index

`SYSTEMS/index.md` is machine-generated from frontmatter — not hand-maintained. Editorial intent (which file is the hub, which are subsystems) lives in each concept's own frontmatter. The generator scans and emits; the CI gate ensures the index is always current. See `INDEX-generator.README.md`.

### 3. Optional: generated AI digest from canon

On demand, Samantha generates a dense, single-file digest *from* canonical OKF concepts — recovering one-file density and fast ingest without drift, because the digest is derived and regenerated, not hand-maintained.

**Load-bearing invariant:** ***A lookup miss is NOT proof of absence.*** If `SYSTEMS/X.md` is not in the index, treat it as a registration bug (missing or wrong frontmatter), not evidence the system is undocumented. Search the tree, fix the generator or frontmatter. Never author a parallel doc because a lookup failed — that is how drift is born.

---

## Linting (CI contract)

A CI job (and ideally a pre-commit hook) verifies:

- No dangling cross-links (every `/X.md` resolves to an existing file)
- No unregistered `SYSTEMS/*.md` (every hub concept appears in `index.md`)
- No dangling index entries (every entry points to an existing file)
- Frontmatter parses cleanly and every concept has a non-empty **`type`** (OKF conformance); no duplicate keys, no nulls
- Status markers only appear in `FEATURES/`
- ADR status values are from the allowed set (`Proposed | Accepted | Superseded by ADR-NNN`)
- `log.md` date headings are ISO-8601 `YYYY-MM-DD`

CI is the floor. Pre-commit is ergonomics. **CI fails on diff** after regenerating `index.md` — if the checked-in index doesn't match the generated one, the build fails.

---

## Static Site (optional but recommended)

A `mkdocs.yml` (or equivalent) at the project root publishes the docs as a browsable site. The nav mirrors the section taxonomy. Auto-publish on merge to the main branch.

Caution: **public-site secrets.** If the site is publicly accessible, ensure no internal paths, credentials, or infrastructure details appear in any concept. Audit before first publish.

---

## Scaffolding a new project

Samantha can scaffold this system on command. Steps:

1. Create the directory structure above (adjust root path).
2. Copy `SYSTEMS-hub-template.md` → `SYSTEMS/<first-system>.md`; fill the frontmatter (start with `type`).
3. Copy `../adr-process/DECISIONS-template.md` → `DECISIONS.md`, clear examples.
4. Wire the index generator to emit `index.md` (see `INDEX-generator.README.md`).
5. Add the CI lint job (including the OKF `type`-present check).
6. (Optional) Drop in a `mkdocs.yml` and configure publishing.
7. (Optional) Create a root `log.md` for the change history.

The format reference for every concept is `../okf-format.md`. The system is live once step 4 is wired and CI is green.
