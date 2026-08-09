# Idle activity schedule (PROTOCOL 1.3.0) — per-seat scheduler for IDLE-KICK

Copy to `<coord-dir>/idle-schedule-<identity>.md` or pass `--schedule-file` to `heartbeat.sh`.
If absent, heartbeat keeps using `--idle-policy` / role defaults (backward compatible).

```
schema_version: 1
identity: <my-identity>
role: orchestrator | implementer

# Activities listed in order. On IDLE-KICK, heartbeat includes every activity
# whose `when` matches. The agent executes due items (do not stand by).

activities:
  - id: mailbox-catchup
    when: always
    summary: Read new addressed mail / same-project peer deltas before other idle work.

  - id: hold-check
    when: hold_active
    summary: ACK or clear the named HOLD; do not start product work while HOLD binds.

  - id: discover-6lens
    when: role=orchestrator AND queue_ready < 12
    summary: Run M5 6-lens discovery; refill READY queue to ≥ depth floor.

  - id: claim-next-wo
    when: role=implementer AND queue_has_unclaimed_in_zone
    summary: Claim next READY WO in your zone/project; post STATUS.

  - id: standing-idle-policy
    when: always
    summary: >-
      Fallback standing work (same text as legacy --idle-policy). Weak seats must
      use an explicit work-request-only policy — never self-generated product work.
```

## `when` predicates (v1)

| Token | Meaning |
|-------|---------|
| `always` | Every IDLE-KICK |
| `hold_active` | A named `[HOLD:…]` is in effect for this seat |
| `role=orchestrator` / `role=implementer` | Role match |
| `queue_ready < N` | Orchestrator: READY count below N (default floor 12) |
| `queue_has_unclaimed_in_zone` | Implementer: at least one READY WO targeting this zone/project |

Combine with `AND` (v1). No `OR` yet.

## Weak seats

`--weak-seat` still requires an explicit `--idle-policy` *or* a schedule file whose only product activity is work-request-shaped. Heartbeat refuses to arm a weak seat on the strong-seat default pack.
