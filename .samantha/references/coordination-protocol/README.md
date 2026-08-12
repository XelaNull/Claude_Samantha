# Coordination Protocol — Orchestrator–Implementer

PROTOCOL-VERSION: 1.6.0

> **Versioning:** bump `PROTOCOL-VERSION` (file + this stamp) on every ratified amendment.
> **Scripts are versioned with the protocol** — `PROTOCOL-VERSION` is sourced by
> `coord-monitor.sh` / `heartbeat.sh`; arm banners print the stamp. A seat running
> scripts whose stamp ≠ this README is a defect.
>
> **1.6.0** (2026-08-12) — Canonical queue schema + tooling: `queue_schema.py`
> (canonical 6-column row schema + a `classify()` heuristic cross-checking a row's
> declared Status against its own content), `queue-append.py` (the sanctioned
> writer — refuses duplicate WO-ids, auto-routes overflow to a backlog file's
> "READY, over the cap" section), `queue-lint.py` (read-only schema/cap/dup
> sweep). Backported from a live deployment (Nebuspace) after its per-repo
> `queue-<repo>.md` files drifted into 7-13 incompatible ad hoc table variants
> with no canonical writer ever having existed to prevent it. Optional — for
> sites using the per-repo pull-queue shape (see `QUEUE-template.md`); does not
> apply to the single-global-push-queue pattern. No script behavior for
> existing single-queue sites changes; adopting this tier is opt-in.
>
> **1.5.0** (2026-08-10) — Protocol Version Handshake: peer staleness detection +
> self-upgrade pointer, never a push:
> - **Bootstrap-time exchange (Part A):** the newborn's `🛰️ HEADS-UP` and the
>   Orchestrator's `🤝 ASSIGN-IDENTITY` reply now both carry `PROTOCOL-VERSION:
>   X.Y.Z` — two-directional (used to be announce-only). Never blocks bootstrap
>   over a version difference alone.
> - **Re-arm-time staleness detection (Part B):** `coord-monitor.sh` compares
>   each known peer's last-known presence `protocol_version` to its own on
>   every LOCAL-channel arm, and posts ONE addressed `⚠️ PROTOCOL-VERSION-MISMATCH`
>   alert on a genuinely new mismatch — deduped the same way `SEAT STALE`
>   already is, never spammed every arm cycle.
> - **Self-upgrade pointer (Part C):** the mismatch message names both
>   versions and WHERE the newer one lives — `git pull` for the common
>   local/shared-repo topology, or `COORD_CANONICAL_SOURCE` for cross-repo/
>   remote-seat. Never embeds file content, a diff, or a script — a pointer,
>   not a payload.
> - **MAJOR/MINOR/PATCH given real meaning (Part D):** MAJOR = wire/grammar-
>   breaking, MINOR = additive/backward-compatible, PATCH = non-semantic.
>   Nothing shipped 1.1.0-1.4.0 was ever MAJOR under this definition.
>   `coordination-precommit-hook.sh` hard-blocks on a MAJOR mismatch only;
>   MINOR/PATCH stay advisory (A/B above).
> - **Hardened (2026-08-10, round-9 — Cipher HIGH, live-demonstrated both
>   directions):** Part D's hard-block gate no longer trusts the unsigned,
>   coord-dir-write-forgeable `.presence` sidecar for a peer's version — a
>   forged presence value could fabricate a false MAJOR mismatch (DoS) or
>   mask a real one (defeat the gate). It now derives a peer's version
>   ONLY from their own already-signed, routine `HEARTBEAT` body (which now
>   embeds `PROTOCOL-VERSION`), verified via `coord-verify.sh`'s own engine
>   — never a second, parallel verification path. Peer enumeration also
>   moved from local mailbox-file presence (evadable by a maliciously-named
>   identity; blind to an archived/rotated seat) to `allowed_signers`, the
>   actual enrolled-identity trust root. **Part B stays presence-sourced,
>   deliberately** — advisory-only, informational, cheap, frequent; Cipher
>   separately rated that path's forgery risk LOW, and the human's
>   hard-block decision is what makes signed-sourcing worth its cost, not
>   every consumer of `protocol_version`. See § Protocol Version Handshake,
>   Part D below for the full mechanism and its ceilings.
> - **Hardened further (2026-08-10, round-10 — Cipher HIGH, round-9's fix
>   moved this hole, did not close it):** round-9's extraction was a second,
>   independent raw-file scan matched back to a verified message only by
>   timestamp — never confirming the specific `PROTOCOL-VERSION` line sat
>   inside the actually-signed bytes. Unsigned text appended straight after
>   a real message's own SIG block sailed through. Fix: `coord-verify.sh
>   --extract-field NAME` scans ONLY the exact bytes it verified for that
>   message (`signed_region`) and prints the value from there — no second
>   scan of any kind.
> - **Hardened a third time (2026-08-10, round-11 — Cipher HIGH, the third
>   distinct way "which claim is authoritative" was gamed):** round-10 still
>   picked a single "current" claim (the last `FIELD-VERIFIED` line,
>   physical file order) — a coord-dir-write attacker with ZERO signing key
>   could physically reorder two of a peer's own genuinely-signed historical
>   claims to flip which one counted, no forgery needed. Round-11 stops
>   picking a winner entirely: blocks on ANY verified incompatible-MAJOR
>   claim in the tail window, full stop. Accepted tradeoff: a brief,
>   self-resolving false-positive block right after a genuine MAJOR
>   transition, until the tail window ages the old claim out — see § Protocol
>   Version Handshake, Part D for the full reasoning.
> - **Hardened a fourth time (2026-08-10, round-12 — Cipher HIGH, one layer
>   above round-11's fix):** round-11 correctly stopped arbitrating which
>   claim wins, but the tail window feeding that collection — plain
>   `coord-verify.sh --tail N` — was still a RAW LINE COUNT, computed before
>   any signature classification. A coord-dir-write attacker with ZERO
>   signing key could append unsigned messages shaped to match the dead-man
>   alarm's own documented `--strict` exemption (tag `⚠️ ` + the
>   `[SIGNING-FAILED — ...]` sentinel — legitimately non-fatal under
>   `--strict`, working exactly as designed) purely to inflate the raw-line
>   count and evict a peer's real, current, genuinely signed+verified
>   incompatible claim from the window — one-directional (can only hide a
>   real mismatch, never fabricate a fake one), but that is this gate's
>   single worst-case failure. Fix: new `coord-verify.sh --tail-verified N`
>   computes its window from CLASSIFIED content — the last N spans that
>   actually verify — so unsigned padding of any shape cannot consume any of
>   that budget; it is skipped for free. Same structural principle as
>   round-10's `--extract-field` fix, applied one layer up: to window
>   selection instead of field extraction.
> - New shared helpers: `coord-presence.sh`'s `protocol_version_major` /
>   `protocol_mismatch_severity` / `protocol_mismatch_message`.
> - See § Message Authenticity, Protocol Version Handshake below for the full
>   mechanism.
> - Tests: `tests/run.sh`.
>
> **1.4.0** (2026-08-09) — Message Authenticity (SSH signing): origin authentication +
> tamper-evidence on the mailbox message bus, via `ssh-keygen -Y sign`/`-Y verify`
> (the same mechanism git uses for SSH-signed commits — no new dependency, **caveat:**
> `-Y sign`/`-Y verify` need OpenSSH 8.2+, but the deterministic UNKNOWN-SIGNER
> classification below needs 8.9+ — stock on Ubuntu 20.04 LTS and macOS Monterey is
> older than that; `coord-verify.sh` self-checks its OpenSSH version and prints a
> distinct WARN naming the actual cause, rather than degrading silently into every
> signed message reading as UNKNOWN-SIGNER):
> - `coord-keygen.sh` (key lifecycle: `--generate`/`--enroll`/`--rotate`/`--fingerprint`)
>   and `coord-verify.sh` (`--tail`/`--since-line`/`--strict`) — new, Required tier.
> - `coord-send.sh` now signs every message it posts (auto-provisions a key if none
>   exists yet) and FAILS LOUD rather than sending unsigned.
> - `coord-monitor.sh` annotates each emitted message with its verify verdict inline
>   (informational only).
> - `coordination-precommit-hook.sh` hard-BLOCKS a commit whose newly-read mail
>   contains an INVALID (tampered) or non-exempt UNVERIFIED (unsigned) message —
>   scoped forward-only from the point a seat upgrades; never re-scans pre-amendment
>   history.
> - `bootstrap-identity.sh --provision` generates the newborn's key and embeds its
>   pubkey in the HEADS-UP body; the Orchestrator's `ASSIGN-IDENTITY` reply enrolls it
>   under the assigned name in the same round trip; `--adopt` carries the key files
>   over the identity rename.
> - `allowed_signers` (new, committed, Orchestrator-only single-writer) is the trust
>   root. `ROSTER-template.md` schema_version 2 (`pubkey_fingerprint`, additive-only).
> - See § Message Authenticity (SSH signing) below for the full mechanism.
> - Tests: `tests/run.sh`.
>
> **1.3.0** (2026-08-09) — Project-scoped star awareness + skill modes + scheduler + presence sidecar:
> - **Project wake/watch:** spokes watch `orchestrator.md` + same-project `impl-*.md`;
>   hub-outbox emit only for TO ∈ {me, ALL, same-project seats}. Other projects silent.
>   Only orchestrator watches everything. `--project` / roster `project:` / `impl-<project>[-lane]`.
> - **Skills:** `coordinate` + `coordinate-solo` + `coordinate-star` (dual renamed star).
> - **Idle schedule:** `IDLE-SCHEDULE-template.md` + `heartbeat --schedule-file`.
> - **Presence sidecar:** `.presence/<id>` for PIDs/state (Phase 4); mailbox stays message log.
> - **Multi-orch:** design memo only — `advanced/MULTI-ORCHESTRATOR.md`.
> - Tests: `tests/run.sh`.
>
> **1.2.1** (2026-08-09) — Superseded by 1.3.0 project filter (1.2.1 was identity-only; wrong scope).
>
> **1.2.0** (2026-08-03) — Backport of live dual-suite extensions into the portable pack:
> IDLE-KICK (own-file self-nudge; distinct from orchestrator discover-on-idle) · `--idle-policy` ·
> HOLD-DAMP-V2 · `--weak-seat` · `--role` + STAR excludes for `PROJECTS.md` / `queue-*.md` ·
> optional remote ssh bus (`advanced/REMOTE-SEATS.md`; `--remote-host` requires `--remote-bus-dir`;
> no baked host/bus paths). Live deployment overlays (e.g. Nebuspace `.claude/`) may still carry
> site defaults — do not blind-overwrite them from this pack without a per-file newer check.

The file-based protocol for **star mode** (formerly called dual mode): Samantha (Orchestrator) coordinating one or more Monk peer instances (Implementers) through shared files when two or more agent processes must work in parallel.

---

## When to use this (star mode threshold)

Star mode is **human-initiated** and only warranted when ANY of:
1. Work must survive a crash, compaction, or session restart.
2. A durable, human-auditable work-order trail is required.
3. The task exceeds one context window and must be partitioned across processes.
4. Two genuinely concurrent live workstreams a human watches in parallel.

Otherwise: **stay in solo mode** (background subagents via `run_in_background`). Solo dominates within one context budget. Arm either mode via the `coordinate-solo` / `coordinate-star` skills (shared substrate: `coordinate`).

**Solo installs:** keep this pack as reference documentation; arm seat scripts only when a skill (or human) opts into star — or when solo wants a local idle scheduler. Do **not** treat "copy vs don't copy scripts" as the primary install fork.

---

## Script tiers (what to copy)

| Tier | Scripts | Who |
|------|---------|-----|
| **Required (dual)** | `coord-monitor.sh` · `coord-send.sh` · `coord-status.sh` · `heartbeat.sh` · `bootstrap-identity.sh` · `coordination-precommit-hook.sh` · `coord-keygen.sh` · `coord-verify.sh` (+ `allowed_signers`, Orchestrator-created) | Every dual workspace root — signing is Required, not optional, as of PROTOCOL 1.4.0: `coord-send.sh` always signs |
| **Optional (PROTOCOL 1.1.0)** | `coord-protocol-metrics.sh` · `coord-session-healthcheck.sh` · `coord-evidence-lint.sh` · `coord-gate-audit.sh` (+ `PROTOCOL-AMENDMENTS.tsv`) | Dual sites adopting the robustness amendment |
| **Optional (PROTOCOL 1.2.0)** | Remote ssh bus — same `coord-monitor`/`heartbeat` binaries with `--remote-host` + `--remote-bus-dir`; see `advanced/REMOTE-SEATS.md` | Dual sites with off-box Implementers |
| **Optional (PROTOCOL 1.6.0)** | `queue_schema.py` · `queue-append.py` · `queue-lint.py` — canonical queue-row schema + writer + lint, see § Canonical queue schema + tooling below | Sites running `queue-<repo>.md` files (single or multi-project) that want schema drift prevented rather than cleaned up after the fact |
| **Do not copy** | Anything under `retired/` | Tombstones only — **no executables**. History in git. |

Implementer sub-repos invoke the **parent workspace** copies by absolute path — they do not need a second full suite.

---

## Arming the inbox (harness bridge)

`coord-monitor.sh` is a long-lived process that prints to stdout when addressed mail arrives. The agent only wakes if the **harness** bridges that stdout into the chat. Arm it with the matching tool for your host:

| Host | How |
|------|-----|
| **Claude Code** | `Monitor` tool with `persistent:true` on the `coord-monitor.sh` command |
| **Cursor Agent** | `Shell` with `notify_on_output` (pattern matching monitor output) — keep the process in the background |

Arm **once per session** (persistent monitor). Do **not** re-arm after every message. On `heartbeat` `exit 42` (WATCHER-DOWN): re-arm the monitor **first**, then the heartbeat.

```bash
./coord-monitor.sh --identity <id> --dir <coord-dir>
# optional on network-mounted coord-dirs:
./coord-monitor.sh --identity <id> --dir <coord-dir> --force-poll
```

### IDLE-KICK + HOLD (PROTOCOL 1.2.0)

STAR spokes do not watch their own outbox — a bare heartbeat would never wake the **owning** seat. `heartbeat.sh` appends an actionable `⚡ IDLE-KICK` (standing `--idle-policy`); `coord-monitor.sh` self-nudges on own-file HEARTBEAT/IDLE-KICK/WATCHER-DOWN.

- **IDLE-KICK** ≠ discover-on-idle. IDLE-KICK = self-wake + policy (all seats). Discover-on-idle = Orchestrator queue-depth directive **folded into** the IDLE-KICK body when `role=orchestrator`.
- **HOLD-DAMP-V2:** named `[HOLD:…]` damps IDLE-KICK and requires periodic HOLD-CHECK ACKs (observed-incident amendment, 2026-07-29).
- **`--weak-seat`:** requires explicit `--idle-policy` (no strong-seat audit-and-improve default). See `advanced/REMOTE-SEATS.md`.

### Project-scoped awareness (PROTOCOL 1.3.0)

On a **shared hub**, implementers must see their **own project** (including sibling seats) and must **not** see other projects. Only the orchestrator is aware of everything.

| Seat | Watches | Hub-outbox emit when TO is… |
|------|---------|------------------------------|
| Orchestrator | All peer outboxes | (n/a — full traffic) |
| Implementer project P | `orchestrator.md` + `impl-*` whose project is P (not self) | `ALL`, this seat, or any seat in P |

Project resolution: `--project` → roster/`project:` → `.presence/<id> project=` → identity `impl-<project>[-<lane>]` (first segment after `impl-`). Multi-hyphen project names need an explicit `--project` or `project:` field.

Hub self-nudge (`orchestrator → orchestrator`) does not wake spokes. Prefer unicast within a project; reserve `ALL` for true cross-seat broadcasts (deploy windows).

Smoke tests: `coordination-protocol/tests/run.sh`.

---

## Topology — STAR

```
               ┌─────────────────────────────┐
               │    <coord-dir>/             │
               │    orchestrator.md  (hub)   │
               │    impl-alpha.md    (spoke) │
               │    impl-beta.md     (spoke) │
               └─────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
   Orchestrator       impl-alpha        impl-beta
   watches ALL         watches          watches
   files except        orchestrator.md  orchestrator.md
   its own             ONLY             ONLY
