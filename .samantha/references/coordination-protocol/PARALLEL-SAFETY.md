# Parallel-Safety Classification — the **PAR tag**

A project-agnostic method for letting an Implementer fan out subagent build-waves as aggressively as is *safe* — never wider than disjoint write-sets allow. Every WO carries a **PAR tag** that answers one question at a glance:

> *"What can I build at the same time as this, right now, without two workers editing the same file and silently dropping a write?"* (the concurrent-edit race the single-committer rule exists to prevent).

**This file defines the METHOD.** Each project defines its **own** lane/Cell map in its local queue doc (see §7). The framework never hard-codes a project's lanes.

---

## 1. Granularity: **Lane ▸ Cell ▸ write-glob**

Scheduling on lanes is too coarse. The unit that actually determines collision is the **Cell**.

- **Lane** — an exclusive write-territory: a repo, a service, or a top-level module. Cross-lane work is almost always concurrent (no shared files between lanes).
- **Cell** — *the unit of parallelism*: the finest collision-independent file-family within a lane (one leaf module/service file, one component-family, one isolated subsystem). **Two WOs collide IFF they share a Cell.** A Cell's write-glob = its **source-glob ∪ its test-glob** (tests count — see R2).
- **Spine** — the shared files within a lane that many WOs touch (shared models/schemas/config/base-classes, the app shell, shared test fixtures). A write here ripples lane-wide → it is the lane's serializer.

> **Schedule on Cells, not lanes.** "One service" is not one queue — it's *N* Cells that run at once, gated only by the rare spine change.

---

## 2. Collision class — the headline PAR tag

| | Class | Meaning | Parallel rule |
|---|---|---|---|
| 🟢 | **FREE** | disjoint Cell · no unmet dep · no shared runtime/migration | run concurrently with **anything**, incl. same-lane siblings in other Cells |
| 🟡 | **LANE** | shares a Cell with a **named** sibling WO | parallel across lanes; serialize with the `conflicts:` sibling only |
| 🟠 | **ORDERED** | needs a predecessor merged first | cannot start until `after:<WO>` **commits** |
| 🔴 | **SERIAL** | shared **runtime** / migration / cross-lane file | needs a deploy window or cross-lane ACK |

---

## 3. Blast radius — graded collision likelihood

Collision is not binary. Grade every WO / sub-part:

- 🟩 **LOW** — writes only leaf file(s) in one Cell. Freely parallel with any other LOW in a different Cell.
- 🟨 **MED** — writes a leaf but **reads** a spine type a concurrent WO might change; or is a **stitch step** landing on a shared mount-point (R1). Safe *iff* no concurrent WO writes that Cell/spine.
- 🟥 **HIGH** — **writes a spine file**, or a **shared test-spine** (a common fake/fixture base — R2). Lane-wide serializer: runs **first-and-solo**; leaves rebase onto it.

---

## 4. The tag

Every WO header carries:

```
[ <LANE>:<CELL> · <FREE|LANE|ORDERED|SERIAL> · blast:<🟩/🟨/🟥> · after:<WO…> · conflicts:<WO…> · deploy:<free|window|deploy-with:<WO>|gated> · gate:<reviewers> ]
```

`deploy`: `free` (own-lane restart / heads-up) · `window` (shared-runtime/migration → hub deploy window) · `deploy-with:<WO>` (contract-coupled, ships together) · `gated` (human sign-off — auth/payments/public-push/etc.).

---

## 5. Safety rule (one line)

> **Two WOs are safe to build simultaneously IFF they occupy different Cells (disjoint write-globs *including tests*, neither writing the lane spine) AND neither is `ORDERED` on an uncommitted WO AND neither is `SERIAL`-conflicting.**

Same-lane / **different-Cell = still safe** — that is the entire point. Serialize only on a **shared Cell** or a **spine write**.

**Bounds on "aggressive"** (independent of this classification):
1. **The agent cap** — the hard ceiling on concurrent subagents; the wave-width limit.
2. **One committer** — workers build in parallel but do **not** commit; the lead serializes commits and **verifies each worker's persistence** (`git log`/`git diff`) — the concurrent-edit race can silently drop a write even across disjoint files when workers share a checkout.
3. **Gate-reviewer throughput** — reviewers are themselves subagents; an oversized wave starves the gate.

