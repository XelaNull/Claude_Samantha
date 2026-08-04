# Coordination Protocol — Orchestrator–Implementer

PROTOCOL-VERSION: 1.2.0

> **Versioning:** bump `PROTOCOL-VERSION` on every ratified amendment.
>
> **1.2.0** (2026-08-03) — Backport of live dual-suite extensions into the portable pack:
> IDLE-KICK (own-file self-nudge; distinct from orchestrator discover-on-idle) · `--idle-policy` ·
> HOLD-DAMP-V2 · `--weak-seat` · `--role` + STAR excludes for `PROJECTS.md` / `queue-*.md` ·
> optional remote ssh bus (`advanced/REMOTE-SEATS.md`; `--remote-host` requires `--remote-bus-dir`;
> no baked host/bus paths). Live deployment overlays (e.g. Nebuspace `.claude/`) may still carry
> site defaults — do not blind-overwrite them from this pack without a per-file newer check.

The file-based protocol for **dual-mode** operation: Samantha (Orchestrator) coordinating one or more Monk peer instances (Implementers) through shared files when two Claude Code processes must work in parallel.

---

## When to use this (Mode B threshold)

Dual mode is **human-initiated** and only warranted when ANY of:
1. Work must survive a crash, compaction, or session restart.
2. A durable, human-auditable work-order trail is required.
3. The task exceeds one context window and must be partitioned across processes.
4. Two genuinely concurrent live workstreams a human watches in parallel.

Otherwise: **stay in solo mode** (background subagents via `run_in_background`). Solo dominates within one context budget.

**Solo installs:** keep this pack as reference documentation only. Do **not** copy or arm the coordination scripts.

---

## Script tiers (what to copy)

| Tier | Scripts | Who |
|------|---------|-----|
| **Required (dual)** | `coord-monitor.sh` · `coord-send.sh` · `coord-status.sh` · `heartbeat.sh` · `bootstrap-identity.sh` · `coordination-precommit-hook.sh` | Every dual workspace root |
| **Optional (PROTOCOL 1.1.0)** | `coord-protocol-metrics.sh` · `coord-session-healthcheck.sh` · `coord-evidence-lint.sh` · `coord-gate-audit.sh` (+ `PROTOCOL-AMENDMENTS.tsv`) | Dual sites adopting the robustness amendment |
| **Optional (PROTOCOL 1.2.0)** | Remote ssh bus — same `coord-monitor`/`heartbeat` binaries with `--remote-host` + `--remote-bus-dir`; see `advanced/REMOTE-SEATS.md` | Dual sites with off-box Implementers |
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
- **Each Implementer (spoke)** watches ONLY the Orchestrator's file (its inbox for orders and decisions).
- No spoke-to-spoke watching. No self-watching. Self-filter is structural, not conditional.
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

## Bootstrap Checklist

Run these steps in order when standing up a new dual session.

### Orchestrator

```
[ ] 1. Identify role: cwd = workspace root → ORCHESTRATOR.
[ ] 2. Create <coord-dir>/ if absent.
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
> below) to request a name from the Orchestrator before running this checklist.

```
[ ] 1. Identify role: cwd = sub-repo or worktree → IMPLEMENTER.
[ ] 2. Choose identity: impl-<name> (stable, derived from cwd/worktree name — never changes).
         (If no identity pre-known, the Identity Bootstrap section provides the naming handshake.)
[ ] 3. Write <coord-dir>/impl-<name>.md from ROSTER-template (role=Implementer, zone=<cwd>, state=Active).
[ ] 4. M4: read it back — confirm it landed.
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
C. Reply in `orchestrator.md` with `🤝 ASSIGN-IDENTITY` addressed to `pending-<uuid>`:
   ```
   ### <UTC> — orchestrator → pending-<uuid> — 🤝 ASSIGN-IDENTITY

   You are: impl-alpha
   Unique in <coord-dir>/ at time of assignment.
   Adopt: bootstrap-identity.sh --adopt. Re-arm watcher. Reply with ACK.
   ```

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
| `coord-monitor.sh` | Persistent STAR monitor — local + optional remote ssh channel (`--remote-host` **requires** `--remote-bus-dir`); `--role`; excludes `QUEUE.md` / `PROJECTS.md` / `queue-*.md` / archives; own-file IDLE-KICK nudge (`emit_own_idle_kick`); `--force-poll` for network mounts; portable `DIR=${COORD_DIR:-$PWD/.samantha/coord}` |
| `coord-send.sh` | The publish half of the coordination chat-room — auto-fills timestamp/identity/header, appends atomically to your own outbox, reads the append back to verify it landed; named args `--to`/`--tag`/`--subject`/`--body`/`--body-file` |
| `coord-status.sh` | Read-only liveness — local (+ remote) watcher pidfiles and heartbeat; ALL-CHANNELS aware; portable coord-dir default |
| `heartbeat.sh` | IDLE-KICK (`--idle-policy`) + Orchestrator discover-on-idle (folded into IDLE-KICK body) + HOLD-DAMP-V2 + `--weak-seat` + ALL-CHANNELS watcher dead-man (`exit 42`); portable `--dir` |
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
| `coordination-precommit-hook.sh` | PreToolUse hook for `git commit`/`push`/`rebase`: mailbox-read gate (Rule 4), dangerous-verb warning (`add -A`/`add .`/`commit -a`), non-blocking secret-scan; supports both the Claude Code JSON-stdin tool-input protocol and the Cursor `beforeShellExecution` allow/deny contract |
| `retired/` | Tombstones only — retired watcher/hook **scripts were deleted** (git history retains bodies). See `retired/README.md`. Do not resurrect. |
| `bootstrap-identity.sh` | DESIGN EXTENSION: provisional-ID generation (`--provision`) and identity adoption (`--adopt`) for the naming handshake; see § Identity Bootstrap |
| `advanced/sqlite-mcp.README.md` | Optional advanced path: SQLite(WAL) + stdio-MCP for atomic claim (M6) — design sketch; align to persistent `coord-monitor.sh`, not the retired one-shot watcher |
| `advanced/REMOTE-SEATS.md` | Optional remote ssh bus: second hub monitor, `watcher-remote.pid`, weak-seat idle policy; `--remote-host` requires `--remote-bus-dir` (no baked paths) |
| `advanced/COMPONENT-OWNERSHIP.md` | DESIGN EXTENSION, not yet framework-ratified: per-seat component assignment on multi-seat repos, mandatory claim-marker to prevent duplicate-claim races, idleness-AND-gated escalation teeth. Verify against your own deployment before trusting the accountability mechanics as-is — see the file's own Status note. |
