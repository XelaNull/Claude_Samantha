---
# REQUIRED frontmatter — fill all fields before the generator will register this file.
#
# type:           OKF concept type (REQUIRED by OKF). For a hub doc this is `System`.
#                 (Subsystem docs may use `System` too, with role: subsystem.)
#
# system:         The canonical name of the system this doc describes.
#                 Used as the lookup key in index.md. Keep it stable — renaming
#                 requires an ADR (the name is part of the canonical address).
#
# role:           hub       → this is the authoritative entry-point for this system.
#                 subsystem → this doc describes one part; link back to the hub.
#
# status:         Live | Current | Release | Future | Deprecated
#                 "Live" = shipped and running; "Future" = planned, not built.
#
# version:        Semver, date, or sprint tag. Updated when the doc is meaningfully revised.
#
# generated-from: The canonical source file(s) and their content hashes, used by the
#                 index generator to detect staleness. Format: <path>:<sha256-prefix>
#                 Leave blank and fill after first generation, or omit if this doc IS
#                 the canonical source (not generated from another file).
#
type: System
system: <system-name>
role: hub
status: Future
version: "0.1"
generated-from: ""
---

<!-- CUSTOMIZE: Replace everything in angle brackets. Delete all comments before committing. -->

# <System Name>

<!-- One paragraph: what this system does and why it exists. Prescriptive voice — describes what
     SHOULD be true, not just what currently is. This is the system's definition, not a status report. -->

---

## Responsibilities

<!-- Bullet list. What this system owns. Be precise — overlap between systems is a design smell. -->

- <responsibility>

## What it does NOT own

<!-- Explicit non-ownership prevents scope creep and clarifies boundaries for agents. -->

- <non-responsibility>

---

## Architecture

<!-- How the system is structured internally. Diagrams welcome (Mermaid renders in mkdocs).
     Link to ARCHITECTURE/ docs for cross-cutting topology. -->

---

## Key Interfaces

<!-- How other systems interact with this one. API surface, event contracts, shared data. -->

| Interface | Direction | Description |
|-----------|-----------|-------------|
| | | |

---

## Data

<!-- What this system stores or owns. Link to DATA_MODELS/ for full schemas. -->

---

## Constraints

<!-- Hard constraints on this system — things that must never change without an ADR. -->

---

## Related

<!-- Cross-links to subsystem docs, feature docs, ADRs, data models.
     All links bundle-relative absolute (begin with / — OKF's stable form). -->

- **Features:** [/FEATURES/](/FEATURES/) ← status of features in this system
- **Data models:** [/DATA_MODELS/](/DATA_MODELS/) ← schemas
- **ADRs:** [/ADR/](/ADR/) ← decisions that shaped this system

---

<!-- GENERATED SECTION — do not hand-edit below this line.
     The index generator appends subsystem links here. To add a subsystem,
     create SYSTEMS/<system>-<subsystem>.md with role: subsystem and this
     system's name in its `system:` field. The generator will pick it up. -->

## Subsystems

<!-- (populated by generator) -->
