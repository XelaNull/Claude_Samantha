# Component Ownership (DESIGN EXTENSION — PROPOSED, not yet ratified in its origin deployment)

> **Status:** staged here for visibility per the framework's instance→framework backport
> discipline, not because it has cleared ratification. Origin deployment: proposed
> 2026-08-04, revised same-day after a cross-lane validation pass surfaced two real gaps
> (folded into the design below), pending a clean cross-lane ACK before that deployment
> treats it as canonical. Do not present this section as settled protocol until an
> adopting deployment has actually ratified it locally — copy the *mechanism*, verify it
> against your own seats' lived experience before trusting the accountability teeth as-is.

## Why

Self-claim from a shared per-repo queue has no guarantee a seat stays engaged — a seat
can go quiet with no structural signal beyond a passive heartbeat self-nudge. Component
ownership assigns each multi-seat repo's real subsystems to specific seats, scopes every
work order to a component, and adds accountability teeth so silence becomes visible
instead of invisible. Origin question that prompted this: *"what prevents an implementer
from basically just no longer picking up work orders?"*

This formalizes an existing-but-optional pattern already present in the base protocol —
§ Multi-project coordination's "sub-repo lane splits inherit the same rule" — into an
always-on mechanism with a real registry and accountability teeth, rather than
introducing a parallel system.

## Component registry

Each multi-seat repo gets `<coord-dir>/components-<repo>.md`, a path-glob-bounded table
of that repo's real components:

```
| Component  | Path glob(s)              | Notes |
|------------|----------------------------|-------|
| backend    | services/backend/**       | migrations, models, services, routes |
| admin-ui   | services/admin-ui/**      | |
| frontend   | services/frontend/**      | |
| shared     | anything outside the globs above (docs/, ADR/, root configs) | cross-cutting — see routing below |
```

- **Repo-shape-gated, not universal.** A repo with only one logical component gets **no**
  `components-<repo>.md` file at all — absence means "component concept doesn't apply
  here," not an error. The file is created only once a repo has **≥2 active seats
  simultaneously**; it stays present (harmlessly stale) if the repo later drops back to
  one seat, and component-routing goes dormant until a second seat returns.
- Registry is hub-owned (same write discipline as a multi-project board file).

## Ownership assignment

Extends the presence-header `zone` field (repo-level routing source-of-truth) — does not
replace it. A second field, `component:`, is meaningful only when the repo has a
registry:

```
zone: /path/to/workspace/backend-repo
component: backend
```

- **1:1 by default; many-to-one allowed; one-to-many never.** One seat owns one
  component. A seat may own multiple components if there are more components than
  seats. **A component is never split across two seats** — that recreates the exact
  problem this extension exists to close.
- **Assignment mechanism:** hub posts `🤝 ASSIGN-COMPONENT` on its own outbox naming
  seat→component (same handshake shape as the base protocol's `🤝 ASSIGN-IDENTITY`
  bootstrap tag — no new tag grammar needed); each seat echoes the assignment into its
  own presence header on next bootstrap/re-registration.
- **Reassignment:** a seat idle past the IDLE-KICK threshold with an unclaimed
  owned-component work order and no ACK → hub may reassign that component to a live
  seat, or hold its queue rows at current depth until the seat returns. A new seat
  joining a repo with an existing registry gets assigned the least-staffed component at
  bootstrap.

## Work-order scoping

Every work order gets a `component:` field in the full-WO template, between `Scope:` and
`Constraints:`.

- **Derived, not manually authored, by default** — at staging time the hub checks
  whether all `Scope:` paths fall under one component's glob and fills the field
  mechanically (same operation as the base zone-routing check).
- **Cross-component work orders get `component: shared`** and are NOT split into
  artificial per-component sub-WOs. Routes to whichever owning seat has the shallower
  current queue, tie-broken by recent-commit density over the WO's paths
  (`git log --stat`, last 20 commits). A WO with genuinely independent concurrent
  sub-parts across components still uses the base "disjoint sub-parts + subagent-worker
  fan-out" pattern — that fan-out stays **within** the owning seat (subagent spawns into
  the secondary component's paths under Rule 3's "announce before crossing"), never a
  cross-seat split.

## Claim-marker (mandatory companion, not optional)

