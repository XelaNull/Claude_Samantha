# Mailbox: <my-identity>

<!--
  TEMPLATE — one file per instance, named <my-identity>.md in the coord-dir.
  Copy to <coord-dir>/<my-identity>.md and fill the header block.
  This file IS both the mailbox AND the presence/ROSTER entry for this instance.
  See ROSTER-template.md for the full presence-schema fields that go below the header.

  RULES:
  - Append-only. Never delete or overwrite a message once posted.
  - One logical update = one atomic append (write-temp-then-rename, never in-place).
  - The Orchestrator's file (orchestrator.md) is watched by all implementers.
  - Each implementer's file is watched by the Orchestrator only (STAR topology).
  - All timestamps in UTC ISO 8601.
-->

<!-- FILL: presence fields from ROSTER-template.md -->
role: <orchestrator|implementer>
zone: <cwd or worktree path>
state: Active
watcher_pid: <pid>
heartbeat_pid: <pid>
started_at: <UTC ISO 8601>

---

## Message Log

<!-- All messages below this line. Append only. -->

---

## Message Grammar

Every message follows this format exactly:

```
### <UTC ISO 8601> — <FROM> → <TO> — <emoji TAG>

<body>
```

**Rules:**
- `FROM` and `TO` are stable instance identities (e.g. `orchestrator`, `impl-alpha`).
- `TO: ALL` for broadcast. `TO: <identity>` for unicast.
- Tag emoji comes last on the header line — it is the at-a-glance type indicator.
- Append-order is **canonical chronology** — the timestamp is metadata, not the source of truth.
- One logical update = one atomic append. Never split a single message across two appends.
- **Atomic write**: always write-temp-then-rename (never write in-place to shared files):
  ```bash
  TMPFILE=$(mktemp "$MAILBOX_FILE.XXXXXX")
  cat "$MAILBOX_FILE" > "$TMPFILE"
  echo "$new_message" >> "$TMPFILE"
  mv "$TMPFILE" "$MAILBOX_FILE"
  ```

---

## Tag Reference

| Tag | Emoji | Meaning | Expected reply |
|-----|-------|---------|----------------|
| HANDOFF | 🤝 | Work order or delegation | STATUS |
| STATUS | 📋 | Progress report: DONE / BLOCKED / DECISION-NEEDED | none, or ACK |
| DECISION-NEEDED | ❓ | Blocked; requires Orchestrator or human resolution | HANDOFF or HEADS-UP |
| DEPLOY-WINDOW REQUEST | 🔧 | Implementer asks Orchestrator to open a deploy window | Orchestrator broadcasts DEPLOY-WINDOW OPEN → ALL |
| DEPLOY-WINDOW OPEN | 🔧 | Orchestrator signals shared-runtime work beginning | ACK from all active instances before proceeding |
| DEPLOY-WINDOW CLOSED | ✅ | Shared runtime work complete; others may proceed | none |
| HEADS-UP | 🛰️ | Informational; no action required | none, or ACK if relevant |
| ACK | 🤝 | Acknowledges receipt of a specific message | none |
| HEARTBEAT | 💓 | Alive signal; no substantive activity | none |
| PROCESS-NOTE | 💡 | Proposes a protocol change; obligates Orchestrator to full review | ratification or counter-proposal |
| ASSIGN-IDENTITY | 🤝 | Orchestrator assigns a stable identity to a newborn Implementer (bootstrap handshake) | ACK from the Implementer after adopting |

---

## Example Messages

### HANDOFF (Orchestrator → Implementer)

```
### 2026-07-01T14:30:00Z — orchestrator → impl-alpha — 🤝 HANDOFF

**WO-7: Add retry backoff to the job queue worker**

See WORK-ORDER-template.md for the full format.
```

### STATUS: DONE

```
### 2026-07-01T15:45:22Z — impl-alpha → orchestrator — 📋 STATUS

**WO-7 STATUS: DONE**

SHA: a3f9b2c
Proof: `make test` passes (12/12); manual smoke: job fails → retries 3× with 2s/4s/8s backoff → dead-letters.
Notes: no changes from original plan.
```

### STATUS: BLOCKED

