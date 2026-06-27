# Coordination Protocol — Orchestrator–Implementer

The file-based protocol for **dual-mode** operation: Samantha (Orchestrator) coordinating one or more Monk peer instances (Implementers) through shared files when two Claude Code processes must work in parallel.

---

## When to use this (Mode B threshold)

Dual mode is **human-initiated** and only warranted when ANY of:
1. Work must survive a crash, compaction, or session restart.
2. A durable, human-auditable work-order trail is required.
3. The task exceeds one context window and must be partitioned across processes.
4. Two genuinely concurrent live workstreams a human watches in parallel.

Otherwise: **stay in solo mode** (background subagents via `run_in_background`). Solo dominates within one context budget.

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
- **Each Implementer (spoke)** watches ONLY the Orchestrator's file (its inbox for orders and decisions).
- No spoke-to-spoke watching. No self-watching. Self-filter is structural, not conditional.
- The directory's live contents **are** the roster — dynamic, self-populating, no hand-maintained static list.

---

## Bootstrap Checklist

Run these steps in order when standing up a new dual session.

### Orchestrator

```
[ ] 1. Identify role: cwd = workspace root → ORCHESTRATOR.
[ ] 2. Create <coord-dir>/ if absent.
[ ] 3. Write orchestrator.md from ROSTER-template (role=Orchestrator, state=Active).
[ ] 4. M4: read it back — confirm it landed (sandbox filesystem can silently swallow writes).
[ ] 5. Start watch-coordination.sh in background (Bash tool run_in_background):
         ./watch-coordination.sh --identity orchestrator --role orchestrator --dir <coord-dir>
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
[ ] 5. Start watch-coordination.sh in background (Bash tool run_in_background):
         ./watch-coordination.sh --identity impl-<name> --role implementer --dir <coord-dir>
[ ] 6. Start heartbeat.sh in background:
         ./heartbeat.sh --identity impl-<name> --role implementer --dir <coord-dir>
[ ] 7. PID files are written automatically by the scripts.
         To stop (M2 — kill by PID, never pkill -f):
           kill $(cat <coord-dir>/.watch-state/impl-<name>/watcher.pid)
           kill $(cat <coord-dir>/.watch-state/impl-<name>/heartbeat.pid)
[ ] 8. Read orchestrator.md in full: catch up on open WOs, decisions, and context.
[ ] 9. Post ACK: "impl-<name> armed in. Zone: <cwd>. Watching <coord-dir>/orchestrator.md."
```

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

2. **Arm** the watcher under the provisional identity:
   ```bash
   # Bash tool — run_in_background=true
   ./watch-coordination.sh --identity "$PROV_ID" --role implementer --dir <coord-dir>
   ```
   Watches `orchestrator.md`; fires when the Orchestrator's reply is addressed to
   `pending-<uuid>` (addressing filter: `→ $PROV_ID —`).

3. **Wait.** The watcher exits and prints the ASSIGN-IDENTITY reply.

4. **Adopt** the assigned name:
   ```bash
   ./bootstrap-identity.sh --adopt \
     --provisional "$PROV_ID" --assigned impl-alpha --dir <coord-dir>
   ```
   Atomically renames `pending-<uuid>.md → impl-alpha.md` (POSIX `mv`, same dir).
   Prints the provisional-watcher kill command and the re-arm command.

5. **Kill** provisional watcher (M2 — by PID, never `pkill -f`) and **re-arm**:
   ```bash
   kill $(cat <coord-dir>/.watch-state/$PROV_ID/watcher.pid)
   ./watch-coordination.sh --identity impl-alpha --role implementer --dir <coord-dir>
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

## The 5 Disaster Rules

These are the rules whose violation causes the 5 most common coordination failures. Non-negotiable.

**Rule 1 — Commit only explicit paths. Never `git add -A` or `git add .` in a shared tree.**
Staging everything silently includes in-flight artifacts from a concurrent implementer's zone.

**Rule 2 — Bracket shared-runtime changes in a DEPLOY WINDOW.**
Before touching a shared runtime: post `DEPLOY-WINDOW OPEN`. After: post `DEPLOY-WINDOW CLOSED`. Others wait for the CLOSED signal before committing to the same service.

> **Hub-mediated (STAR topology):** In a star topology, spokes watch *only* the Orchestrator's file — a message posted to an Implementer's own file is invisible to sibling Implementers. Deploy windows MUST therefore be hub-mediated:
> - An **Implementer** that needs a window posts a `DEPLOY-WINDOW REQUEST` to the Orchestrator (`→ orchestrator`). It does NOT post OPEN to its own file.
> - The **Orchestrator** broadcasts `🔧 DEPLOY-WINDOW OPEN → ALL` on its own file (every spoke sees it), waits for ACKs from active instances, performs or authorizes the shared-runtime change, then broadcasts `✅ DEPLOY-WINDOW CLOSED → ALL`.
> - The Orchestrator may open a window directly (without a prior request) when it initiates the change itself.
> Only the Orchestrator opens and closes windows on the shared channel. Spokes request; the hub broadcasts.

**Rule 3 — Stay in your lane. Announce before crossing; wait for ACK.**
Need to touch another instance's zone? Post a HEADS-UP, get an explicit ACK, then proceed. No silent cross-zone edits, ever.

**Rule 4 — Read your mailbox before any commit, push, or deploy.**
A message addressed to you may contain a decision that changes what you are about to do. The PreToolUse hook (git-pre-commit.sh) enforces this mechanically.

**Rule 5 — Public docs only. No secrets in any mailbox.**
The mailbox files are version-controlled. Never post credentials, tokens, internal paths, or PII. Treat every message as already public.

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

---

## Key Files

| File | Purpose |
|------|---------|
| `watch-coordination.sh` | Directory-based, identity-aware, echo-and-terminate watcher (STAR topology); named args `--identity`/`--role`/`--dir`; delta = newly appended bytes |
| `heartbeat.sh` | Idle-poke + Orchestrator discover-on-idle trigger; named args; 20min idle threshold, 300s cadence |
| `6-lens-audit.md` | M5: 6-lens discovery methodology — when to run, all six lenses with what to look for, output format |
| `MAILBOX-template.md` | Message grammar, tag types, atomic-write rules, archive hygiene |
| `WORK-ORDER-template.md` | WO format (full + one-liner tiers) and STATUS reply |
| `ROSTER-template.md` | Presence file schema (M9 richer fields); registration and deregistration |
| `QUEUE-template.md` | Claimable queue, three-bucket SSOT, depth-floor, push-assignment rules |
| `git-pre-commit.sh` | PreToolUse hook: mailbox-read gate, dangerous-verb warning, secret-scan |
| `bootstrap-identity.sh` | DESIGN EXTENSION: provisional-ID generation (`--provision`) and identity adoption (`--adopt`) for the naming handshake; see § Identity Bootstrap |
| `advanced/sqlite-mcp.README.md` | Optional advanced path: SQLite(WAL) + stdio-MCP for atomic claim (M6) |