Component ownership alone does **not** prevent two live seats sharing a many-to-one
component from double-working the same row — this is the gap a cross-lane validation
pass caught in the origin deployment: two seats independently closed the same queue rows
multiple times under a passive self-claim model, and many-to-one component ownership on
its own would not have fixed that. Component ownership fixes "a seat goes silent" — a
*different* failure mode from "two seats grab the same row," and the two mechanisms are
complementary, not substitutes.

Mandatory wherever a component is many-to-one (2+ seats sharing it): before starting a
row, a seat posts a one-line `📋 CLAIM [<row-id>]` to its own outbox. A seat about to
self-triage from a shared component's READY list checks the hub-visible union of recent
CLAIM posts across siblings sharing that component before picking a row. A same-tick
collision (both claim before either sees the other) is resolved by the hub on next wake
— first CLAIM timestamp wins, the loser's outbox gets a one-line `🔁 REROUTE` note.

## Accountability ("stays busy," the actual point)

Component-scoping alone doesn't guarantee engagement — a seat can still ignore its own
queue. Two additions to the base IDLE-KICK heartbeat:

1. **Per-component idle-kick.** The heartbeat's queue-depth check filters READY rows by
   `component:` matched against each seat's assignment before judging "is this seat's
   queue empty" — attributing an unclaimed READY row to its specific owning seat, not
   just the repo as a whole.
2. **Escalating teeth — AND-gated on genuine idleness, not coord-file posting cadence.**
   Sparse outbox traffic during a legitimate background-agent-dispatch-and-wait cycle
   (lane dispatched → nudges sent → independent re-verify → commit, easily 20-40+ min
   with nothing posted) is normal and productive, not stalling — a first draft of this
   escalation without the AND-gate would false-page the human over exactly that pattern.
   The escalation therefore requires BOTH: (a) the seat's owned component has ≥1 READY
   row idle past the IDLE-KICK threshold (default 1200s) with no claim, AND (b) the
   seat's own heartbeat self-nudge shows no evidence of an in-flight dispatch (no open
   subagent lane, no pending reply-await) — a seat mid-dispatch is not silent, it's busy.
   Only when both hold does the next heartbeat cadence tick post a **directed**
   `🤝 HANDOFF` naming that specific WO to that specific seat (not a generic re-nudge),
   and the hub's next queue-status line surfaces it:
   `⚠️ STALLED: <seat> owns <component>, N READY unclaimed >Xmin`. Two consecutive
   stalled ticks (~40min) on the same component, both passing the (a)+(b) check,
   escalates to a direct one-line note to the human.

## Interaction with the base protocol

| Base mechanism | Change |
|---|---|
| STAR topology | Unaffected — component ownership is metadata on the existing watch graph, not a new watch relationship. |
| Zone-routing (§ Multi-project coordination) | Extended to zone+component: a HANDOFF is only valid if WO paths ⊆ recipient `zone` **and** (if the repo has a registry) WO `component:` ⊆ recipient's assigned component(s); a `shared`-component WO satisfies the check against any seat in that zone. |
| Queue depth floor | Becomes per-component when a registry exists; stays per-repo otherwise. An unowned component doesn't get its own floor — it gets the reassignment/hold-at-depth handling above. |

## Known risk, named not hidden

Live queue evidence from the origin deployment's proposing session showed its two seats
were *not* naturally differentiated by component — both worked one component
heavily. Forcing a clean 1:1 split against evidence that doesn't support one is a real
failure mode of this design; the hub must verify actual recent work patterns
(`git log --stat` over each seat's DONE rows) before assigning components, not assign by
fiat. Many-to-one (multiple seats keep the same component, other components sit unowned
until work patterns shift or a new seat joins) is an explicitly valid, non-broken
outcome of this rule — it is not required that every component have a distinct owner on
day one.

## Migration onto an already-live multi-seat repo

Rolling this out on a repo that already has multiple active seats must not silently
reassign a seat mid-WO. Stand up the registry, post `ASSIGN-COMPONENT` for each seat's
*current, evidence-backed* pattern, let in-flight WOs finish under the prior shared-queue
rules; per-component idle-kick only starts evaluating a seat once its `component:` field
is echoed back in its own presence header.