```

- **Each instance writes only its OWN file** (outbox named by identity).
- **Orchestrator (hub)** watches ALL files in the coord-dir except its own — auto-discovers new implementers.
- QUEUE.md is also excluded from the hub's watch-set: it's orchestrator-owned (single-writer, M7), so every change to it is a self-write — watching it caused a phantom rotation wake (ratified 2026-07-03).
- **Each Implementer (spoke)** watches the Orchestrator's file **and** same-project peer outboxes (`impl-<project>*.md`, excluding self). No cross-project spoke watching. No self-watching for peer chatter (own-file IDLE-KICK is the exception via `emit_own_idle_kick`).
- Hub-outbox delivery to spokes is **project-filtered** (PROTOCOL 1.3.0) — see § Project-scoped awareness.
- The directory's live contents **are** the roster — dynamic, self-populating, no hand-maintained static list.
- **Message-log entries:** append-only at true EOF via shell `>>` (or the write-temp-then-rename pattern in MAILBOX-template.md) — never anchor-based Edit. Structured header/roster fields (`watcher_pid`, `heartbeat_pid`, `state`, `last_active`, `queue_depth`) are the opposite: updated in place via Edit, never appended.

---

## Multi-project coordination

The STAR topology above assumes one Orchestrator coordinating spokes inside a single downstream project. When one Orchestrator instance coordinates **multiple independent downstream repos/projects at once**, extend the same topology rather than replacing it:

- **A hub-only board** (e.g. `PROJECTS.md` in the coord-dir) tracks every active downstream repo/project — its tip/branch, its seats, and its state — in one place. Only the Orchestrator writes it; spokes don't watch it.
- **Per-repo queues, not one global queue.** Instead of a single flat work queue, each downstream repo gets its own queue file (e.g. `queue-<repo>.md`), so claimable work stays scoped and readable per project instead of interleaved across unrelated codebases.
- **Identity stem = the repo/lane a spoke owns.** An Implementer's identity is derived from the project or path-lane it's responsible for (e.g. `impl-<repo>`, or `impl-<repo>-<lane>` on a sub-repo split), and its presence-file `zone` field (see ROSTER-template.md) declares the owned path glob(s) or repo root.
- **Zone is routing source-of-truth.** A HANDOFF is only valid if the work order's target paths are a subset of the recipient's declared `zone`. The Orchestrator checks this before posting any product work order — never assume a spoke owns paths just because it answered fastest or was the last one dispatched.
- **cwd/zone mismatch STOPs the hub.** If a spoke's declared `zone` disagrees with what its identity filename implies (e.g. `impl-<repo>` whose `zone` doesn't resolve inside `<repo>`), the Orchestrator halts and rezones that spoke before posting any product work order to it — a silent mismatch means work could land in the wrong repo or on a seat that doesn't own it.
- **Sub-repo lane splits inherit the same rule.** A single downstream repo can itself split into multiple Implementer seats on disjoint path lanes (e.g. a frontend lane and a backend lane within one repo) — each still gets its own identity and declared `zone`, checked the same way. Multi-project support is really "zone precision, applied at whatever granularity the deployment needs" — repo-level or lane-level.

The STAR invariants (single-writer-per-file, hub watches all spokes, spokes watch only the hub, no spoke-to-spoke watching) are unchanged — multi-project just adds a routing layer (`zone` + per-repo queues + a hub board) on top so one hub can safely fan out across more than one codebase.

---

## Canonical queue schema + tooling (PROTOCOL 1.6.0)

**The gap this closes:** nothing in the base protocol above defines what a *row* in `queue-<repo>.md` must look like, beyond QUEUE-template.md's starting example. Left unenforced, every agent hand-formats rows differently as the file grows across weeks/months — a downstream deployment (2026-08-12) accumulated **7-13 incompatible ad hoc table variants per file** this way, with no canonical writer or lint ever existing to catch it. The worst instance: a work-order row stayed classified as buildable-now despite its own description text reading "confirmed shipped — not claimable, already done" — nothing was checking a row's declared Status against what its own content actually said.

**Canonical row schema** (6 columns): `| WO | Priority | Status | Claimed-by | Verified-against | Description |`. Priority is `HIGH`/`MED`/`LOW` or `P0`-`P4` (pick one vocabulary per project, don't mix). Status is one of `CURRENT` / `PENDING` (alias `READY`) / `DONE` / `GATED` / `PARKED` / `NEEDS-TRIAGE`.

**Three files, one import chain:**
- `queue_schema.py` — the schema itself: column shape, valid-value regexes, a schema-drift-tolerant row parser (`parse_table`/`parse_table_text`), a `classify()` heuristic that infers a row's real status from its own cell content (not just a literal `status` column — several drifted schemas bury the real signal in a `gate/verified` or description cell instead), and `validate_row()` which cross-checks a row's *declared* Status against what `classify()` infers from its *content* — this cross-check is what would have caught the "confirmed shipped... already done" row above.
- `queue-append.py` — the only sanctioned way to add a row. Validates against the schema before writing, refuses duplicate WO-ids (`--force` to override), and auto-routes overflow past `--cap` (default 24) into `backlog-<repo>.md`'s overflow section instead of silently blowing past the depth-floor-adjacent cap. `--dir` points at the coord-dir (defaults to `$COORD_DIR` or `./.samantha/coord`).
- `queue-lint.py` — read-only sweep. Reports column-shape drift, invalid Priority/Status values, duplicate WO-ids, cap overruns, and the declared-vs-content disagreement check above. `--all` additionally lints a backlog file's own quick-reference tables (not its verbatim historical dump, which intentionally preserves whatever legacy shape it always had). Run it periodically — each proactive discovery-pass wake is a natural cadence — not only when something already looks wrong.

**Adoption note:** these three files have zero hardcoded paths (`queue-lint.py`/`queue-append.py` take `--dir`, `queue_schema.py` is pure logic) — copy all three together into a site's script directory; they don't need anything else from this reference pack to run. Building/rolling this out at a site whose queue files are already schema-drifted needs a one-time manual triage pass first (don't trust a first-pass automated migration on messy legacy schemas without a self-test-then-verify step — build the classifier, run it read-only, spot-check disagreements, *then* apply) — the tooling here prevents the drift from recurring, it doesn't retroactively fix years of hand-formatting on its own.

---

## Message Authenticity (SSH signing)

**PROTOCOL 1.4.0.** Every message on the mailbox bus is origin-authenticated and
tamper-evident: `coord-send.sh` SSH-signs everything it posts, and readers can
verify (`coord-verify.sh`) or hard-enforce (`coordination-precommit-hook.sh`)
that a message really came from who it claims and wasn't altered after posting.

### Mechanism

`ssh-keygen -Y sign` / `-Y verify` — OpenSSH's native signing facility, the same
one git uses for SSH-signed commits. No new dependency: it's already on every
implementer's box. All signatures use the namespace string `samantha-coord`,
which scopes them so they can never be replayed as, say, a git-commit signature
(or vice versa).

**Version floor.** `-Y sign`/`-Y verify` themselves only need OpenSSH 8.2+. The
UNKNOWN-SIGNER classification below (`ssh-keygen -Y match-principals`) needs
8.9+ — a box between 8.2 and 8.8 (stock on Ubuntu 20.04 LTS, macOS Monterey)
has every signed message misclassify as UNKNOWN-SIGNER regardless of real
enrollment, hard-blocking every `--strict` commit with remedy text that sends
the operator chasing the wrong problem. `coord-verify.sh` runs a one-time
version probe (`ssh -V`) and prints a distinct WARN naming the actual cause
when it detects <8.9, rather than degrading silently.

### Key storage (per-seat private key, never committed)

```
~/.samantha/coord-keys/<dirhash>/<identity>_ed25519
```

`<dirhash>` = first 12 hex chars of `sha256(<coord-dir>/.coord-id contents)`.
`.coord-id` is a stable random token, generated once and committed into the
coord-dir itself — **not** a hash of the absolute coord-dir path (2026-08-09
hardening): an absolute-path hash silently orphaned every already-provisioned
key the moment this portable framework's checkout was moved, renamed, or
re-cloned to a different location, with no error — just "no key found,
re-provision" against the new (wrong) derived path. The id file travels WITH
the coord-dir instead, the same way `allowed_signers` already does. This
scopes keys per coord-dir, so the same identity string (e.g. two different
projects both running an `impl-alpha`) never collides across projects on one
machine.

**`.coord-id` travels WITH a deployment, never between deployments.** It is
committed **within** that one coord-dir's own git history, same as
`allowed_signers`. Do **not** carry it over when cloning/copying a coord-dir
to stand up a genuinely NEW, separate deployment (a second project, a fresh
environment that should NOT share key namespace with the original) — doing
so collapses the per-coord-dir separation `.coord-id` exists to provide,
silently reusing the source deployment's key namespace in the copy. Delete
`.coord-id` (it regenerates itself on next use) as part of any "clone this
coord-dir to start a new one" procedure. Conversely, do **not** `.gitignore`
it in a normal single-deployment repo — it needs to be committed and shared
exactly like `allowed_signers`, or a fresh checkout regenerates its own
token and every already-provisioned key in that checkout silently orphans.

Key files are mode `0600` (containing dir `0700`), generated
passphrase-less (`ssh-keygen -t ed25519 -N ""`) — proportionate for a local
automation key protected by filesystem permissions, the **same trust tier as an
unattended CI deploy key**. Stated plainly rather than hidden: a passphrase-less
key is only as safe as the box it lives on.

`coord-keygen.sh` owns this lifecycle:

| Mode | What it does |
|------|--------------|
| `--generate --identity <id> --dir <coord-dir>` | Idempotent. Prints the identity's raw pubkey line (existing or newly generated) to stdout; guidance to stderr. |
| `--enroll --identity <id> --pubkey-line "<line>" --dir <coord-dir> [--rotate]` | Appends `<id>`'s key to `allowed_signers`. Refuses a silent key-swap (different key already on file) unless `--rotate` is also given. |
| `--rotate --identity <id> --pubkey-line "<line>" --dir <coord-dir>` | Same as `--enroll --rotate` — an explicit, rare, deliberate re-key. |
| `--fingerprint --identity <id> --dir <coord-dir>` | Prints `ssh-keygen -lf` output, for display in ACK/roster messages (see ROSTER-template.md's `pubkey_fingerprint` field). |

### Trust root: `allowed_signers`

`<coord-dir>/allowed_signers` — standard OpenSSH `allowed_signers` format, one
line per identity:

```
<identity> namespaces="samantha-coord" <key-type> <base64-key>
```

**Single-writer: Orchestrator only** — same pattern as `QUEUE.md` (M7; see §
Topology — STAR). This file **IS committed/shared**: it holds public keys only,
which is Rule-5-safe (a public key is not a secret).

**TOFU trust root.** The very first key enrolled — the Orchestrator's own, at
its own bootstrap — is trust-on-first-use: nothing yet exists to vouch for it.
This is the **same trust tier the Orchestrator already holds** as sole namer in
§ Identity Bootstrap (collision-free by construction) — not a new, separately-
justified trust primitive.

**Write-gated, unconditionally (2026-08-09, human-approved; verb coverage
widened 2026-08-09 round-3 — see below).**
`coordination-precommit-hook.sh` BLOCKS any commit-landing verb (`commit`,
`merge`, `cherry-pick`, `rebase`, `am`, `revert`, `pull`) or `git push` that
touches a file named `allowed_signers` unless an explicit authorization
reference (`AUTH:`/`human GO`/`DECISION-…`/`sign-off:`, or `COORD_AUTH_REF`)
is present — the same marker pattern § "Fail closed at the point of action"
already uses for gated pushes below, but **unconditional** here (not behind
`COORD_GATED_PATH_PATTERN`): this file is the trust root for every signature
verification in the protocol, so an unreviewed edit here is categorically
different from an unreviewed edit to an ordinary file.

**Ceiling, stated so it isn't over-trusted:** none of this — the write gate,
the single-writer-Orchestrator convention, the TOFU bootstrap above — stops a
determined malicious process that already has write access to the coord-dir.
Filesystem permissions were never an isolation boundary in this protocol (see
§ "Fail closed at the point of action" below for the same admission about its
gated-push mechanism); a co-resident process with that access can edit `allowed_signers`
directly, bypassing every hook, or forge an authorization reference exactly as
easily as a legitimate author writes one. What this buys is real but partial:
an ACCIDENTAL or careless edit (a bad rotate, a copy-paste merging two
coord-dirs' trust roots) gets caught before it lands, and a deliberate change
leaves an auditable trail. Full enforcement against a hostile co-resident
needs OS-level process isolation (separate users/containers/sandboxes) —
out of scope for a filesystem-permissions-based protocol.

### Enrollment handshake (bootstrap)

Naming and key-trust land in **one round trip**, not two ceremonies:

1. A newborn Implementer's `bootstrap-identity.sh --provision` generates its
   signing key and embeds the raw pubkey line in the `🛰️ HEADS-UP` body it
   already posts (this message itself stays unsigned — see Exemptions below).
2. The Orchestrator's `🤝 ASSIGN-IDENTITY` reply step calls
   `coord-keygen.sh --enroll` with that pubkey line, under the **assigned**
   name (not the provisional one).
3. `bootstrap-identity.sh --adopt` carries the local key files over the same
   rename that retargets the mailbox file (`pending-<uuid>_ed25519` →
   `impl-alpha_ed25519`) — same key material, so what the Orchestrator just
   enrolled is exactly what `coord-send.sh` finds on disk from then on.

A **pre-assigned** identity (no bootstrap handshake) enrolls the same way, just
without the provisional-name detour — see the Implementer checklist below.

### Sending: always signed, hard-fail on sign failure

`coord-send.sh` auto-provisions a key (`coord-keygen.sh --generate`) if none
exists yet for `--identity`, then signs every message it posts. If
`ssh-keygen -Y sign` fails for any reason (including too old an `ssh-keygen`),
`coord-send.sh` **FAILS LOUD and refuses to send unsigned** — it never silently
degrades. There is no supported way to post an unsigned message once a seat's
tooling is at 1.4.0.

### heartbeat.sh's own appends: signed the same way, except the alerts that must never go silent

`heartbeat.sh` never routes through `coord-send.sh` (it appends directly to its
own mailbox file on a timer), but it shares `coord-keygen.sh`'s signing
helpers (`ensure_signing_key` / `sign_message_file` — the exact functions
`coord-send.sh` itself calls), so it can never drift from `coord-send.sh` on
signing mechanics:

- **HEARTBEAT / IDLE-KICK** and **HOLD-CHECK** entries: sign or don't post.
  If signing fails for either, `heartbeat.sh` WARNs to stderr and skips that
  cycle's append entirely — it never falls back to an unsigned post. This is
  safe because the dead-man switch (`WATCHER_DEAD_TICKS`) already tolerates a
  missed tick, so there is no unsigned shape of a routine heartbeat/HOLD-CHECK
  for `--strict` to ever need to exempt.
- **⚠️ WATCHER-DOWN** and **⚠️ HOLD-WAKE-UNACKED** (the two dead-man alarms —
  both self-terminate the heartbeat, exit 42 and exit 43 respectively, to
  force a human or peer to notice): try to sign first, same as everything
  else — when signing succeeds the message is fully verified like any other,
  tamper included. Signing these is best-effort, not mandatory: they are the
  messages in the protocol that must never be silently swallowed for
  auth-layer reasons (a dead-man alarm is exactly the moment you can least
  afford a "couldn't verify, so drop it" gap), so **only if signing itself
  fails** does `heartbeat.sh` fall back to appending it UNSIGNED — loudly,
  with the body prefixed
  `[SIGNING-FAILED — unauthenticated, verify liveness by other means]`. Both
  get identical treatment deliberately (2026-08-09 ratified): exempting one
  dead-man alarm from fail-closed auth but not the other would be an
  inconsistent trust model with no defensible reason. See exemption (c) below
  for how `coord-verify.sh` tolerates exactly this narrow fallback shape
  without weakening verification of a signed alert.

### Signature block format

Appended by `coord-send.sh` immediately after the message body. See
MAILBOX-template.md § Message Grammar for the full grammar and a worked
example. The `bytes:` line is the exact byte length of the signed region —
`coord-verify.sh` reads exactly that many bytes starting at the message's
header line to find where the signature applies, full stop, which is what
makes message-boundary detection exact rather than a heuristic (2026-08-09
hardening — see coord-verify.sh's header comment for why the old
"scan forward for the next header-shaped line" approach could misparse a
message whose body legitimately quotes a prior header).

### Verifying: `coord-verify.sh`

```bash
coord-verify.sh --dir <coord-dir> --file <mailbox-file> [--tail N] [--since-line N] [--strict]
```

Per message: `✅ VERIFIED` / `⚠️ UNVERIFIED (no signature)` / `❓ UNKNOWN-SIGNER
(identity not enrolled / allowed_signers stale)` / `❌ INVALID (signature
present, verification FAILED)`. `❌ INVALID` is always fatal (exit non-zero) —
a tamper/forgery signal, `--strict` or not. `⚠️ UNVERIFIED` alone exits 0
unless `--strict` is given, in which case it (and `❓ UNKNOWN-SIGNER`, always)
also fails, **except** for three exempt message shapes for `⚠️ UNVERIFIED`
(detected by FROM/TAG/TO pattern on the header line — plus, where noted, a
FROM == basename(file) file-binding check — see the script's own header
comment, which is written to be the one place a reviewer can audit "did they
just carve a hole in the gate"):

1. a `pending-*` seat's first `🛰️ HEADS-UP`, file-bound to its own
   `pending-<uuid>.md` (bootstrap handshake),
2. an `orchestrator` `🤝 ASSIGN-IDENTITY` reply addressed to a still-`pending-*`
   TO (bootstrap handshake), and
3. an unsigned message whose body carries the literal sentinel
   `[SIGNING-FAILED —`, file-bound to its own poster's outbox
   (heartbeat.sh's best-effort-sign-else-flag fallback for either dead-man
   alarm, `⚠️ WATCHER-DOWN` or `⚠️ HOLD-WAKE-UNACKED` — collapsed into one
   sentinel-keyed exemption (2026-08-09) rather than two separately tag-
   enumerated ones, so it self-extends to any future alarm type heartbeat.sh
   grows without a new enumerated hole).

`❓ UNKNOWN-SIGNER` is never exempt for any of the three shapes above — those
exemptions apply only to a message with **no SIG block at all**; a message
that DOES carry one is always fully verified (enrolled-but-invalid still
comes back `❌ INVALID`, not-yet-enrolled comes back `❓ UNKNOWN-SIGNER`, both
non-exempt under `--strict`). The first two exemptions exist only to let the
trust-bootstrap handshake happen without a chicken-and-egg deadlock. The third
exists only because an alert whose signing itself failed must still get
through — one that DOES carry a SIG block gets no special treatment at all: it
is fully verified, file-bound, and a tampered/forged one still comes back
`❌ INVALID`, never exempt.

`coord-monitor.sh` annotates every emitted message inline with its `--tail`
verdict — informational only, never affects wake/addressing mechanics.

### Hard-block: `coordination-precommit-hook.sh`

Runs alongside (not instead of) the existing Rule-4 mailbox-read gate, but is
**deliberately independent of it** (2026-08-09 round-2 hardening — see
below for why). The hook derives a trusted lower bound for "what's new"
from **`git show HEAD:<file>`** — the mailbox file's content as of the last
commit (nothing, if the file is untracked or new) — snaps that byte count to
the nearest real message boundary via `coord-verify.sh --find-boundary`, and
runs `coord-verify.sh --strict` from there to the current working-tree EOF.
Any `❌ INVALID`, or any non-exempt `⚠️ UNVERIFIED`, **BLOCKS the commit**
(not a warning) — printing the offending message's header and verdict so
the cause is visible immediately.

**Why git, not the mailbox-read receipt:** an earlier version of this gate
anchored on the same per-seat receipt the Rule-4 nudge uses
(`<coord-dir>/.watch-state/<id>/<file>.size`). A live security review showed
that receipt is not a security boundary even with its own hash-binding —
sha256 is not a keyed MAC, so anything with write access to inject unsigned
or tampered mail also has read access to compute a matching hash and
self-write a forged receipt using the exact helper an honest watcher uses.
The receipt still exists and is still hash-bound (see coord-receipt.sh), but
it is used **only** for the original Rule-4 "have you read your mail" nudge,
which pre-dates this amendment and never claimed to be a security boundary.
Git history is not attacker-forgeable without rewriting it, which this
protocol already treats as a gated, irreversible action elsewhere (Disaster
Rule 1, the force-push carveout).

**Verb coverage (widened 2026-08-09 round-3 — Cipher CRITICAL):** the hook
self-filters on the Bash command TEXT, and used to recognize only a literal
`git commit` / `git push` substring. `git merge`, `git cherry-pick`, `git
rebase --continue`, and `git am` all land a commit object exactly as surely
as `git commit` does, and all bypassed every check here — including this
hard-block and the `allowed_signers` write gate below — with zero output,
no `--no-verify` or history rewrite needed. The self-filter now also
recognizes `merge`, `cherry-pick`, `rebase`, `am`, `revert`, and `pull`
(which implicitly merges or rebases). **Ceiling, stated so it isn't
over-trusted:** this remains a Claude-Code-session-scoped Bash-command-TEXT
matcher, not equivalent to a real git hook — it does not protect a human
typing git commands directly in a terminal (it only fires on a Bash tool
call inside a hooked session), and a text matcher can always be blindsided
by some future/uncommon verb, alias, or wrapper script this list doesn't
enumerate. A durable fix — real `.git/hooks/pre-commit` +
`pre-merge-commit` hooks, enforced by git itself regardless of tool or
process — is out of scope for 1.4.0; flagged as a future item, the same
"acknowledged gap, not solved this round" treatment `advanced/REMOTE-SEATS.md`
gets for cross-machine watch coverage.

**Scope, stated as a PREREQUISITE, not just a note (sharpened 2026-08-09
round-3 — Rook):** if a coord-dir's mailbox files are committed to git as
part of normal operation, only mail appended since the last commit is
re-verified — a live deployment adopting this amendment does not find
itself instantly re-blocked on its own pre-amendment (unsigned) history
every run, only on what's actually new. If a mailbox file has never been
committed at all, the git-anchored floor is 0 and the **whole file** is
verified every time — the safe default in both directions, but with one
real consequence for `--strict`: a newly-`--adopt`ed identity's OWN first
HEADS-UP message permanently carries `FROM=pending-<uuid>` inside
`<assigned-name>.md` (the `--adopt` rename never rewrites message content —
see § Identity Bootstrap), which is legitimate and correctly non-exempt-but-
not-INVALID under the two-tier structural check, but reads as a hard
`⚠️ UNVERIFIED` block under `--strict` for as long as it's never git-anchored
past. Since the Orchestrator's inbox is every peer file, an un-committed
coord-dir means every Orchestrator commit is blocked forever by this one
fully-honest message. **Commit the coord-dir's mailbox files once after each
identity `--adopt`, before relying on `--strict`** — see the Bootstrap
Checklist below. See
`.samantha/references/safety-carveouts.md`: never bypass or disable this
hard-block without explicit human sign-off — a verification failure is a
tamper/impersonation signal, not friction to route around.

### Rotation

Re-keying an identity (compromised key, lost key, routine hygiene) is
`coord-keygen.sh --rotate` — the Orchestrator only, deliberate, loud on stderr.
It replaces what every reader currently trusts for that identity, so confirm
out-of-band that the rotation is genuine before running it.

### Protocol Version Handshake

**PROTOCOL 1.5.0.** Nothing before this detected a peer running a stale
coordination-protocol install. Each seat already writes its own
`protocol_version` into its own `.presence` on every arm (`coord-monitor.sh`,
`heartbeat.sh`); this amendment adds the pieces that actually READ and
compare it, plus a bounded self-upgrade pointer — never a push.

**MAJOR / MINOR / PATCH, given real meaning for the first time:**

- **MAJOR** — wire/grammar-breaking: a seat on the old MAJOR cannot correctly
  produce or parse what the new MAJOR expects.
- **MINOR** — additive/backward-compatible. Every amendment shipped 1.1.0
  through 1.4.0 to date matches this tier.
- **PATCH** — non-semantic: docs/test-only, no behavior change.

This is a forward-looking convention, not a retroactive reclassification —
**nothing shipped to date was ever a MAJOR bump under this definition.**
MAJOR is the only tier `coordination-precommit-hook.sh` blocks on (see Scope
below); MINOR/PATCH are advisory-only, surfaced by the two mechanisms below.

**A — bootstrap-time exchange.** The pubkey-carrying first-contact messages
(already necessarily unsigned/exempt — chicken-and-egg, nothing exists yet to
verify against) carry `PROTOCOL-VERSION: X.Y.Z` alongside the pubkey: the
newborn's `🛰️ HEADS-UP` (both the `--provision` path and the manual
pre-assigned-identity path, Bootstrap Checklist step 4b) announces its own;
the Orchestrator's `🤝 ASSIGN-IDENTITY` reply (step D) now carries the hub's
own back — this exchange used to be one-directional. On a mismatch,
enrollment proceeds exactly as it would on a match, unconditionally — a
version difference alone never blocks bootstrap. The reply just also carries
the plain-language mismatch note below if versions differ.

**B — re-arm-time staleness detection.** Bootstrap-time exchange only ever
fires once, at first contact — it never re-fires for a seat that already
bootstrapped and simply forgot to upgrade before its next restart. This is
the part that actually catches that case: on every LOCAL-channel
`coord-monitor.sh` arm, after writing this seat's own `protocol_version` to
presence, it walks the same peer roster message delivery already uses and
compares each peer's last-known presence `protocol_version` to its own. On a
mismatch it posts ONE loud, addressed `⚠️ PROTOCOL-VERSION-MISMATCH` message
into its own outbox (the STAR addressing filter delivers it to the stale
peer, same as `⚠️ WATCHER-DOWN`/`⚠️ HOLD-WAKE-UNACKED`) — not just local
stdout, so the peer's own session and a human reading their file both notice
it. It does not spam this every arm cycle: a state file
(`.watch-state/<id>/monitor/protocol-version.<peer>.state`) gates the alert
the same way the SEAT STALE check's `wasstale` state file does, alerting
again only on a genuinely NEW mismatch (either side's version changes), and
clearing the moment versions agree again. Scoped to the LOCAL channel only —
a remote seat's presence lives on a different host and isn't reachable via a
local presence lookup; not extended to the remote channel this round.

**C — self-upgrade pointer, not a push (human's explicit design call).** The
mismatch message (both A's bootstrap reply and B's re-arm alert use the SAME
wording, `coord-presence.sh`'s `protocol_mismatch_message()`) names the two
versions, the severity, and WHERE the newer version lives — never a diff, a
script, or embedded file content. The receiving seat's own agent session is
responsible for fetching/copying under its own local tooling and initiative,
exactly like a manual sync today; this message is not a distribution channel.
Remediation text depends on topology:
  - **Local/shared-repo** (the common case — Orchestrator and Implementer
    share a repo checkout; this framework's own `DEPLOYMENTS.md` model is
    copy-based, not centrally pushed): zero-cost — `git pull`, then re-arm.
    This is the default wording.
  - **Cross-repo/remote-seat:** set `COORD_CANONICAL_SOURCE` (optional env
    var, empty by default) to the canonical framework location. Unset, the
    message asks the peer to check with their Orchestrator/human rather than
    fabricate a path.

**D — Scope.** `coordination-precommit-hook.sh` adds a protocol-version gate:
if a peer's MAJOR version differs from this seat's own MAJOR version, the
commit is blocked (`FAIL`, exit 2 — same reporting style as the other checks
in that file). MINOR/PATCH differences never block — advisory only, via A/B
above. As of 1.5.0 this check cannot fire on anything in a real deployment
(there is no MAJOR bump yet to differ against) — it is a ceiling for a future
MAJOR bump, proven with a synthetic fixture in this pack's own test suite.

A hard block is only as trustworthy as what feeds it, so unlike A/B/C above,
Part D deliberately does NOT read a peer's version from `.presence` (round-9,
2026-08-10, Cipher HIGH — see the 1.5.0 changelog entry above for the
live-demonstrated exploit). Instead:
  - **Signed source.** `heartbeat.sh`'s routine `HEARTBEAT` append now embeds
    `PROTOCOL-VERSION: X.Y.Z` in its already-signed body. For each peer, this
    check collects EVERY message (within a bounded recent-window scan —
    several `HEARTBEAT` cycles' worth, not an unbounded full-history rewalk
    every commit) that carries this field AND verifies cleanly against
    `allowed_signers`, via `coord-verify.sh`'s own engine — never a second,
    parallel verification path. The window itself is chosen from CLASSIFIED
    content, not a raw line count — see the round-12 bullet below.
  - **No arbitration — block on ANY incompatible claim (round-11,
    2026-08-10, Cipher HIGH — the third distinct way "which claim is
    authoritative" was gamed).** This gate used to pick a single "current"
    claim — first the peer's `.presence` value (round 8, unsigned,
    forgeable), then the last-verified claim by an unscoped byte range
    (round 9), then the last-verified claim by file position (round 10,
    fixed round-9's scoping gap but not the underlying approach). Round 10's
    fix still let a coord-dir-write-level attacker with ZERO signing key
    physically reorder two of a peer's OWN, genuinely, honestly signed
    historical `HEARTBEAT`s — no forgery, not one byte inside either message
    touched, both independently still `VERIFIED` — and flip which one a
    "most recent wins" rule treated as current, in either direction (mask a
    real mismatch, or fabricate a false one from stale history). The attack
    precondition — a peer having 2+ genuinely different historical version
    claims in the tail window — is not an edge case: it is the literal shape
    of a genuine version transition, the exact event this gate exists to
    catch. Round-11 stops picking a winner entirely: it blocks if ANY
    verified claim in the tail window has an incompatible MAJOR, and lists
    every incompatible claim found, not just one. **Accepted tradeoff:**
    immediately after a genuine, deliberate MAJOR transition, a peer's own
    past incompatible claim can still sit in the tail window until enough
    newer content ages it out — a brief, self-resolving false-positive
    block. Deliberately preferred over any scheme that re-introduces a
    "pick the winner" step: MAJOR bumps are rare (nothing shipped
    1.1.0-1.5.0 has ever been one) and deliberate; "briefly noisy right
    after an expected rare transition" is a categorically safer failure
    mode than "an attacker with no signing key decides which of a peer's
    own real, honest claims counts."
  - **Window selection anchored on verified spans, not raw lines
    (round-12, 2026-08-10, Cipher HIGH — a fourth distinct way this gate's
    inputs were gamed).** Round-11 stopped arbitrating WHICH claim wins, but
    the tail window feeding that collection was still plain `coord-verify.sh
    --tail N` — a RAW LINE COUNT, computed before any signature
    classification. A coord-dir-write attacker with ZERO signing key can
    append any number of unsigned messages shaped to match the dead-man
    alarm's own documented `--strict` exemption (tag starting `⚠️ `, body's
    first line the exact `[SIGNING-FAILED — ...]` sentinel — that exemption
    checks SHAPE only, never that `heartbeat.sh` itself produced it or that a
    real signing failure occurred). Each one is legitimately non-fatal under
    `--strict`, working exactly as that exemption is meant to, while ALSO
    counting as a raw line toward `--tail`'s eviction boundary — enough of
    them pushes a peer's real, currently-true, genuinely signed+verified
    incompatible claim out of the window entirely, so this gate sees "0 with
    a verified claim" instead of the real one. One-directional only (can
    hide a real mismatch, never fabricate a fake one), but that is this
    gate's single worst-case failure. Fix: `coord-verify.sh --tail-verified
    N` computes its window boundary from CLASSIFIED content — the last N
    message spans that actually verify — never a raw line count, so unsigned
    padding of any shape (including all three `--strict` exemption shapes)
    is skipped "for free" and cannot consume any of that budget. Same
    structural principle as round-10's `--extract-field` fix (scope to
    signed bytes, never a second raw scan), applied one layer up: to window
    selection instead of field extraction.
  - **Accepted characteristic — unbounded scan cost (Cipher HIGH finding,
    2026-08-10, reviewed with the human — not fixed).** `--tail-verified`'s
    classify-then-slice approach has unbounded worst-case cost relative to
    file size: finding the last N verified spans can require classifying
    (crypto-verifying) arbitrarily much of a file, since verified-message
    density can't be known in advance. No cap — capping naively (stopping
    the classify pass early) would reopen round-12's exact masking bug for
    whatever content falls past the cap. A very large or heavily-padded
    peer mailbox file makes check 1d's pass over that peer proportionally
    slower. This is accepted for this deployment model rather than fixed
    with a bounded-scan mechanism: this framework runs on the human's own
    private infrastructure between their own agent sessions, not a public/
    multi-tenant service — an actor who already has coord-dir write access
    to deliberately pad a peer's file purely to slow down a git commit has
    far more damaging options available at that point.
  - **Peer set.** Enumerated from `allowed_signers` (the actual
    enrolled-identity trust root) rather than local mailbox-file presence —
    comma-separated principal lists on one line (a hand-edited-only shape;
    every tool-written line is one bare identity) are split before
    enumeration, so one shared line correctly yields every principal on it —
    an attacker cannot rename their way out of being enrolled the way a
    mailbox-file-shaped exclusion list could be evaded, and an archived/
    rotated seat (`<id>.md` → `<id>.archive.md`, an ordinary lifecycle
    event) stays enrolled and is still enumerated and counted — see the
    next bullet for what actually happens to it (skipped, not blocked; a
    rotated seat has no live file left to find a verified claim in).
  - **Fail-open on absence, never on unknown.** A peer with no verified
    `PROTOCOL-VERSION` claim yet (new peer, pre-1.5.0 history, or an
    archived seat whose only claim now lives in a file `coord-verify.sh`'s
    structural FROM==basename(file) check can never verify — see that
    script's own header) is skipped, not blocked. A seat whose OWN
    `PROTOCOL_VERSION` reads `"unknown"` (a partial/incomplete framework
    copy missing its `PROTOCOL-VERSION` file) skips the whole gate with a
    loud `WARN`, rather than false-blocking every peer, every commit,
    forever, on not knowing its own version.
  - **Remote-seat ceiling.** This gate is LOCAL-channel only, same as Part B.
    Unlike Part B, this is not "presence isn't reachable remotely" — a
    remote seat's presence sidecar IS already reachable today via
    `remote_sweep_script`'s existing `PRES <name> <mtime>` records (see
    `advanced/REMOTE-SEATS.md`). This round deliberately does not wire
    check 1d to the remote channel anyway: doing so would mean re-opening
    the remote-script surface rounds 5-6 spent hardening against RCE, for a
    hard-block gate that (per the signed-source requirement above) would
    need the SAME heavier verified-HEARTBEAT-lookup treatment remotely,
    not presence — a larger, separate piece of work, explicitly out of
    scope for this round. A remote seat's MAJOR mismatch is therefore not
    caught by this gate today; see `advanced/REMOTE-SEATS.md` § Protocol
    Version Handshake (Remote Ceiling) for the accepted ceiling this leaves.
  - **Accepted ceiling — dedup-state pre-seeding (Cipher LOW, round-9).**
    Part B's dedup state file (`protocol-version.<peer>.state`) records the
    LAST alerted `(their-version:my-version)` pair; someone with coord-dir
    write access could pre-seed that file with the CURRENT real mismatch to
    suppress the one legitimate alert for it. This is accepted, not fixed:
    the same write access already lets that actor do far more directly (edit
    `allowed_signers`, mailbox files, or `PROTOCOL-VERSION` itself), Part B
    is advisory-only (nothing it gates is security-relevant — see above),
    and Part D's own hard-block gate does not use this state file at all, so
    pre-seeding it cannot suppress or fabricate a MAJOR-mismatch commit
    block.

---

## Bootstrap Checklist

Run these steps in order when standing up a new dual session.

### Orchestrator

```
[ ] 1. Identify role: cwd = workspace root → ORCHESTRATOR.
[ ] 2. Create <coord-dir>/ if absent.
[ ] 2b. PROTOCOL 1.4.0 — generate + self-enroll the signing key (the TOFU trust
         root; same trust tier as the Orchestrator already being "sole namer,
         collision-free by construction" — see § Message Authenticity below):
           LINE=$(./coord-keygen.sh --generate --identity orchestrator --dir <coord-dir>)
           ./coord-keygen.sh --enroll --identity orchestrator --pubkey-line "$LINE" --dir <coord-dir>
[ ] 3. Write orchestrator.md from ROSTER-template (role=Orchestrator, state=Active).
[ ] 4. M4: read it back — confirm it landed (sandbox filesystem can silently swallow writes).
[ ] 5. Arm coord-monitor.sh via your harness's output→chat bridge
         (see § Arming the inbox above):
         ./coord-monitor.sh --identity orchestrator --dir <coord-dir>
[ ] 6. Start heartbeat.sh in background:
         ./heartbeat.sh --identity orchestrator --role orchestrator --dir <coord-dir>
[ ] 7. PID files are written automatically by the scripts.
         To stop (M2 — kill by PID, never pkill -f):
           kill $(cat <coord-dir>/.watch-state/orchestrator/watcher.pid)
           kill $(cat <coord-dir>/.watch-state/orchestrator/heartbeat.pid)
[ ] 8. Check QUEUE.md: if below depth-floor (>=12 buildable contracts), run the M5 6-lens discovery pass.
[ ] 9. Read all files in <coord-dir>: catch up on any messages since last session.
[ ] 10. Post readiness: HEADS-UP "Orchestrator armed in. Queue depth: <N>."
```

### Implementer

> **No pre-assigned identity?** Use the Identity Bootstrap protocol (§ Identity Bootstrap
> below) to request a name from the Orchestrator before running this checklist —
> `bootstrap-identity.sh --provision` now also generates your signing key and
> embeds it in the HEADS-UP for the Orchestrator to enroll (PROTOCOL 1.4.0).

```
[ ] 1. Identify role: cwd = sub-repo or worktree → IMPLEMENTER.
[ ] 2. Choose identity: impl-<name> (stable, derived from cwd/worktree name — never changes).
         (If no identity pre-known, the Identity Bootstrap section provides the naming handshake.)
[ ] 3. Write <coord-dir>/impl-<name>.md from ROSTER-template (role=Implementer, zone=<cwd>, state=Active).
[ ] 4. M4: read it back — confirm it landed.
[ ] 4b. PROTOCOL 1.4.0 — if this identity was pre-assigned (skipped the Identity
         Bootstrap handshake, so nobody has generated/enrolled a key for it yet),
         generate + hand the pubkey to the Orchestrator to enroll. PROTOCOL 1.5.0
         §3.5 Part A: include your own PROTOCOL-VERSION alongside the pubkey — same
         two-directional exchange as the --provision path, just carried by hand:
           LINE=$(./coord-keygen.sh --generate --identity impl-<name> --dir <coord-dir>)
           MYVER=$(. ./PROTOCOL-VERSION; echo "$PROTOCOL_VERSION")
           # send $LINE and "PROTOCOL-VERSION: $MYVER" to the Orchestrator (HEADS-UP), who runs:
           #   ./coord-keygen.sh --enroll --identity impl-<name> --pubkey-line "$LINE" --dir <coord-dir>
           # and replies with their own PROTOCOL-VERSION (mismatch note if it differs
           # — see § Protocol Version Handshake — never blocks this step either way).
         (If this identity WAS bootstrapped via --provision/--adopt, this already
         happened as part of that handshake — skip.)
[ ] 5. Arm coord-monitor.sh via your harness's output→chat bridge
         (see § Arming the inbox above):
         ./coord-monitor.sh --identity impl-<name> --dir <coord-dir>
[ ] 6. Start heartbeat.sh in background:
         ./heartbeat.sh --identity impl-<name> --role implementer --dir <coord-dir>
[ ] 7. PID files are written automatically by the scripts.
         To stop (M2 — kill by PID, never pkill -f):
           kill $(cat <coord-dir>/.watch-state/impl-<name>/watcher.pid)
           kill $(cat <coord-dir>/.watch-state/impl-<name>/heartbeat.pid)
[ ] 8. Read orchestrator.md in full: catch up on open WOs, decisions, and context.
[ ] 9. Post ACK: "impl-<name> armed in. Zone: <cwd>. Watching <coord-dir>/orchestrator.md."
```

### Re-arm Rules

**PID-ALIVE ≠ agent-alerted (2026-07-17, Implementer #2 deaf-gap incident).** The monitor process consuming messages proves nothing about the AGENT seeing them — each harness needs an output→chat bridge (Claude Code: the `Monitor` tool; Cursor Agent: Shell `notify_on_output` — copy-paste patterns in the workspace CLAUDE.md). Two corollaries: (1) after ANY monitor re-arm, tail-read the peer file across the gap — a fresh baseline never replays what the dead ear missed; (2) the hub verifies a NEW seat's wake path with a live wake-test message before trusting event-driven handoffs to it.


- **Full-read after a gap.** After any watcher re-arm that follows a dead window (session cycle, crash, cap-expiry with a gap), the instance MUST full-read every file in its watch-set before resuming normal operation — the re-armed watcher baselines at current EOF, so gap-window messages are otherwise silently swallowed. A tail-glance is insufficient (mid-file anomalies make the tail misleading).
- **PID refresh on re-arm.** PID refresh is part of the re-arm: every watcher/heartbeat (re)arm updates the presence file's PID fields in the SAME wake-cycle. Stale PIDs make liveness undiagnosable.
- **Watcher dead-man switch (heartbeat.sh v2.1+).** Each cadence tick, the heartbeat verifies its sibling `coord-monitor.sh` process is still alive (60s arm-grace on a fresh `watcher.pid`, PID-reuse guard — the guard also accepts the retired `watch-coordination.sh` for backward compatibility, see `retired/README.md`). Sustained death — `WATCHER_DEAD_TICKS`=3 consecutive failed ticks, ~15 min at the default 300s cadence — trips the alarm: it appends an addressed `⚠️ WATCHER-DOWN` alert to its own file (Orchestrator → ALL, Implementer → orchestrator) and self-terminates with `exit 42` — the only way a backgrounded process can wake a dormant agent session. It never auto-re-arms the watcher (P6). **On `exit 42`: re-arm the watcher FIRST, then the heartbeat** — the heartbeat's own alarm exists precisely because the watcher can't wake anyone by itself. Receiving `⚠️ WATCHER-DOWN` from a peer means that peer's lane inbox is deaf; escalate if it persists past one re-arm.
  Rationale: sustained-death rather than a single-tick check, guarding against a transient `ps` race or momentary scheduler hiccup rather than genuine death — a single failed check should never be treated as proof of trouble. (This design point predates the persistent monitor: it was originally load-bearing for the retired echo-and-terminate watcher, whose `watcher.pid` legitimately pointed at a dead process for most of every wake-cycle. `coord-monitor.sh` is persistent — armed once per session, not re-armed per wake-cycle — so the tolerance now mostly guards against false alarms rather than a structurally-expected dead PID.)
- **Arm once per session, not per wake-cycle.** `coord-monitor.sh` is a persistent, forever-running process armed under the harness's output→chat bridge (Claude Code: `Monitor` tool `persistent:true`; Cursor: Shell + `notify_on_output`) — it is NOT re-armed after each message the way the retired one-shot watcher was. There is no "early-arm for a long wake-cycle" concern under this model: the monitor stays alive continuously through builds, deploys, audits, and long reads with no re-arm timing to manage. Re-arm ONLY when `coord-status.sh` reports the watcher DEAD.

### Network Filesystems / Cross-Machine Seats

`fswatch` (`coord-monitor.sh`'s event-driven receive path) is built on OS-level
filesystem-change notifications — FSEvents on macOS, inotify on Linux. Those
notifications are **local-only**: a peer process running on a *different
machine*, writing onto a coord-dir reached over a network mount (SMB, SSHFS,
NFS), does not generate a local fs-event on your side. `fswatch_loop` will
silently go deaf while still reporting itself armed.

Use `--force-poll` on any seat whose coord-dir is a network mount:

```bash
./coord-monitor.sh --identity impl-alpha --dir <coord-dir> --force-poll --poll 2
```

This skips fswatch entirely (even if it happens to be on `PATH`) and runs the
fixed-interval poll loop from the start. Polling is safe here because delta
detection is size-based (`emit_new` stats and reads the file directly), not
event-based — a plain stat/read sweep behaves identically over a network mount.

Keep `--poll` at 2 seconds or higher on network mounts: SMB/NFS client-side
attribute caching can delay a remote writer's size change from becoming
visible for a few seconds. Treat the effective delivery latency as **low
seconds, not milliseconds**, and don't tighten the poll interval expecting
event-loop-like responsiveness — it won't get faster than the cache TTL allows.

### Tear-down

```
[ ] 1. kill <watcher-pid> && kill <heartbeat-pid>   (M2: targeted kill, never pkill -f).
[ ] 2. Delete own presence file from <coord-dir>/.
[ ] 3. If Orchestrator: post HEADS-UP "Orchestrator going offline. Archive: <archive-path>."
[ ] 4. Archive the mailbox file if it has grown large (see MAILBOX-template.md archiving rules).
```

---

## Identity Bootstrap (DESIGN EXTENSION)

> **Design extension** — not derived from the source project. Adopting projects may
> use pre-assigned identities (as in the Implementer checklist above) when the
> identity is known before the session starts.

The Implementer must watch `orchestrator.md` before it has a name; the Orchestrator
must see the Implementer's presence file before it can assign one. Provisional IDs
break this deadlock. The Orchestrator is the **sole namer** — its assignments are
collision-free by construction.

### Protocol

**Implementer side:**

1. **Provision** — shell-generated ID (never let the model invent it):
   ```bash
   PROV_ID=$(./bootstrap-identity.sh --provision --dir <coord-dir> --zone "$(pwd)")
   ```
   Creates `<coord-dir>/pending-<uuid>.md` with a `🛰️ HEADS-UP → orchestrator`
   requesting name assignment. The new file trips the Orchestrator's watcher.
   PROTOCOL 1.4.0: also generates a signing key for the provisional identity and
   embeds its raw pubkey line in the HEADS-UP body (`pubkey: …`) — this message
   itself stays unsigned (coord-verify.sh's bootstrap exemption covers exactly
   this shape; nothing exists yet to verify it against).

2. **Arm** the monitor under the provisional identity, via your harness's output→chat
   bridge (see § Arming the inbox above):
   ```bash
   ./coord-monitor.sh --identity "$PROV_ID" --dir <coord-dir>
   ```
   Watches `orchestrator.md`; emits when the Orchestrator's reply is addressed to
   `pending-<uuid>` (addressing filter: `→ $PROV_ID —`).

3. **Wait.** The monitor stays armed and emits the ASSIGN-IDENTITY reply the moment
   the Orchestrator posts it — no watcher exit, no separate file Read.

4. **Adopt** the assigned name:
   ```bash
   ./bootstrap-identity.sh --adopt \
     --provisional "$PROV_ID" --assigned impl-alpha --dir <coord-dir>
   ```
   Atomically renames `pending-<uuid>.md → impl-alpha.md` (POSIX `mv`, same dir).
   Prints the provisional-monitor kill command and the re-arm command.
   PROTOCOL 1.4.0: also carries the signing key files over the same rename
   (same key material — the enrolled pubkey from step C already matches).

5. **Kill** the provisional monitor (M2 — by PID, never `pkill -f`) and **re-arm**
   under the adopted identity:
   ```bash
   kill $(cat <coord-dir>/.watch-state/$PROV_ID/watcher.pid)
   ./coord-monitor.sh --identity impl-alpha --dir <coord-dir>
   ```

6. **Post ACK** in `impl-alpha.md → orchestrator`: "Identity adopted. Armed in as impl-alpha."

**Orchestrator side (after the provisional file appears):**

A. Read `pending-<uuid>.md` — the HEADS-UP names the requester and its zone.
B. Pick a friendly unique name (`impl-alpha`, `impl-beta`, …). Unique = no existing
   `<name>.md` file in `<coord-dir>/` at the time of assignment.
C. PROTOCOL 1.4.0: enroll the pubkey from the HEADS-UP body under the **assigned**
   name (not the provisional one) — naming and key-trust land in one round trip:
   ```bash
   ./coord-keygen.sh --enroll --identity impl-alpha --pubkey-line "<pubkey: line from the HEADS-UP>" --dir <coord-dir>
   ```
D. Reply in `orchestrator.md` with `🤝 ASSIGN-IDENTITY` addressed to `pending-<uuid>`.
   **PROTOCOL 1.5.0 §3.5 Part A:** carry your own `PROTOCOL-VERSION` back —
   this exchange is two-directional (the newborn already announced its own
   in the HEADS-UP body). If it differs from the newborn's, say so plainly
   in one line, using the SAME wording `coord-presence.sh`'s
   `protocol_mismatch_message()` produces (severity + remediation — see
   § Protocol Version Handshake below) — never hand-write a different
   phrasing that could drift from what the automated re-arm-time check
   (Part B) says for the same mismatch. **Never block adoption over a
   version difference alone** — enrollment proceeds exactly as it would on
   a match.
   ```
   ### <UTC> — orchestrator → pending-<uuid> — 🤝 ASSIGN-IDENTITY

   You are: impl-alpha
   Unique in <coord-dir>/ at time of assignment.
   Pubkey enrolled under impl-alpha (PROTOCOL 1.4.0).
   PROTOCOL-VERSION: <own current version, e.g. $MYVER from step 4b — never hand-type a literal, it goes stale at the next bump>
   Adopt: bootstrap-identity.sh --adopt. Re-arm watcher. Reply with ACK.
   ```
   If versions differ, append the mismatch note (example — MINOR/PATCH shown;
   see § Protocol Version Handshake for the MAJOR wording, which additionally
   states this will block hub commits):
   ```
   PROTOCOL-VERSION mismatch: pending-<uuid> is running 1.4.0; orchestrator is running 1.5.0.
   Severity: MINOR/PATCH — additive/backward-compatible or non-semantic. No functional break; upgrade at your convenience, this is advisory only.
   If you share a repo checkout with the other side (the common, zero-cost case): git pull the coordination-protocol, then re-arm your watcher/heartbeat. If this is instead a cross-repo/remote-seat topology, ask your Orchestrator/human where the canonical framework repo lives (set COORD_CANONICAL_SOURCE to point at it directly next time).
   This is a pointer, not a payload — no file content, diff, or script is embedded here.
   ```
   This reply itself may read UNVERIFIED under `coord-verify.sh --strict` — it is
   the second bootstrap-exempt shape (FROM orchestrator, TAG ASSIGN-IDENTITY);
   see coord-verify.sh's header comment for exactly why.

E. **PREREQUISITE for `--strict` (2026-08-09 round-3 — Rook), do this once per
   adopt, not optional:** commit the coord-dir's mailbox files, including the
   just-adopted `<name>.md`. The `--adopt` rename in step 4 never rewrites
   message content, so `<name>.md` permanently carries the newborn's own
   `🛰️ HEADS-UP` with `FROM=pending-<uuid>` inside a file now named
   `<name>.md` — legitimate (correctly non-exempt-but-not-INVALID under the
   two-tier structural check in § Message Authenticity), but a hard
   `⚠️ UNVERIFIED` block under `--strict` for as long as it's never
   git-anchored past. The Orchestrator's inbox is every peer file, so an
   un-committed coord-dir means this one fully-honest message blocks every
   future Orchestrator commit, forever, with remedy text that reads like a
   tamper signal. If this coord-dir is never committed as a matter of normal
   operation, `--strict` verifies the newborn's whole file every run instead
   (the safe default — see § Hard-block's Scope paragraph) and this step is
   moot; if it IS committed, this step is what actually clears the block.

### Optional: restart stability

Persist the assigned name in a dotfile in the worktree (e.g., `.samantha-identity`).
On restart, read it and skip the handshake — register directly as the known name:

```bash
if [[ -f .samantha-identity ]]; then
  IDENTITY=$(cat .samantha-identity)
  # Use $IDENTITY in the normal Implementer checklist — skip the bootstrap.
fi
```

The Orchestrator accepts direct re-registration without re-assigning.

### Edge cases

| Scenario | Outcome |
|----------|---------|
| Two newborns arm simultaneously | UUID provisional IDs are unique — no collision. Orchestrator names them sequentially. |
| Orchestrator offline at provision time | `pending-<uuid>.md` waits in the dir. Orchestrator auto-discovers it on wakeup. |
| Provisioned but never adopted | `pending-<uuid>.md` stays in the dir. Teardown: delete it; kill the provisional watcher by PID. |

---

## The 6 Disaster Rules

These are the rules whose violation causes the most common coordination failures. Non-negotiable.

**Rule 1 — Commit only explicit paths. Never `git add -A` or `git add .` in a shared tree.**

> **MULTI-SEAT push discipline (ratified 2026-07-17, unanimous):** fetch origin <branch> -> no-divergence (origin is ancestor of HEAD) -> plain push; DIVERGED -> STOP + hub-coordinate, never rebase over a sibling's dirty tree. **NEVER pull --rebase --autostash** with two implementers -- autostash swallows the SIBLING's uncommitted work, and a mid-rebase churns it (near-miss 2026-07-17, WIP recovered). The rebase-refuses-a-dirty-tree behavior is the safe signal --autostash bypasses.
Staging everything silently includes in-flight artifacts from a concurrent implementer's zone.

**Rule 2 — Bracket shared-runtime changes in a DEPLOY WINDOW.**
Before touching a shared runtime: post `DEPLOY-WINDOW OPEN`. After: post `DEPLOY-WINDOW CLOSED`. Others wait for the CLOSED signal before committing to the same service.

> **Hub-mediated (STAR topology):** In a star topology, spokes watch *only* the Orchestrator's file — a message posted to an Implementer's own file is invisible to sibling Implementers. Deploy windows MUST therefore be hub-mediated:
> - An **Implementer** that needs a window posts a `DEPLOY-WINDOW REQUEST` to the Orchestrator (`→ orchestrator`). It does NOT post OPEN to its own file.
> - The **Orchestrator** broadcasts `🔧 DEPLOY-WINDOW OPEN → ALL` on its own file (every spoke sees it), waits for ACKs from active instances, performs or authorizes the shared-runtime change, then broadcasts `✅ DEPLOY-WINDOW CLOSED → ALL`.
> - The Orchestrator may open a window directly (without a prior request) when it initiates the change itself.
> Only the Orchestrator opens and closes windows on the shared channel. Spokes request; the hub broadcasts.

> **Transport clause (ratified 2026-07-16, unanimous — after the DOCKPROX hot-sync incident):** the window covers **every mechanism that changes the shared runtime's executing code or schema** — restart, migration, scp/rsync onto a bind-mount, hot-reload pickup, exec-patching — regardless of how non-disruptive the transport feels. The sole carve-out is frontend HMR in your exclusive lane (HEADS-UP class). If the shared runtime will EXECUTE different code afterward, it needs the window — and gates+commit come first. Live-host proofs never belong in a worker's own definition-of-done; live proof happens AT the sanctioned window.

**Rule 3 — Stay in your lane. Announce before crossing; wait for ACK.**
Need to touch another instance's zone? Post a HEADS-UP, get an explicit ACK, then proceed. No silent cross-zone edits, ever.

**Rule 4 — Read your mailbox before any commit, push, or deploy.**
A message addressed to you may contain a decision that changes what you are about to do. The PreToolUse hook (coordination-precommit-hook.sh) enforces this mechanically.

**Rule 5 — Public docs only. No secrets in any mailbox.**
The mailbox files are version-controlled. Never post credentials, tokens, internal paths, or PII. Treat every message as already public.

**Rule 6 — A hot-deploy is committed code. (Ratified 2026-07-16, unanimous.)**
Every scp / bind-mount / HMR hot-deploy to a shared runtime acquires a scoped commit **before the session ends — no exceptions**; the working tree is never the only home of live code. Cadence: commit per deploy-batch once the batch is feature-coherent. A batch mid-refinement (the human actively iterating on that exact surface) MAY defer consolidation to burst-end — never past session end — and the deferral is declared with a one-line `🛰️ HEADS-UP` so the hub knows live>git divergence exists at that moment.
> Origin incident: the 2026-07-15/16 SOLO burst left ~65 live-deployed files — including an applied DB migration — existing only in a working tree. Amendment rationale: committing a mid-refinement intermediate forces a supersede + double-flag; feature-coherence gates the per-batch commit, session-end gates everything.

---

## Robustness Amendments (PROTOCOL-VERSION 1.1.0)

The 6 Rules cover the *destructive* failures — a clobbered tree, a mid-flight restart. This section covers the *quiet* ones: a claim that was never true, a gate nobody flagged, a status doc that decayed while reading identically, a queue that starved while both watchdogs reported healthy. Every item below is derived from an observed incident in a live deployment, not a hypothetical.

**The organizing principle is silent-vs-noisy, not mechanical-vs-written.** A rule whose violation is *noisy* — an atomic-write split that leaves a visibly dangling reference, self-announced and corrected in seconds — does not need a script; the failure announces itself. A rule whose violation is *silent* — a prose claim that reads identically to a verified one — is high-risk no matter how firmly it is written down, and needs a mechanism. Spend mechanization on the silent ones.

### Evidence discipline
Full rule in MAILBOX-template.md § Rules: any assertion about an external artifact pastes freshly-fetched, tool-output-shaped evidence, fetched in the same action as the claim; negative claims ("still untouched") included; fetch-and-log is one atomic action. Mechanized (presence, not truth) by `coord-evidence-lint.sh`.

### Queue hygiene
Full rule in QUEUE-template.md § Row-Hygiene Columns: `gated` / `schema` / `verified-against` columns, three compounding gate kinds, checked `depends-on`, banner-the-superseded-queue-file. Mechanized by `coord-gate-audit.sh` and the `coord-status.sh` metrics block.

### Fail closed at the point of action
Making *queue rows* legible does nothing about a gated action that was never a queue row. A seat that never touches the queue can push straight to a gated target — and did: a canonical ruling published to an auto-deploying public docs site with no sign-off, as a direct git push. **If the deployment has a gated target — a public/auto-deploying doc repo, canonical numbers, an ADR-Accepted marker, a safety-list surface — the check belongs at the push, not in the queue.** `coordination-precommit-hook.sh` BLOCKS (not warns) such a push unless the commit message or an accompanying coord entry carries an explicit authorization reference (`COORD_GATED_REMOTE_PATTERN` / `COORD_GATED_PATH_PATTERN`; no-op when unset).

> **Ceiling, stated so it isn't over-trusted:** the authorization reference is actor-written and carries the same fabrication surface as any other claim. This does not stop a determined liar. What it buys is real but partial: the original failure was conflating *"I was told to decide"* with *"I was told to publish"*, and the hook forces that conflation into an explicit, auditable assertion at the moment of action instead of a retroactive narrative.

Same shape, different surface: **`gh pr merge` never runs un-gated on a protected base.** Check `mergeable`/`mergeStateStatus` first; prefer `--auto` over `--admin`; `--admin` requires an explicit named reason in the coord log.

### Remediation of an unauthorized gated action
Codified in advance, because improvising it under pressure is how a bad hour becomes a bad day:
- **Forward-correction only — never a history rewrite.**
- **It does not un-publish.** Auto-deployed content may already be cached, mirrored, or indexed elsewhere. Say so; don't imply erasure.
- **Issuing the remediation is itself a gated action**, logged as one — never folded silently into the original mistake's own cleanup.

### The third clock
The monitor/heartbeat pair is a *mutual* monitor: each proves the other's process is alive. Neither can observe "both alive, session quiet, nobody answering." That needs a clock **outside the pair** — `coord-session-healthcheck.sh`, run from cron/launchd, not inside a live session.

Key it correctly or it becomes wallpaper: the trigger is absence of coord-dir activity **AND** absence of any observable work product (no new commits, no worktree mtime change) over the window — not coord-dir silence alone. A healthy seat mid-build is *supposed* to be quiet on the mailbox; alarming on that trains every seat to ignore the alarm.

### Status-doc decay
A status claim about code decays the moment the code changes, and a stale claim is byte-identical to a fresh one. Two mechanisms, each covering the other's blind spot:
- **(a) Reverse-index at commit time.** Build `path → [status docs citing it]` from citations already present in canon; the precommit hook prints, per committed path, which docs cite it. Advisory, never blocking. **Cap the output** — a wide commit (rename sweep, promotion slice) could print a screenful, and a hook that prints a screenful gets scrolled past. Summarize (`N docs cite paths in this commit: <top 3> … +N more`) with a pointer to the full list.
- **(b) `verified-against: <sha>` on status claims generally**, making staleness *measurable* (`git log <sha>..HEAD -- <paths>`) rather than binary.
- Not redundant: (b) can be stamped without the check ever running. (a) fires off git's actual changed-path list, which nobody authors, so an unstamped-but-touched doc is conspicuous regardless of anyone's honesty.
- Consequence for the 6-lens pass: drive Lens 2 from the reverse index (only docs whose cited paths moved), not a broad periodic re-read.

### Amendment durability — the meta-item
This is the item that keeps the others from lapsing. **A fix for one of these exact problems already existed once, and quietly lapsed unenforced — nobody noticed until the failure repeated.** A rule that lives only in a mailbox thread will scroll out of the archive-hygiene window and cease to exist.

- **Every rule adopted from a coordination incident gets a durable home** in this reference pack or the project's CLAUDE.md — never only in a mailbox thread.
- **Version the protocol** — the `PROTOCOL-VERSION` stamp at the top of this file, bumped on every ratified amendment, so a stale cached understanding is falsifiable against a *number* instead of prose-diffed.
- **Track ratified-but-unbuilt items** in `PROTOCOL-AMENDMENTS.tsv` (see `PROTOCOL-AMENDMENTS.tsv.example`). `coord-status.sh` prints the version stamp plus the count of ratified-but-unimplemented items — so "we adopted a rule and never built it" is visible at the one moment every seat reliably looks. Without this, amendment durability is only a promise to remember, which is exactly the failure it names.

> **Canon-versioning caveat.** Check whether the file that *defines* your protocol is itself under version control. The scripts that enforce a protocol usually live in a git repo; a project-root `CLAUDE.md` frequently does not — leaving the definition as the one unversioned link in an otherwise-auditable chain. Until it is versioned: take a timestamped copy before each edit, and scope any cross-lane review of a change explicitly to the touched region, re-read after the fact rather than assumed to cover the whole file.

---

## M5 — 6-Lens Discovery Pass (Orchestrator's Standing Duty)

Run this when idle and the queue is below the depth floor (>=12 buildable contracts). Each lens finds a class of work the others miss. Together they cover the full surface.

| Lens | What to look for | Output |
|------|----------------|--------|
| **1. Features to build** | Items in backlog or spec not yet started | New WOs |
| **2. Code-vs-canon divergence** | Code contradicting a hub doc, ADR, or settled spec | WOs + DECISION entries for canon-edge cases |
| **3. Defined-but-unwired** | Functions declared but never called; hooks registered but never triggered | Cleanup or integration WOs |
| **4. Cleanup/removal** | Dead code, deprecated paths, orphaned files, stale migrations | Cleanup WOs |
| **5. Doc/canon gaps + design flaws** | Systems with no hub doc; ADRs without follow-up; spec sections marked OPEN | WOs for doc work + DECISION entries |
| **6. ADR rollup** | Resolved DECISION items not yet promoted to ADRs; ADRs not yet folded into canon | ADR WOs |

Post discovered WOs directly to QUEUE.md. Work within canon autonomously; canon-edge discoveries log a DECISION entry first and build the unambiguous kernel.

---

## Protocol Ratification

A protocol change ships only on **unanimous active-member ratification** (Orchestrator + all live Implementers). No member — Orchestrator included — changes the shared protocol unilaterally.

Procedure:
1. Any member proposes via `PROCESS-NOTE` message.
2. **This obliges the Orchestrator to a full end-to-end protocol review** — reciprocity: match the proposer's investment, hunt further improvements beyond the one proposed.
3. Unanimous agreement among active members → change ships. Orchestrator authors and commits the update.
4. Members offline at ratification inherit the change on bootstrap; they may re-propose if they disagree.
5. No unanimity → escalate to the human as tiebreaker.

The Orchestrator is the **sole author and committer** of protocol documents. Implementers propose only.

**On ratification:** bump `PROTOCOL-VERSION` at the top of this file, give the amendment a durable home here (not only in the mailbox thread that carried it), and add a row per item to `PROTOCOL-AMENDMENTS.tsv` with its build status — so the gap between "ratified" and "actually built" stays a visible number rather than an assumption. An amendment that is half judgment-based and half mechanical is normal; the judgment half ships with the prose, and the mechanical half is tracked as build work rather than treated as already honored by discipline.

**Cross-lane validation.** Protocol authoring is the Orchestrator's lane, but a change to it should get a validation pass from an Implementer before it is treated as canonical — not as a ratification gate, as a quality one: the hub does not have the spoke's lived experience of these mechanics, and a gate that feels airtight from the hub routinely misses what the spoke hits daily. In practice this has been worth it every time — the validation passes that produced *this* amendment returned substantive revisions, not rubber-stamps, on both rounds.

---

## Proving Standard

Build/test passing is necessary, not sufficient — it cannot see runtime behavior, migrations, or content fidelity. For **lossless/migration WOs**, traceability matrices are CLAIMS, not proof:
- The Implementer's per-wave review must sample source-vs-target SUBSTANCE for "migrated" rows — not just structure, links, and builds.
- The Orchestrator must run an independent adversarial source-vs-target audit before marking DONE.
- Recurring loss shapes to hunt: enumerations "preserved by reference" into archive-bound files; deferral ping-pong between waves; parameter/prosody/choreography tables summarized into prose.

Lossless-mandate WOs inherit this proving standard automatically (see WORK-ORDER-template.md).

---

## Key Files

| File | Purpose |
|------|---------|
| `PROTOCOL-VERSION` | Single stamp shared by docs + scripts (`PROTOCOL_VERSION=…`) — bump on every amendment |
| `coord-address-filter.sh` | Project-scope helpers (`spoke_filter_delta`, `protocol_project_of_identity`, …) |
| `coord-presence.sh` | `.presence/<id>` sidecar read/write (Phase 4). PROTOCOL 1.5.0: also carries the shared Protocol Version Handshake helpers (`protocol_version_major`/`protocol_mismatch_severity`/`protocol_mismatch_message`) — see § Protocol Version Handshake |
| `IDLE-SCHEDULE-template.md` | Per-seat idle activity schedule for `heartbeat --schedule-file` |
| `SOLO.md` | Solo protocol stub |
| `advanced/MULTI-ORCHESTRATOR.md` | Design memo only — multi-hub options |
| `coord-monitor.sh` | Persistent STAR monitor — project watch/filter (1.3.0); presence sidecar PID write; PROTOCOL stamp on arm. Remote channel (`--remote-host`): ssh-fetch-verify-annotate on arrival + auto-writes `<coord-dir>/.remote-channels` on arm — see `advanced/REMOTE-SEATS.md` § Message Authenticity. PROTOCOL 1.5.0: LOCAL-channel arm also checks each known peer's presence `protocol_version` against its own and posts a deduped `⚠️ PROTOCOL-VERSION-MISMATCH` alert on a genuine mismatch — see § Protocol Version Handshake |
| `coord-send.sh` | The publish half of the coordination chat-room — auto-fills timestamp/identity/header, appends atomically to your own outbox, reads the append back to verify it landed; named args `--to`/`--tag`/`--subject`/`--body`/`--body-file`. `--remote-seat`/`COORD_REMOTE_SEAT=1` (MANDATORY-EXPLICIT): skips the local enrollment readback-verify for a bus dir with no local `allowed_signers` by design — see `advanced/REMOTE-SEATS.md` § Message Authenticity |
| `coord-status.sh` | Read-only liveness — local (+ remote) watcher pidfiles and heartbeat; ALL-CHANNELS aware; portable coord-dir default |
| `heartbeat.sh` | IDLE-KICK (`--idle-policy`) + Orchestrator discover-on-idle (folded into IDLE-KICK body) + HOLD-DAMP-V2 + `--weak-seat` + ALL-CHANNELS watcher dead-man (`exit 42`); portable `--dir`. PROTOCOL 1.5.0: routine `HEARTBEAT` append embeds `PROTOCOL-VERSION` — the signed source `coordination-precommit-hook.sh`'s protocol-version gate reads (round-9) — see § Protocol Version Handshake |
| `coord-protocol-metrics.sh` | Shared helpers sourced by `coord-status.sh` / `heartbeat.sh` — queue depth per queue file, `PROTOCOL-VERSION` stamp, ratified-but-unimplemented amendment count, migration-chain state. Standalone-runnable for a one-shot dump |
| `coord-session-healthcheck.sh` | The third clock — session-external (cron/launchd). Alerts only when BOTH no coord-dir write AND no commit/worktree touch over `--window`; repeatable `--repo` (no default project paths) |
| `coord-evidence-lint.sh` | Evidence-presence lint for mailboxes — flags a completion/state claim with no adjacent output-shaped evidence. Ceiling: presence, not truth |
| `coord-gate-audit.sh` | Mechanical gate-audit for queue rows — checks all three gate kinds (code-comment marker, canon-prose provisional, safety-list keyword) across cited code and canon paths; marker/ACL-exclusion/safety patterns all overridable; lists every gate found, never stops at the first |
| `PROTOCOL-AMENDMENTS.tsv.example` | Template for the ratified-amendment tracker that feeds the amendment-debt count |
| `6-lens-audit.md` | M5: 6-lens discovery methodology — when to run, all six lenses with what to look for, output format |
| `MAILBOX-template.md` | Message grammar, tag types, atomic-write rules, archive hygiene |
| `WORK-ORDER-template.md` | WO format (full + one-liner tiers) and STATUS reply |
| `ROSTER-template.md` | Presence file schema (M9 richer fields); registration and deregistration |
| `QUEUE-template.md` | Claimable queue, three-bucket SSOT, depth-floor, push-assignment rules; in multi-project deployments, instantiate one queue per downstream repo (`queue-<repo>.md`) — see § Multi-project coordination |
| `coordination-precommit-hook.sh` | PreToolUse hook for git commit-landing verbs (`commit`/`merge`/`cherry-pick`/`rebase`/`am`/`revert`/`pull`) and `push`: mailbox-read gate (Rule 4), dangerous-verb warning (`add -A`/`add .`/`commit -a`), non-blocking secret-scan, git-anchored sig-verify (`COORD_REMOTE_SEAT_HOOK=1` explicit escape for a remote seat running this hook against its own bus-dir-as-coord-dir), `allowed_signers` write gate, remote-channel sig-verify (reads `.remote-channels`; every remote value goes through `coord-remote-verify.sh`'s `coord_remote_shquote` before being spliced into an ssh command — round-5, 2026-08-09, closed a live-demonstrated RCE; always prints which channel(s) it checked, even zero, and fails closed on an unreachable host or a live remote watcher with no configured channel — see `advanced/REMOTE-SEATS.md` § Round-5 hardening), PROTOCOL 1.5.0 protocol-version MAJOR-mismatch gate (FAIL on a peer's MAJOR version, sourced from their own signed+verified HEARTBEAT and enumerated via `allowed_signers` — round-9 hardened against presence forgery — differing from this seat's own; MINOR/PATCH never block, see § Protocol Version Handshake); supports both the Claude Code JSON-stdin tool-input protocol and the Cursor `beforeShellExecution` allow/deny contract. Bash-command-text matcher, not a real git hook — see § Hard-block for the stated ceiling |
| `retired/` | Tombstones only — retired watcher/hook **scripts were deleted** (git history retains bodies). See `retired/README.md`. Do not resurrect. |
| `bootstrap-identity.sh` | DESIGN EXTENSION: provisional-ID generation (`--provision`) and identity adoption (`--adopt`) for the naming handshake; see § Identity Bootstrap. PROTOCOL 1.4.0: also generates/embeds and carries over the signing key. PROTOCOL 1.5.0: HEADS-UP also embeds `PROTOCOL-VERSION` alongside the pubkey — see § Protocol Version Handshake. |
| `coord-keygen.sh` | PROTOCOL 1.4.0: SSH signing-key lifecycle — `--generate`/`--enroll`/`--rotate`/`--fingerprint`. Sourceable (key-path helpers only) by `coord-send.sh` / `bootstrap-identity.sh`. See § Message Authenticity (SSH signing) |
| `coord-verify.sh` | PROTOCOL 1.4.0: verifies mailbox message signatures against `allowed_signers` — `--tail`/`--since-line`/`--strict`/`--find-boundary`/`--extract-field`/`--tail-verified`; the three exemptions are documented in its own header comment. `--tail-verified N` (round-12, 2026-08-10) selects its window from CLASSIFIED content — the last N spans that actually verify — rather than a raw line count, so unsigned padding cannot evict a real claim; classifying that window has unbounded worst-case cost relative to file size, an accepted characteristic (no cap — see § Protocol Version Handshake, Part D) |
| `coord-remote-verify.sh` | PROTOCOL 1.4.0 remote-seat extension: shared `verify_remote_buffer` helper — writes an ssh-fetched buffer to a correctly-named local temp file and runs `coord-verify.sh` against it with `--dir` pointed at the hub's own local `allowed_signers`. Also carries `coord_remote_shquote` (round-5, 2026-08-09): POSIX single-quote escaping for any value spliced into a remote ssh command string — a HARD dependency for `coord-monitor.sh --remote-host` (refuses to arm without it) after a live-demonstrated command-injection finding via an unescaped remote filename. Sourced by both `coord-monitor.sh`'s remote channel and `coordination-precommit-hook.sh`. See `advanced/REMOTE-SEATS.md` § Message Authenticity |
| `allowed_signers` | PROTOCOL 1.4.0: the trust root — OpenSSH allowed_signers format, one line per identity's public key. Orchestrator-only single-writer (same pattern as `QUEUE.md`, M7). Committed/shared — public keys only, Rule-5-safe |
| `advanced/sqlite-mcp.README.md` | Optional advanced path: SQLite(WAL) + stdio-MCP for atomic claim (M6) — design sketch; align to persistent `coord-monitor.sh`, not the retired one-shot watcher |
| `advanced/REMOTE-SEATS.md` | Optional remote ssh bus: second hub monitor, `watcher-remote.pid`, weak-seat idle policy; `--remote-host` requires `--remote-bus-dir` (no baked paths) |
| `advanced/COMPONENT-OWNERSHIP.md` | DESIGN EXTENSION, not yet framework-ratified: per-seat component assignment on multi-seat repos, mandatory claim-marker to prevent duplicate-claim races, idleness-AND-gated escalation teeth. Verify against your own deployment before trusting the accountability mechanics as-is — see the file's own Status note. |
