# Remote Seats — Optional Advanced Channel (PROTOCOL 1.2.0+)

> **Optional.** Local STAR dual-mode does not need this. Use only when one or more
> Implementer seats run on a **remote host** and cannot share the local coord-dir
> filesystem (no common mount).

This document generalizes the remote ssh-bus pattern proven in live dual deployments.
It is **not** required for same-machine Orchestrator/Implementer pairs.

---

## When to use

- Hub (Orchestrator) is local; one or more spokes run on another machine.
- Spokes write presence + outbox files on a **remote bus directory** the hub can reach over `ssh`.
- You are willing to run a **second** `coord-monitor.sh` process on the hub (local channel + remote channel).

When **not** to use: both seats share `${COORD_DIR}` on one filesystem — stay on the local channel only.

---

## Shape

```
Local channel (always):
  coord-monitor.sh --identity orchestrator --dir <coord-dir>
  → watches local peer outboxes; pidfile: watcher.pid

Remote channel (optional, hub-only, SEPARATE process):
  coord-monitor.sh --identity orchestrator --dir <coord-dir> \
    --remote-host <ssh-alias> --remote-bus-dir <absolute-path-on-remote>
  → polls remote bus over ssh; pidfile: watcher-remote.pid
```

Invariants:

- **Never combine** local + remote watch sets in one process.
- Remote channel does **not** run own-file IDLE-KICK (no local own outbox in that watch-set).
- Remote channel does **not** duplicate heartbeat mutual-monitor alerts (local channel owns that).
- Heartbeat dead-man is **ALL-CHANNELS**: any armed watcher pidfile for the seat dying trips WATCHER-DOWN.

---

## Required flags (portable — no baked defaults)

| Flag | Required? | Meaning |
|------|-----------|---------|
| `--remote-host <alias>` | to enable remote channel | SSH host alias (`BatchMode` must work) |
| `--remote-bus-dir <path>` | **always with** `--remote-host` | Absolute path of the bus dir **on the remote host** |

Canon scripts **refuse to arm** remote mode if `--remote-host` is set without `--remote-bus-dir`. There is no default bus path in the portable pack.

---

## Weak seats (`--weak-seat`)

A **weak / remote Implementer** must not inherit the strong-seat idle default ("audit and start work"). Pass:

```bash
./heartbeat.sh --identity impl-<name> --role implementer --dir <coord-dir> \
  --weak-seat --idle-policy '<explicit work-request-only policy text>'
```

Without `--idle-policy`, `--weak-seat` is a hard error (MANDATORY-EXPLICIT). Typical policy: post exactly one `📥 WORK-REQUEST`, then stop until a reply — never self-generated product work.

---

## IDLE-KICK (local, all seats — core 1.2.0)

STAR spokes do not watch their own outbox. A bare heartbeat append therefore never wakes the **owning** seat. `coord-monitor.sh` self-nudges on own-file `💓 HEARTBEAT` / `⚡ IDLE-KICK` / `⚠️ WATCHER-DOWN` so the seat starts its standing `idle_policy`.

This is **not** a second idle mechanism parallel to discover-on-idle:

- **IDLE-KICK** — self-wake + actionable policy (all seats).
- **discover-on-idle** — Orchestrator-only queue-depth directive, folded into the IDLE-KICK body when `role=orchestrator`.

---

## HOLD damping (HOLD-DAMP-V2)

While a named `[HOLD:…]` marker is in effect, IDLE-KICK is damped and the seat posts periodic `HOLD-CHECK` liveness probes (default 2h) that must be ACKed. Observed-incident amendment (ratified 2026-07-29): prevents thrash / false "do not stand by" pressure during an explicit human pace-down or named HOLD.

---

## Cutover checklist (hub)

1. Ensure remote ssh alias works non-interactively (`ssh -o BatchMode=yes <alias> true`).
2. Create the remote bus dir; spokes write only their own `<identity>.md` there.
3. Arm **local** monitor as usual.
4. Arm **remote** monitor with both `--remote-host` and `--remote-bus-dir`.
5. `coord-status.sh` should show both channels alive for the hub identity.
6. Keep deployment-specific host/bus paths in the **site overlay** (e.g. workspace `.claude/` or a small env wrapper) — never commit them into this portable pack.
