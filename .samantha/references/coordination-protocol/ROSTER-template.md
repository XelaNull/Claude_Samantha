# Presence File / ROSTER Entry

<!--
  TEMPLATE — M9 richer ROSTER schema.
  Each instance writes ONE file in the coord-dir: <coord-dir>/<my-identity>.md
  This file IS the instance's presence entry AND its mailbox (append-only message log follows).
  See MAILBOX-template.md for the message log section.

  SCHEMA EVOLUTION (M8 — additive-only migrations):
  When adding fields to this schema, ONLY add new optional fields with defaults.
  NEVER: change the meaning of an existing field, rename a field, or remove a field.
  Rationale: a running instance may still be writing the old schema; a reader must
  tolerate both. Adding a field is safe; changing one breaks existing readers.
  Version the schema with the `schema_version` field so readers can detect old entries.

  To register: create/update this file when arming watchers (M4: read-back-after-write).
  To deregister: delete this file when tearing down (and archive the message log if large).
  The directory's live .md files ARE the live roster — no separate ROSTER.md needed.
-->

# Presence: <my-identity>

<!-- FILL: replace all angle-bracket placeholders. -->

## Identity

```
schema_version: 1
identity:      <my-identity>           # stable, derived from cwd/worktree name; never changes mid-session
role:          orchestrator | implementer
zone:          <absolute path this instance owns>  # cwd or worktree root; "workspace root" for Orchestrator
```

## State

```
state:         Active | Idle | Offline
state_updated: <UTC ISO 8601>          # when state last changed; updated by heartbeat + status transitions
```

## Process PIDs (M2 — never pkill -f; kill by recorded PID)

```
watcher_pid:   <pid>                   # PID of watcher.sh background process; update on each re-arm
heartbeat_pid: <pid>                   # PID of heartbeat.sh background process
```

## Session Timestamps

```
started_at:    <UTC ISO 8601>          # when this instance armed in for the current session
last_active:   <UTC ISO 8601>          # updated on each message posted or WO status change
```

## Work

```
current_wos:   WO-<N>, WO-<M>         # WO numbers currently claimed by this instance (or "none")
zone_lock:     <resource-name> | none  # DEPLOY WINDOW or shared-file lock held (one at a time)
zone_lock_at:  <UTC ISO 8601> | none   # when zone_lock was acquired
```

## Queue (Orchestrator only — omit on Implementers)

```
queue_depth:   <N READY>               # count of READY (buildable, unclaimed) WOs in QUEUE.md
depth_floor:   12                      # minimum; triggers discovery pass when queue_depth < depth_floor
last_discovery: <UTC ISO 8601>         # when the M5 6-lens discovery pass last ran
```

## Notes

```
notes:         <free text — current focus, context for peers, anything unusual>
```

---

## State Transitions

```
Armed in  →  Active
Active    →  Idle    (idle >= 300s, heartbeat fires)
Idle      →  Active  (any message posted or WO claimed)
Active    →  Offline (tear-down; delete this file after archiving message log)
```

The `state` field is informational — the watcher detects liveness from the file's mtime, not the state string. A file that hasn't changed in > 2× heartbeat interval (>40 min) should be treated as potentially stale. The Orchestrator surfaces stale entries to the human rather than auto-reclaiming (M7: human in the loop for reclamation at small N).

---

## Additive-Only Schema Evolution (M8)

When the schema needs a new field:

1. Add the field as optional with a sensible default.
2. Update `schema_version` to the next integer.
3. Update this template.
4. Add a migration note below.

Readers must tolerate missing optional fields by using the default. Never break backward compatibility.

### Migration history

| Version | Change | Date |
|---------|--------|------|
| 1 | Initial schema | (authoring date) |

---

## Full Example

```
# Presence: impl-alpha

schema_version: 1
identity:      impl-alpha
role:          implementer
zone:          /path/to/worktrees/impl-alpha

state:         Active
state_updated: 2026-07-01T14:35:00Z

watcher_pid:   18432
heartbeat_pid: 18433

started_at:    2026-07-01T14:30:00Z
last_active:   2026-07-01T15:45:22Z

current_wos:   WO-7
zone_lock:     none
zone_lock_at:  none

notes: Working on WO-7 (retry backoff). Sub-part A done; sub-part B in progress.
```

---

## Message Log

<!-- Message log begins below. See MAILBOX-template.md for grammar. Append only. -->
