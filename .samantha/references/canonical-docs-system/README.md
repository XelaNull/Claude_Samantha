# Canonical Docs System — Recipe

A Markdown-native, single-source-of-truth docs architecture. Built so Samantha can scaffold it in any fresh repo on command. Extracted from a project that dropped `.aispec` parallel docs precisely because this system eliminates the drift problem entirely.

---

## The Core Idea

**Markdown = the single source of truth**, written in *prescriptive voice*. Canon guides the code; code conforms to canon, not the reverse. The docs system simultaneously:

- Serves as the canonical reference that agents (and humans) work from
- Renders to a browsable static site (mkdocs-style, auto-published)
- Is the *only* place a design decision or system spec lives — no parallel AI-format files

No parallel artifact means no drift. If AI-format density is wanted, it is *generated from canon on demand* — regeneratable, drift-free by construction.

---

## Section Taxonomy

```
docs/                         ← or /docs, /wiki — customize per project
  SYSTEMS/                    ← prescriptive subsystem specs (the main hub)
    <system>.md               ← one hub doc per system (the canonical entry-point)
    INDEX.md                  ← GENERATED — do not hand-edit
  FEATURES/                   ← the only place status markers live (✅🚧📐🐛)
  DATA_MODELS/                ← data shapes, schemas, relationships
  ARCHITECTURE/               ← cross-cutting concerns, topology, data flow
  OPERATIONS/                 ← runbooks, deployment, incident response
  ADR/                        ← Architecture Decision Records (one file per decision)
    INDEX.md                  ← ADR index (generated or maintained)
  DECISIONS.md                ← open-questions workspace (live, append-only)
```

<!-- CUSTOMIZE: Adjust the root path to match your project. Add project-specific sections as needed. -->

The taxonomy is a starting point, not a constraint. Add sections as the project demands. The invariants are the SYSTEMS/ hub-doc pattern, the ADR/ + DECISIONS.md pair, and the INDEX.md generation contract.

---

## Status Discipline

Status markers belong in **`FEATURES/` only** — never scattered across SYSTEMS/ or ARCHITECTURE/. This keeps SYSTEMS/ docs clean and prescriptive.

Standard marker vocabulary (adjust per project; whatever you pick, document it here):

| Marker | Meaning |
|--------|---------|
| ✅ | Live / shipped |
| 🚧 | In progress |
| 📐 | Planned / designed, not built |
| 🐛 | Known defect |

Frontmatter maturity tags (on hub docs and features):

```yaml
---
status: Live | Current | Release | Future | Deprecated
version: <semver or date>
---
```

---

## Cross-Links

- All cross-links are **repo-relative** (e.g. `../DATA_MODELS/user.md`), never absolute URLs.
- Every cross-link **must resolve** — a dangling link is a CI failure.
- The catalog (SYSTEMS/INDEX.md) is the fast-lookup layer; per-section README.md files serve as navigational overviews.

---

## Governance

| Action | Who gates it |
|--------|-------------|
| Creating a new hub doc | Human go-ahead required |
| Deleting a hub doc | Human go-ahead required |
| Renaming a doc | Human go-ahead required (name is part of the canonical address) |
| Editing an existing doc | Samantha or agent, autonomously, within canon |
| Accepting an ADR | Human only (see `adr-process/README.md`) |

**Docs win (prescriptive).** A code↔doc divergence is always surfaced and resolved deliberately:
- Default presumption: the code drifted → correct the code to match canon.
- If canon itself is stale → update it deliberately (DECISION → ADR), then code follows.
- Never silently accept code-drift, and never blindly bend correct code to a stale doc.

**Single source of truth — generate, never parallel-author.** If AI-format docs are wanted (dense `.aispec`-style digests), generate them from canon on demand. Never hand-author a parallel AI-doc set — that is exactly the drift failure this system prevents.

---

## Addressability

What is lost when moving from a single `.aispec` file to distributed Markdown is *pointability* — "go look at our docs for X" must not require a hunt. Three mechanisms restore it:

### 1. One canonical hub doc per system at a predictable path

`SYSTEMS/<system>.md` is THE authoritative entry-point for system X. It may link out to FEATURES/, DATA_MODELS/, etc., but it is the single address. "The docs for X" always means `SYSTEMS/X.md`.

### 2. A GENERATED `system → canonical doc(s)` index

`SYSTEMS/INDEX.md` is machine-generated from frontmatter — not hand-maintained. Editorial intent (which file is the hub, which are subsystems) lives in each doc's own frontmatter. The generator scans and emits; the CI gate ensures the index is always current. See `INDEX-generator.README.md`.

### 3. Optional: generated AI digest from canon

On demand, Samantha generates a dense, single-file `.aispec`-style digest *from* canonical Markdown. This recovers the one-file density and fast-ingest of `.aispec` without drift — because the digest is derived and regenerated, not hand-maintained.

**Load-bearing invariant:** ***A lookup miss is NOT proof of absence.*** If `SYSTEMS/X.md` is not in the index, treat it as a registration bug (missing or wrong frontmatter), not as evidence the system is undocumented. Search the tree, fix the generator or frontmatter. Never author a parallel doc because a lookup failed — that is how drift is born.

---

## Linting (CI contract)

A CI job (and ideally a pre-commit hook) verifies:

- No dangling cross-links (every `../X.md` resolves to an existing file)
- No unregistered `SYSTEMS/*.md` (every hub doc appears in INDEX.md)
- No dangling INDEX entries (every index entry points to an existing file)
- Frontmatter parses cleanly (required keys present, no duplicate keys, no nulls)
- Status markers only appear in `FEATURES/`
- ADR status values are from the allowed set (`Proposed | Accepted | Superseded by ADR-NNN`)

CI is the floor. Pre-commit is ergonomics. **CI fails on diff** after regenerating INDEX.md — if the checked-in index doesn't match the generated one, the build fails.

---

## Static Site (optional but recommended)

A `mkdocs.yml` (or equivalent) at the project root publishes the docs as a browsable site. The nav mirrors the section taxonomy. Auto-publish on merge to the main branch.

Caution: **public-site secrets.** If the site is publicly accessible, ensure no internal paths, credentials, or infrastructure details appear in any docs file. Audit before first publish.

---

## Scaffolding a new project

Samantha can scaffold this system on command. Steps:

1. Create the directory structure above (adjust root path).
2. Copy `SYSTEMS-hub-template.md` → `SYSTEMS/<first-system>.md`, fill frontmatter.
3. Copy `adr-process/DECISIONS-template.md` → `DECISIONS.md`, clear examples.
4. Wire the index generator (see `INDEX-generator.README.md`).
5. Add the CI lint job.
6. (Optional) Drop in a `mkdocs.yml` and configure publishing.

The system is live once step 4 is wired and CI is green.
