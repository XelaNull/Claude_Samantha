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
- **Project-scoped spoke delivery** (PROTOCOL 1.3.0): an implementer wakes on hub mail to itself, to `ALL`, or to any seat in the **same project**; other projects are silent. Same-project peer outboxes are also watched. Prefer unicast within a project.
- Tag emoji comes last on the header line — it is the at-a-glance type indicator.
- Append-order is **canonical chronology** — the timestamp is metadata, not the source of truth.
- One logical update = one atomic append. Never split a single message across two appends.
- **Post via `coord-send.sh` — the only supported way to post a message (PROTOCOL
  1.4.0).** It builds the header, appends the body, SSH-signs the whole thing, and
  does the write-temp-then-rename append atomically — all in one step:
  ```bash
  coord-send.sh --identity <my-id> --dir <coord-dir> --to <recipient> --tag STATUS --body "..."
  ```
  **Hand-appending (the raw `mv`/`cat`/`echo` shape below) is DEPRECATED and
  produces an unsigned message.** Once a seat's tooling is at 1.4.0 there is no
  supported way to post unsigned (README.md § "Sending: always signed, hard-fail
  on sign failure") — a hand-appended message reads as `⚠️ UNVERIFIED` under
  `coord-verify.sh` and gets hard-blocked by `coordination-precommit-hook.sh`
  under `--strict` unless it happens to match one of the three narrow bootstrap/
  dead-man exemptions (see § "Signature block" below and README.md § Message
  Authenticity — those exemptions are NOT a general-purpose escape hatch). This
  snippet is kept only as the underlying atomic-write PATTERN `coord-send.sh`
  itself is built on, for reference — never call it directly to post a message:
  ```bash
  TMPFILE=$(mktemp "$MAILBOX_FILE.XXXXXX")
  cat "$MAILBOX_FILE" > "$TMPFILE"
  echo "$new_message" >> "$TMPFILE"
  mv "$TMPFILE" "$MAILBOX_FILE"
  ```
- **Evidence discipline — "the ACK is not the artifact, the file is."** Any entry asserting the state of an *external* artifact — that an action completed (merge, fetch, push, file edit, migration, deploy) **or that nothing changed** ("still untouched", "still clean", "no divergence") — must paste literal, tool-output-shaped evidence: a `state=` / `mergedAt=` line, a SHA, a `grep -n` block, a `--json` dump. Never a prose sentence describing it. Three corollaries, each earned from a real failure:
  - **A verbatim quote alone is not evidence.** An accurate quote is only provably real because the reader could go re-verify it — which relocates exactly the manual-check burden this rule removes. Citing prose from another file requires the `grep -n` (or equivalent command output) that found it, appended to the quote.
  - **The evidence must be fetched in the same action as the claim**, not earlier in the same turn. Stale-but-real output satisfies a naive reading of the rule while still being wrong.
  - **Fetch-and-log-write is ONE atomic action** — never a fetch call followed by a separately-scheduled log entry. The split reliably produces a dangling claim with no value attached.
  > Negative claims are in scope on purpose: "the file is still untouched," based on a read taken minutes ago, is the same defect wearing the opposite sign.
  > `coord-evidence-lint.sh` mechanizes this — with a stated ceiling: it checks that evidence is *present* and output-shaped, not that it is *true*. A fabricated `state=MERGED` still passes. Its real value is converting "wrote a confident sentence" into "had to produce something shaped like output," which catches the omission failure mode (the common one) if not the fabrication one.
- **Message-log entries: append-only at true EOF via shell `>>`** (or the write-temp-then-rename pattern above) — never anchor-based Edit. A concurrent heartbeat daemon may have appended past your anchor since your last read, and an anchor-based edit inserts mid-file, defeating tail-diff addressing. Structured header/roster fields (`watcher_pid`, `heartbeat_pid`, `state`, `last_active`, `queue_depth`) are the opposite: updated in place via Edit, never appended — see ROSTER-template.md.
- **Signature block (PROTOCOL 1.4.0 — Message Authenticity).** `coord-send.sh` appends a `<!-- SIG v1 ... -->` block immediately after every message it posts:
  ```
  <!-- SIG v1
  namespace: samantha-coord
  signer: <FROM identity>
  bytes: <exact byte length of the signed region: header line + \n + body + \n>
  -----BEGIN SSH SIGNATURE-----
  <ssh-keygen -Y sign output>
  -----END SSH SIGNATURE-----
  -->
  ```
  **Machine-generated only — never hand-author a SIG block.** It is produced by
  `coord-send.sh` at the moment of posting (`ssh-keygen -Y sign`, namespace
  `samantha-coord`) and checked by `coord-verify.sh` against `<coord-dir>/allowed_signers`.
  The `bytes:` line is NOT a lint aid — `coord-verify.sh` reads exactly that
  many raw bytes starting at the header line to find the signed region, which
  is what makes message-boundary detection exact instead of a heuristic that
  can misparse a body quoting a prior header on its own line (2026-08-09
  hardening; see coord-verify.sh's header comment). A message with no SIG
  block reads as `⚠️ UNVERIFIED`, not an error — legacy/pre-amendment history
  and the bootstrap-handshake message shapes are expected to have none. See
  README.md § Message Authenticity (SSH signing) for the full mechanism, key
  storage, and the hard-block this enables.

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

**PROTOCOL 1.4.0 — key material during bootstrap.** A newborn's first `🛰️ HEADS-UP`
(via `bootstrap-identity.sh --provision`) carries a `pubkey: <raw-pubkey-line>`
field in its body — the Orchestrator's `🤝 ASSIGN-IDENTITY` reply enrolls it
under the assigned name. Neither message is itself SSH-signed (see § Message
Grammar above and two of coord-verify.sh's three exemptions, the
bootstrap-handshake ones) — this is the
handshake that BOOTSTRAPS the signing trust root, so nothing yet exists to
verify them against.

---

## Example Messages

### HANDOFF (Orchestrator → Implementer)

```
### 2026-07-01T14:30:00Z — orchestrator → impl-alpha — 🤝 HANDOFF

**WO-7: Add retry backoff to the job queue worker**

See WORK-ORDER-template.md for the full format.
```

### HANDOFF, signed (PROTOCOL 1.4.0 — the shape coord-send.sh actually writes)

`coord-send.sh` appends the `<!-- SIG v1 ... -->` block immediately after the
body, no blank line before it. Illustrative only — this is not a real
verifiable signature:

```
### 2026-07-01T14:30:00Z — orchestrator → impl-alpha — 🤝 HANDOFF

**WO-7: Add retry backoff to the job queue worker**

See WORK-ORDER-template.md for the full format.
<!-- SIG v1
namespace: samantha-coord
signer: orchestrator
bytes: 176
-----BEGIN SSH SIGNATURE-----
U1NIU0lHAAAAAQAAADMAAAALc3NoLWVkMjU1MTkAAAAgBS6QZEE4HYhoP1KwOlhqzF7gax
HCMHBRmZVd7ytpCicAAAAOc2FtYW50aGEtY29vcmQAAAAAAAAABnNoYTUxMgAAAFMAAAAL
c3NoLWVkMjU1MTkAAABAvIfDut51dz/c+60dB5lxkSILvvPwqpqNpQlL/fLCZooVHSqo0s
8uv4/uzINu6/Gi5F/zANAvU8IhiDf8iiRbDQ==
-----END SSH SIGNATURE-----
-->
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
