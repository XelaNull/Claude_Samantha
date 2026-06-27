# Monk — memory · project: Samantha Prime (canonical framework repo)

## What I've learned about this project

- This is the canonical source repo (the Claude_Samantha framework). All other projects derive from it.
- Namespace: `.claude/` = harness-discovered files only (agent defs, skills, settings, workflows). `.samantha/` = all framework data and state.
- Agent definitions are in `.claude/agents/`; agent memory lives in `.samantha/agents/<name>/`.
- The spec (`samantha-prime-spec.md`) is in `.samantha/specs/`. It is the ground truth — read it before any build task.
- Build/test/lint commands: not yet established for this repo (it is a framework/config repo, not a compiled project).
- The Reference Pack lives at `.samantha/references/` — greenfield created 2026-06-27. Templates are canonical and project-agnostic.
- Three-tier memory: SELF (global, `~/.samantha/`) · PROJECT (per-repo, `.samantha/memory/MEMORY.md`) · WORKING (live session, plans/specs/scratch). §7 rule 4: "applies to ALL projects" lessons belong in SELF, not per-repo.
- Skills are now plainly named: `diagnose` `build` `polish` `security-review` `spec-check` `i18n` `issue` `commit` `explain` `fix` `gate` `review` `ship` `adversarial-review` (new). All 7 color-code dirs renamed via `git mv` (tracked as rename+modify, not delete+add). The gate skill's routing table was the critical update — every old color-code ref updated to the new name.
- Correct agent model tiers: Monk=Sonnet · Rook=Opus (read-only) · Mack=Sonnet · Cipher=Sonnet · Pixel=Haiku · Rosetta=Haiku. The old README had Rook=Sonnet and Pixel=Sonnet — now corrected.
- **Samantha persona → output-style (task 5, 2026-06-27):** persona lives at `.claude/output-styles/samantha.md` with `keep-coding-instructions: true`. Auto-loaded via `.claude/settings.json` → `"outputStyle": "Samantha"`. CLAUDE.md slimmed to ~3.7KB (was ~22KB) — project context + adoption guide only.
- Output-style Constitution: 5 bullets byte-identical to monk.md + "Memory autonomy" as Samantha's addition. §8a always-on block verbatim as specified.

## How I operate here (my working notes)

- Write to `.samantha/references/` only; never touch `.claude/`, `.samantha/agents/`, or `.samantha/memory/` unless specifically contracted.
- Samantha does not commit — return changes; she reviews and commits.
- Read spec §0.5, §2, §5, §8b before any Reference Pack work. These are the authoritative sources.
- "Project-agnostic" is load-bearing: zero real project names, zero real paths, no pointers to any specific codebase in anything under `.samantha/references/`.
- Coordination-protocol content is deliberately deferred (see `.samantha/references/coordination-protocol/README.md`). Do not author it without a fresh contract from §4.5–4.9.

## Coordination protocol specifics
- `watch-coordination.sh` (was `watcher.sh`): STAR topology; named args `--identity`/`--role`/`--dir`; echo-and-terminate; 20s poll / 1080-iter cap (~6h). Hard convention: Orchestrator identity = "orchestrator".
- Delta display: `tail -c +$((prev_sz+1))` — newly appended bytes only (not `tail -20`).
- ADDRESSING FILTER (added post-initial-build): wakes ONLY when delta contains `" → $IDENTITY —"` or `" → ALL —"` (grep -F; em-dash literal). DELETED files always wake (structural signal). Absorbed changes log count but don't exit. Essential for N-spoke case (all spokes watch same hub file).
- Identity re-arming: stateless by design (fresh SIG_DIR per invocation). Clean to re-arm with a different `--identity` (bootstrap provisional→Orchestrator-assigned handshake).
- Bootstrap handshake (DESIGN EXTENSION): `bootstrap-identity.sh --provision` (shell UUID → pending-<uuid>.md with HEADS-UP) → arm watcher provisional → Orchestrator replies ASSIGN-IDENTITY → `--adopt` (atomic mv same dir). ASSIGN-IDENTITY is 10th MAILBOX tag. Restart stability: `.samantha-identity` dotfile skips handshake.
- `heartbeat.sh`: `IDLE_THRESHOLD=1200s` (20 min), `CADENCE=300s` (5 min), `CAP=21600s`, `DEPTH_FLOOR=12`.
- M1 (self-varying): heartbeat UTC timestamp IS the self-varying element — no `--seq` needed. Watcher delta content is also always unique.
- M2 (pkill footgun): kill using sole-writer PID files — `kill $(cat <coord-dir>/.watch-state/<id>/watcher.pid)` and `kill $(cat <coord-dir>/.watch-state/<id>/heartbeat.pid)`. PIDs are NOT in the presence file anymore.
- M3 (signature): name+size+mtime — size catches growth even when mtime is wrong.
- M4 (read-back): after every write to a coord file, read it back to confirm it persisted.
- `set -uo pipefail` (NOT `-euo`) — grep returning 1 for no-match is tolerated explicitly.
- ROSTER is not a separate file — the coord-dir's .md files ARE the roster (self-populating).
- QUEUE.md is Orchestrator-only writer (no pull/claim race). SQLite path (M6) is optional advanced.
- M8 (additive-only schema): never change existing field meaning — only add new optional fields.
- 6-lens-audit.md: standalone M5 doc. Depth floor ≥12 READY; aim 24 when refilling.
- **Combined-pass (2026-06-27) key facts:**
  - Presence-file write race (HIGH): PIDs moved to `.watch-state/<id>/watcher.pid` + `heartbeat.pid` — sole-writer files, no concurrent writers. `<id>.md` is now append-only: watcher ensures-or-creates on first arm; heartbeat appends via `>>` directly (no mktemp+mv race).
  - Parallel arrays `RF_PATH` / `RF_PREV` / `RF_CURR` replace packed `$f:$prev:$curr` strings (colons in paths break `%%:*` parsing silently).
  - `heartbeat.sh` now requires `--role orchestrator|implementer` (explicit arg — role inference from grepping `<id>.md` raced against watcher create).
  - Stat probe uses `$COORD_DIR` (not `$0`) — split-filesystem safe.
  - FIX 1 refinement: display loop persists `$(file_size "$f")` AFTER `tail -c` read, not detection-time `curr_sz` — prevents re-echo if file grew between detection and display.
  - `SCRIPT_ABS` resolves `$0` to absolute path at startup — re-arm command is cwd-independent.

## Gotchas — things that bit me (don't repeat)

- The WORKFLOW `meta` object must be a pure literal (no template literals, no expressions). Template literals in the `run()` body are fine — they are runtime code. The static meta is not.
- The `.aispec` format's "code wins" rule is the format's own defensive posture. Samantha inverts it to "docs win." Transcribe the original rule faithfully and immediately note the inversion — do not silently correct to "docs win" only.
- INDEX-generator.README.md is the spec for the generator script, not the script itself. The script is a STRETCH / TODO — do not fake one or write a half-baked implementation.
- macOS ships `ugrep` (not GNU grep) — `grep -qF "string"` fails when the string starts with `-` because ugrep treats it as a flag. Use Python for substring checks on lines that start with `-`.
- The `sed -n '/^## Section/,/^$/p'` range pattern behaves differently depending on whether the section header has a blank line after it. Use Python for reliable cross-file comparisons.
