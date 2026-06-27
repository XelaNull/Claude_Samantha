# Advanced Path: SQLite(WAL) + stdio-MCP Coordination (M6)

This is an **optional, human-gated upgrade** to the default markdown-based coordination protocol. It is NOT the default. The default (flat markdown files + file-watcher) stays in place until the human explicitly decides to cut over.

**Status:** The source project that proved the coordination protocol built and trialed this subsystem alongside markdown, with a human-gated cutover plan. That is the validated approach: shadow first, validate, then cut over.

---

## What this buys

| Problem (markdown-only) | SQLite(WAL) fix |
|------------------------|----------------|
| Claim race: two implementers try to claim WO-N simultaneously → both see "unclaimed", both write "claimed" | `link()` to a lock path gives first-wins / `EEXIST` for the loser — no CAS needed for claim |
| Queue lost-update: concurrent readers both read the same queue state, both write back | Orchestrator-sole-writer + WO sentinel files already fixes this — SQLite adds per-row atomicity as an upgrade |
| No cross-process channel | stdio-MCP provides `coord_send`, `coord_read`, `coord_presence` as typed operations |
| Watcher must poll files | MCP watcher fires only on addressed messages (not-from-you filter built in) |

## What this does NOT buy

- **Distributed consensus.** SQLite is a local process, not a distributed service. Leader-election, split-brain detection, and network-partition tolerance are still out of scope. This is intentional: the protocol targets **human-supervised, worktree-isolated, small-N** operation. For unattended autonomy at large N, the Agent SDK is the right tool.
- **Reclamation safety for suspended instances.** A suspended (not crashed) instance can still be reclaimed. The human-supervision assumption absorbs this: a zombie instance is visible and restartable.

---

## Architecture

```
┌──────────────────────────────────────────────┐
│  <coord-dir>/coordination.db  (SQLite WAL)   │
│                                              │
│  tables: messages, presence, queue           │
└──────────────────────────────────────────────┘
         ↑                       ↑
   stdio-MCP server          body-printing
   (coord-mcp.js or           watcher process
    coord-mcp.py)              (filters by
                               addressed-to)
         ↑
   Claude Code (each instance)
   uses MCP tools:
     coord_send, coord_read, coord_presence
```

The SQLite file runs in **WAL mode** (write-ahead log) so that concurrent readers and writers do not block each other. Reads always succeed immediately; writes go to the WAL and are checkpointed periodically.

---

## The Three MCP Operations

### `coord_send`

Append a message to the `messages` table. Returns the message ID.

```
coord_send(
  from:    string,   # sender identity
  to:      string,   # recipient identity or "ALL"
  tag:     string,   # HANDOFF | STATUS | HEARTBEAT | etc.
  body:    string,   # message body (markdown)
)
→ { message_id: integer, timestamp: string }
```

### `coord_read`

Read messages addressed to this instance since a given message ID.

```
coord_read(
  identity: string,  # this instance's identity
  since_id: integer, # read messages with id > since_id (0 = all)
)
→ [{ id, from, to, tag, body, timestamp }, ...]
```

### `coord_presence`

Write or update this instance's presence record. Also used to read others'.

```
coord_presence(
  action:   "write" | "read" | "list",
  identity: string?,   # required for write; optional for list
  fields:   object?,   # presence fields to write (merged, not replaced)
)
→ { identity, role, zone, state, current_wos, ... } | [...]
```

---

## Body-Printing Watcher

The watcher process in the SQLite path watches the `messages` table rather than files. It filters by `to = <my-identity> OR to = "ALL"` and by `from != <my-identity>` (self-filter, same as the file watcher). On a matching new message, it prints the body to stdout and terminates, requesting re-arm.

This replaces `watcher.sh` for the SQLite path. The echo-and-terminate + re-arm model is identical; only the data source changes.

---

## Cutover Plan (human-gated)

Run the SQLite subsystem in **shadow mode** alongside markdown until confidence is established.

```
Phase 1: Shadow (default — start here)
  - Both markdown files AND SQLite are written on every coordination action.
  - Reads come from markdown (unchanged behavior).
  - SQLite accumulates data and can be inspected / queried.
  - No impact on existing behavior; zero risk.

Phase 2: Validate shadow parity
  - Periodically compare markdown state to SQLite state.
  - Verify coord_read returns the same messages as the file-based read.
  - Run the 6-lens discovery pass using SQLite queries; compare results to file-based.
  - Fix any discrepancies in the SQLite path.

Phase 3: Human-gated cutover
  - DECISION: "cut over coordination reads to SQLite."
  - Human approves → ADR filed → cutover committed.
  - After cutover: SQLite is the source of truth; markdown becomes the audit log.
  - Keep markdown writes for ~1 sprint as a rollback safety net, then drop.
```

---

## Schema (SQLite)

```sql
CREATE TABLE messages (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  from_id   TEXT NOT NULL,
  to_id     TEXT NOT NULL,        -- recipient identity or 'ALL'
  tag       TEXT NOT NULL,        -- HANDOFF, STATUS, etc.
  body      TEXT NOT NULL,
  timestamp TEXT NOT NULL         -- UTC ISO 8601
);

CREATE TABLE presence (
  identity      TEXT PRIMARY KEY,
  role          TEXT,
  zone          TEXT,
  state         TEXT DEFAULT 'Active',
  watcher_pid   INTEGER,
  heartbeat_pid INTEGER,
  started_at    TEXT,
  last_active   TEXT,
  current_wos   TEXT DEFAULT 'none',
  zone_lock     TEXT DEFAULT 'none',
  notes         TEXT,
  schema_version INTEGER DEFAULT 1
);

CREATE TABLE queue (
  wo_number   TEXT PRIMARY KEY,   -- e.g. 'WO-7'
  title       TEXT NOT NULL,
  priority    TEXT NOT NULL,      -- HIGH | MED | LOW
  status      TEXT NOT NULL,      -- READY | CLAIMED | DONE | BLOCKED | DECISION-NEEDED | GATED | CANCELLED
  claimed_by  TEXT,
  depends_on  TEXT,               -- comma-separated WO numbers or NULL
  sha         TEXT,               -- set on DONE
  notes       TEXT,
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);
```

Schema evolution follows M8 (additive-only): add columns with defaults; never rename or remove.

---

## When to use this vs. sticking with markdown

| Use markdown (default) | Use SQLite (advanced) |
|-----------------------|----------------------|
| Human-supervised sessions | Need atomic claim at N>2 Implementers |
| Small N (1-2 Implementers) | High-throughput WO churn |
| Transparency + zero setup are top priorities | Want typed MCP operations over file parsing |
| Short sessions (hours) | Multi-day autonomous runs where claim safety matters |
