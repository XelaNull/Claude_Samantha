# Open Knowledge Format (OKF) — Format Reference

**OKF (Open Knowledge Format), v0.1** — an open, human- and agent-friendly format for representing *knowledge*: the metadata, context, and curated insight around data and systems. Markdown-native, diffable in version control, portable across organizations. Source: Google — `GoogleCloudPlatform/knowledge-catalog`, `okf/SPEC.md`.

Samantha carries this reference so she can author, validate, and curate OKF in any project. **OKF is the framework's canonical AI-knowledge format** — it replaces the older `.aispec` (a dense, parallel, hand-authored format that *drifted* from code). Because OKF is plain Markdown, it fits the single-source-of-truth / generate-from-canon posture instead of fighting it: the canonical concept *is* the doc, so there is no parallel artifact to drift.

---

## The Concept Document

A **concept** is one UTF-8 Markdown (`.md`) file with two mandatory parts:

1. **YAML frontmatter** — delimited by `---` … `---`.
2. **Markdown body** — free-form, favoring *structural* markdown.

### Frontmatter

**Required:**
- `type` — a short string naming the kind of concept (used for routing / filtering / presentation). Examples: `BigQuery Table`, `API Endpoint`, `Metric`, `Playbook`, `Reference`, `Service`. **Type values are NOT centrally registered** — pick what fits the project.

**Recommended (priority order):**
- `title` — human-readable name (derivable from the filename if omitted).
- `description` — one-sentence summary (search snippets / previews).
- `resource` — a URI uniquely identifying the underlying asset (omit for abstract knowledge like a playbook).
- `tags` — a YAML list for cross-cutting categorization.
- `timestamp` — ISO-8601 datetime of the last meaningful change.

**Extension:** producers MAY add any key/value pairs. Consumers SHOULD preserve unknown keys when round-tripping and SHOULD NOT reject a document for unrecognized fields. *(The stricter MUST-NOT-reject rule applies at the bundle-conformance level — see Conformance below.)*

### Body — conventional section headings

Favor structural markdown (headings, lists, tables, fenced code) over prose. Three headings carry conventional meaning:

| Heading | Purpose |
|---|---|
| `# Schema` | structured description of the asset's columns / fields |
| `# Examples` | concrete usage, usually fenced code blocks |
| `# Citations` | external sources backing claims — numbered `[1] [Title](url)` |

---

## Bundles, Links, Reserved Files

- A **bundle** is a directory hierarchy of concept files.
- **Cross-links** are ordinary Markdown links. A link from A→B asserts a *relationship*; the *kind* of relationship (parent/child, references, joins-with, depends-on…) is carried by the surrounding prose, not the link. Prefer **absolute (bundle-relative)** links beginning with `/` — they stay valid when files move.
- **`index.md`** (reserved) — a directory listing (no frontmatter); groups concepts under headings with bulleted links, each including the linked concept's `description`. Supports progressive disclosure.
- **`log.md`** (reserved) — chronological change history, newest first; date headings MUST use ISO-8601 `YYYY-MM-DD`.

---

## Conformance

A bundle is conformant if: every non-reserved `.md` file has parseable YAML frontmatter; every frontmatter block has a non-empty `type`; and reserved files (`index.md` / `log.md`) follow their structures when present.

Consumers **MUST NOT** reject a bundle for: missing optional fields · unknown `type` values · unknown extra keys · broken cross-links · a missing `index.md`. Permissive by design — *"if you can `cat` a file, you can read OKF."*

OKF **references** domain schemas (Avro, Protobuf, OpenAPI, …) via `resource` + `# Schema`; it does not subsume them.

---

## Framework Rules (how Samantha uses OKF)

These are the framework's authoring rules, layered on OKF — they travel with the Librarian (§2/§5):

- **DOCS WIN — canon is prescriptive.** An OKF concept for system X is the *truth* about X; code conforms to it. A code↔concept divergence is surfaced and resolved *deliberately* (fix code to canon, OR update the concept via DECISION→ADR) — never silently accepted. *(This inverts the "code wins" drift-surrender that killed `.aispec`.)*
- **Authoritative in-scope.** A concept for X speaks for X only, never for other systems.
- **Single source of truth — generate, never parallel-author.** If a dense AI-digest is wanted, *generate* it from the canonical OKF; never hand-maintain a parallel copy.
- **Gated writes.** Creating / deleting / renaming / restructuring a canonical concept respects the human's go-ahead (like the ADR Accept gate). Samantha proposes; the human authorizes.
- **Curate the collection.** Keep `index.md` honest; hunt the three rot-modes — STALE concepts · DANGLING cross-links · ORPHANS (on-disk concepts missing from the index). The index is generated + CI-verified, not hand-kept; the Librarian's real work is the *semantic* layer — is each concept still *true*?

---

## Worked Example (generic)

A concept file at `/services/auth.md`:

~~~~
---
type: Service
title: Auth Service
description: Issues and validates session tokens for all first-party clients.
resource: repo://services/auth
tags: [security, session, core]
timestamp: 2026-06-27T00:00:00Z
---

Handles login, token issuance, refresh, and revocation. Depends on
[the user store](/data/users.md).

# Schema
| field      | type         | notes                                   |
|------------|--------------|-----------------------------------------|
| token      | string (JWT) | 15-min TTL; refresh via `/auth/refresh` |
| session_id | uuid         | one per active device                   |

# Examples
```http
POST /auth/login  {"user":"…","pass":"…"}  →  200 {"token":"…","refresh":"…"}
```

# Citations
[1] [Session design ADR](/decisions/ADR-014-sessions.md)
~~~~

---

## Migrating from `.aispec`

If a project carries legacy `.aispec` files (OKF replaces that dense, hand-authored format), migrate them to OKF — **gated on the human's go-ahead**, like any canon restructuring. For each `.aispec`:

1. **Create an OKF concept** (`.md`) and map the blocks: `OVERVIEW:` → the body intro + `description` frontmatter · `FACTS:` / `TERMINOLOGY:` → structural body (lists / tables) · `SCHEMA:` → `# Schema` · `EXAMPLES:` → `# Examples` · `CONSTRAINTS:` → body prose · then pick a `type` (e.g. `System`, `Reference`, `API Endpoint`).
2. **Verify the concept against the code** — DOCS WIN, so resolve any drift deliberately (fix code to canon, OR update the concept via DECISION→ADR). The `.aispec` era's "code wins" rule does **not** carry over.
3. **Register** the concept in the bundle's `index.md`.
4. **Retire the `.aispec`** once the OKF concept is verified. Never keep both in parallel — two formats is exactly the drift OKF eliminates.

---

## Adoption note

Place a project's OKF bundle in a predictable directory (e.g. `knowledge/` or `docs/`), with an `index.md` at each level and a `log.md` at the root. Register concepts in the generated index — a miss in the index is a *registration* bug, not proof of absence. See `canonical-docs-system/` for the framework's OKF-aligned docs architecture (hub/index generation + addressability).