```
### 2026-07-01T16:02:00Z — impl-alpha → orchestrator — 📋 STATUS

**WO-7 STATUS: BLOCKED**

Blocks: The retry config table does not exist in the schema. Migration needed before I can proceed.
Next: WO-7 waits until the migration WO is DONE.
```

### STATUS: DECISION-NEEDED

```
### 2026-07-01T16:10:00Z — impl-alpha → orchestrator — ❓ DECISION-NEEDED

**WO-7 STATUS: DECISION-NEEDED**

Question: The spec says "retry up to MAX_ATTEMPTS" but MAX_ATTEMPTS is not defined in the
job_type_config table. Should it be a global constant (simpler) or per-job-type (more flexible)?
Canon currently supports both interpretations — this is a gap. Filed DECISION-OPEN-005.
Unambiguous kernel built: the retry logic exists; it reads from a constant I've named RETRY_MAX=3.
Awaiting your call on per-type vs. global.
```

### DEPLOY-WINDOW (hub-mediated — STAR topology)

In a star topology spokes watch only the Orchestrator's file, so deploy windows
MUST be hub-mediated. An Implementer requests; the Orchestrator broadcasts.

**Step 1 — Implementer requests a window (posts to its own file → orchestrator):**
```
### 2026-07-01T16:18:00Z — impl-alpha → orchestrator — 🔧 DEPLOY-WINDOW REQUEST

Need to restart shared service X (queue-service) to pick up new retry config.
Zone: queue-service only. ETA: ~2 minutes.
```

**Step 2 — Orchestrator opens the window (posts to orchestrator.md → ALL, every spoke sees it):**
```
### 2026-07-01T16:20:00Z — orchestrator → ALL — 🔧 DEPLOY-WINDOW OPEN

Service X (queue-service) — impl-alpha restarting. Zone: queue-service only.
Hold commits to queue-service/* until CLOSED.
```

**Step 3 — Active spokes ACK (each posts to its own file → orchestrator):**
```
### 2026-07-01T16:20:30Z — impl-beta → orchestrator — 🤝 ACK

DEPLOY-WINDOW OPEN acknowledged. Standing by.
```

**Step 4 — Orchestrator closes the window (posts to orchestrator.md → ALL):**
```
### 2026-07-01T16:22:30Z — orchestrator → ALL — ✅ DEPLOY-WINDOW CLOSED

Queue service restarted cleanly. Commits to queue-service/* may resume.
```

### HEARTBEAT

```
### 2026-07-01T18:00:00Z — impl-alpha — 💓 HEARTBEAT

Alive. Idle for >=300s. Working on WO-8 in background.
```

### ASSIGN-IDENTITY (bootstrap handshake — DESIGN EXTENSION)

Orchestrator → newborn Implementer's provisional id:

```
### 2026-07-01T14:05:00Z — orchestrator → pending-a3f9b2c1d4e5f678 — 🤝 ASSIGN-IDENTITY

You are: impl-alpha
Unique in <coord-dir>/ at time of assignment (no impl-alpha.md existed).

Adopt: run bootstrap-identity.sh --adopt --provisional pending-a3f9b2c1d4e5f678 --assigned impl-alpha.
Re-arm your watcher under impl-alpha. Reply with ACK.
```

Implementer ACK after adoption:

```
### 2026-07-01T14:06:00Z — impl-alpha → orchestrator — 🤝 ACK

Identity adopted: pending-a3f9b2c1d4e5f678 → impl-alpha.
Watcher re-armed. Zone: <cwd>. Watching <coord-dir>/orchestrator.md.
```

---

## Archive Hygiene

When a mailbox file exceeds ~200 messages (or ~50KB), archive and start fresh:

1. Copy the current file to `<coord-dir>/archive/<my-identity>-<YYYYMMDD>.md`.
2. Create a new `<my-identity>.md` with the presence-schema header intact.
3. Add a one-line pointer: `Archived prior messages: archive/<my-identity>-<YYYYMMDD>.md`.
4. Do this atomically: write to a temp file, rename into place.
5. Post a HEADS-UP so peers know the file was cycled.

The archive directory (`<coord-dir>/archive/`) is read-only history. Do not edit archived files.