Aggression = "fill the wave to the disjoint-Cell boundary, then to the agent cap," not "run everything."

---

## 6. Composition recipe — the Implementer's standing practice

1. **Decompose to the finest write-set** (source **∪** tests). If a WO writes >1 Cell, **split it** into one sub-part per Cell.
2. **Grade each sub-part's blast radius** (🟩/🟨/🟥).
3. **Spine sub-parts (🟥) commit first-and-solo** (they move the shared contract); then 🟩/🟨 leaves fan out **in parallel**, rebased on the committed spine.
4. **Name the STITCH Cell as its own serial post-wave step (R1).** *N* disjoint leaves that get **composed** = *N* parallel leaves **+ 1 serial integration sub-part** on the shared mount-point (page/route/shell file). Grade it 🟨/🟥 and schedule it *after* the leaf wave — never inside it.
5. **Compose the wave** from pairwise Cell-disjoint 🟩/🟨 parts, up to the agent cap.
6. **A WO that's hard to parallelize usually wasn't decomposed enough** — a WO-authoring failure to fix by splitting.

### Refinements ratified from real waves
- **R1 — the stitch is a hidden serializer.** Parallel *new-file* leaves fan out clean, but *wiring them together* converges on ONE shared mount-point. Model that as an explicit serial integration Cell, or "new files fan out" silently hides the stitch-collision.
- **R2 — a Cell spans source ∪ tests; shared test-infra is spine.** Disjoint *source* Cells still collide on a shared *test* file; a common fake/fixture base is 🟥 **test-spine**. A Cell's write-glob = source-glob ∪ test-glob.

---

## 7. Lane roster — the "how many tracks" dashboard

The roster is the number the Implementer keeps in its head: *"I have **N** independent lanes, and each is an idle track until it has a worker in it."* Each project enumerates its **full lane universe** (every repo + sub-lane), and per lane marks status:

- **FED** — a worker is in it.
- **STARVING** — has WOs, no worker → **fill now.**
- **EMPTY** — no WOs authored → the **Orchestrator's** gap to audit for buildable work.
- **BLOCKED(after:X)** — waiting on a predecessor.
- **GATED(human)** — needs a human decision (a second Implementer, an outward push, etc.) → surface, don't silently idle.

> **Standing instruction (Implementer):** each loop, staff STARVING lanes **before** deepening an already-FED one. Breadth across lanes beats depth in one; a starving lane is wasted parallelism.
> **Standing instruction (Orchestrator):** an EMPTY lane is *yours* to author work for; a GATED lane gets surfaced to the human.

---

## 8. Wave plan

The **wave** = the maximal set of WOs whose dependencies are satisfied and whose Cells are pairwise disjoint. That is what the Implementer fires *now*, one worker per WO. Recompute the wave when a WO commits (its dependents may unblock).

---

## Worked example (illustrative — NOT canon; substitute your own map)

> A game project split its `gameserver` lane (which naïvely reads as "one queue") into ~6–8 Cells — one per leaf service (`team_service`, `fleet_service`, `npc_service`, …), plus isolated subsystems (`scheduler`, `auth`), with `models/` + `schemas/` + `core/` as the **spine**. In real waves: disjoint-Cell WOs ran 3-wide with zero collisions; same-Cell WOs serialized every time; the shared test fake-base was 🟥 test-spine and held behind all churn touching it. The UI lane's persistent-shell files were its spine; new-component WOs fanned out, and the step that wired them into the shell was the serial stitch (R1).

Every project substitutes its own lanes, Cells, and spine.

---

## Defining YOUR project's map

1. **List lanes** — repos + top-level services/modules (exclusive write-territories).
2. **Within each lane, list Cells** — the leaf file-families that don't import each other's internals — and the **spine** (shared files everything imports).
3. **Fold tests into each Cell's glob**; grade shared fixtures/fakes as 🟥 test-spine.
4. **Put the map in your local queue doc**; keep *this* file as the method. Tag every WO with its `PAR:` line at authoring time.
