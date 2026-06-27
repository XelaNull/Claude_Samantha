# INDEX Generator — Design + CI Contract

`SYSTEMS/INDEX.md` is a machine-generated file. **Do not hand-edit it.** If it is wrong, fix the generator or the source frontmatter, then regenerate.

This document describes what the generator does, the CI contract it enforces, and where to put the actual script.

---

## What the generator does

1. **Scans** `SYSTEMS/*.md` (and `SYSTEMS/**/*.md` for subsystems) for YAML frontmatter.
2. **Reads** the required fields: `system`, `role`, `status`, `version`, `generated-from`.
3. **Groups** files by `system` name; identifies the `role: hub` file as the canonical entry-point.
4. **Emits** `SYSTEMS/INDEX.md` with the structure described below.
5. **Marks** the output with `<!-- GENERATED — do not hand-edit -->`.

---

## Output format (`SYSTEMS/INDEX.md`)

```markdown
<!-- GENERATED — do not hand-edit. Run `<generator-command>` to regenerate. -->
<!-- Last generated: <timestamp> -->

# Systems Index

| System | Hub Doc | Status | Version | Subsystems |
|--------|---------|--------|---------|------------|
| <system-name> | [<system-name>.md](<system-name>.md) | Live | 1.2 | [auth-provider](auth-provider.md) |
| ... | | | | |
```

Subsystem links appear in the same row as their hub. A system with no subsystems has an empty Subsystems cell.

---

## Staleness detection (the `generated-from` hash)

Each hub doc's frontmatter may carry:

```yaml
generated-from: "docs/reference/source-data.md:a3f9b2c1"
```

The generator compares the stored hash prefix against the current file's content hash. A mismatch means the hub doc may be stale relative to its source. The CI job reports stale entries as warnings (not failures by default — promote to failure once the team trusts the process).

---

## CI contract

The CI job does the following on every push/PR:

1. **Regenerate** `SYSTEMS/INDEX.md` in a temp file.
2. **Diff** against the checked-in `SYSTEMS/INDEX.md`.
3. **Fail** if any diff exists — the index is out of date (a hub doc was added, removed, or its frontmatter changed without regenerating).
4. **Fail** if any `SYSTEMS/*.md` file is missing from the index (orphan — not registered).
5. **Fail** if any index entry points to a file that does not exist (dangling entry).
6. **Warn** (or fail, once mature) on stale `generated-from` hashes.

Pre-commit hook: regenerate before commit, so the developer gets fast feedback. But CI is the floor — pre-commit can be bypassed with `--no-verify`; CI cannot.

---

## What the script should implement

<!-- TODO: Author the actual generator script.
     Suggested language: Python or Node (pick whatever the project's toolchain already uses).
     Place it at: scripts/generate-systems-index.<py|js|ts>
     Wire it to: CI job + pre-commit hook (`.git/hooks/pre-commit` or husky/lefthook).
     The implementation contract is fully specified above — this README is the spec.
-->

**Stub status:** the generator described here does not yet exist as executable code. The design is complete and the CI contract is specified. A future build task will author the script from this README.

When implementing:
- Parse YAML frontmatter with a standard library (don't hand-roll the parser).
- Use content hashes from the filesystem for `generated-from` freshness checks.
- Write the output atomically (write to `.INDEX.md.tmp`, rename to `INDEX.md`) to avoid partial writes.
- Exit non-zero on any failure condition listed in the CI contract above.
- Accept a `--check` flag that diffs without writing (for CI use).

---

## The load-bearing invariant

**A lookup miss is NOT proof of absence.** If you search `SYSTEMS/INDEX.md` and don't find system X, the correct response is:

1. Search `SYSTEMS/` for `*.md` files with `system: X` in their frontmatter.
2. If found: the file exists but is not registered — this is a registration bug (missing or wrong frontmatter, or generator not run). Fix the frontmatter and regenerate.
3. If not found: the system is genuinely undocumented. File a DECISION, draft the hub doc, get human go-ahead.

Never author a parallel doc because an index lookup failed. That is how drift is born.
