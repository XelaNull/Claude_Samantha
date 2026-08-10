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

**Signing (PROTOCOL 1.4.0 remote-seat extension, 2026-08-09):** a remote seat's `coord-send.sh` calls must also pass `--remote-seat` (or `COORD_REMOTE_SEAT=1`):

```bash
./coord-send.sh --identity impl-<name> --dir <remote-bus-dir> --remote-seat \
  --to orchestrator --tag STATUS --body "..."
```

Same MANDATORY-EXPLICIT posture as `--weak-seat` above, for the same reason: a remote bus dir has no local `allowed_signers` of its own (§ Message Authenticity below) — inferring that from file-absence alone would be ambiguous with an ordinary local coord-dir where nobody has been enrolled yet, and would silently defeat the enrollment-readback-verify check (`coord-send.sh`'s item 8 hardening) for that common local case too. See § Message Authenticity for the full mechanism.

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

## Message Authenticity (SSH signing) — remote channel coverage (2026-08-09)

**The remote channel IS covered by PROTOCOL 1.4.0 signature verification**,
closed as of the round described here. This section previously stated the
opposite — that coverage was explicitly out of scope — as a deliberate,
undocumented-gap admission rather than a silent one; that gap is now closed,
and this section is rewritten to describe the actual mechanism rather than
its absence.

### Design: ONE canonical trust root, not per-remote copies

A remote seat's own `coord-send.sh`/`heartbeat.sh` — running locally ON the
remote host, against `--dir <remote-bus-dir>` — already sign every message
exactly like a local seat, with zero changes needed: from the remote seat's
own point of view, its bus dir is an ordinary local coord-dir, and every
signing call (`coord-keygen.sh --generate`, `ensure_signing_key`,
`sign_message_file`) is purely `--dir`-driven with no hostname/topology logic
anywhere in it. **Confirmed by direct code inspection** (2026-08-09), not
assumed: `coord-send.sh`, `coord-keygen.sh`, `heartbeat.sh`, and
`bootstrap-identity.sh` contain zero references to "local" vs "remote" — the
remote/local distinction exists only in `coord-monitor.sh`'s watch topology
and `heartbeat.sh`'s dead-man-alert channel tracking (`--remote-host`
there means something different: the ORCHESTRATOR's own heartbeat tracking a
remote `coord-monitor.sh` channel's liveness, not "this seat is remote" —
see that flag's own inline comment), never in the signing mechanics
themselves.

The **hub's own local coord-dir's `allowed_signers` stays the single trust
root** — there is no separate "remote allowed_signers," and a remote bus dir
deliberately has none of its own. A remote seat's pubkey is enrolled into it
via the EXISTING mechanism, unchanged: the Orchestrator's `🤝 ASSIGN-IDENTITY`
reply already calls `coord-keygen.sh --enroll` purely locally on the hub,
using a pubkey STRING parsed out of the newborn's HEADS-UP body — that enroll
call never touches the filesystem the pubkey text originated from, so it
works identically whether that HEADS-UP arrived via a local fs event or via
`remote_emit_new`'s ssh-fetch relay. **Confirmed by direct code inspection**:
`coord-keygen.sh --enroll`/`--rotate` take `--pubkey-line` as an opaque
string argument with no file-read dependency at all. This is the deliberate
design choice, not an oversight: mirroring `allowed_signers` out to every
remote bus dir would recreate the exact drift/sync problem — N copies of a
trust root that must all stay in lockstep, silently diverging the moment one
sync fails — a single canonical root exists specifically to avoid.

**One real consequence of this design, and how it's handled:** a remote
seat's own local `coord-send.sh` invocation cannot self-verify against a
local `allowed_signers` it structurally doesn't have — its own item-8
enrollment-readback-verify would otherwise ALWAYS see `❓ UNKNOWN-SIGNER` and
refuse to report success, even though nothing is wrong. `coord-send.sh` now
requires `--remote-seat` (or `COORD_REMOTE_SEAT=1`) to be passed EXPLICITLY
for this — MANDATORY-EXPLICIT, same posture as `--weak-seat` above, and
deliberately NOT inferred from "no local allowed_signers found" alone (that
signal is genuinely ambiguous with an ordinary local coord-dir where nobody
has been enrolled yet — inferring it would silently defeat the
unenrolled-identity check for the common local case). See § Weak seats above
for the exact invocation shape.

### What `coord-monitor.sh`'s remote channel does now

`remote_emit_new` fetches new bytes over ssh exactly as before, but now
writes the fetched buffer to a **local temp file named after the real remote
identity** (e.g. `impl-remote1.md`, inside a fresh temp directory — never an
arbitrary `mktemp` basename, which would make coord-verify.sh's structural
`FROM == basename(file)` check spuriously fail every remote message
regardless of validity) and runs `coord-verify.sh` against it, `--dir`
pointed at the HUB's own local coord-dir — never anything remote-path-shaped.
Annotated inline exactly like the local channel (`✅`/`⚠️`/`❓`/`❌`, batched
as one block after the message text — see `coord-monitor.sh`'s own comment
for why not interleaved per-message), verified against the RAW pre-filter
chunk so a spoke's own addressing filter never affects whether the
underlying signature gets checked. This logic lives in `coord-remote-verify.sh`
(`verify_remote_buffer`), a small SHARED helper sourced by both
`coord-monitor.sh` and `coordination-precommit-hook.sh` — one definition, so
the two can never verify a remote buffer differently.

### What `coordination-precommit-hook.sh` does now

The hook previously had no way to even know a remote channel existed — a
remote bus dir lives on a different host by definition, structurally
invisible to a hook that only ever enumerates `<coord-dir>/*.md` locally.
Closed via `<coord-dir>/.remote-channels` (one `<host> <bus-dir>` line per
configured channel) — **auto-written by `coord-monitor.sh`'s remote channel
the moment it arms**, not a manual step (an operator forgetting a manual step
is exactly the kind of quiet gap this whole amendment exists to close
elsewhere; see the Cutover checklist below, now one line shorter for it).
Before allowing a hub commit, the hook reads `.remote-channels` if present
and, for each configured channel, ssh-fetches every remote seat's outbox
file(s) **in full** (verified via the same `coord-remote-verify.sh` helper
`remote_emit_new` uses) and blocks the commit — exactly like local content
does — on any `❌ INVALID`, `❓ UNKNOWN-SIGNER`, or non-exempt `⚠️ UNVERIFIED`.

**Why full-file every time, not git-anchored like the local hard-block:**
there is no local git history for a file that lives on a different host —
nothing to anchor a "since the last commit" floor against. Remote mailboxes
are bounded by this protocol's own ~200-message/50KB archive-hygiene
convention, so a full re-verify on every commit is cheap regardless of
rotation cadence, not a wasted-effort concern the way an unbounded file would
be.

**Reachability, stated as the one real caveat that remains:** ssh
reachability affects **whether verification can RUN at all, not whether it's
trustworthy when it does run** — a meaningfully lesser caveat than this
document used to carry. The whole point of the signature is that tampered
content fails crypto verification regardless of transport trust; ssh's
`BatchMode` host-key trust was never load-bearing for THAT guarantee, only
for delivering the bytes to check in the first place. An unreachable remote
host does **not** silently skip verification (that would be a bypass an
attacker — or a flaky network — gets for free): the hook fails CLOSED, with a
bounded timeout (`ConnectTimeout`/`ServerAlive` ssh options — no new
dependency on GNU `timeout(1)`) and a diagnostic that names the real cause
("could not reach remote channel `<host>` to verify — treating as
UNVERIFIED, not skipping") rather than reading like a tamper signal.

**What is genuinely still a ceiling, unrelated to this round's work:** this
hook is a Claude-Code-session-scoped Bash-command-TEXT matcher (see the main
`README.md` § Hard-block for its full, general ceiling statement) — it does
not protect a human typing `git commit` directly in a terminal on the hub,
local or remote content alike. A remote channel only ever gets checked once
`coord-monitor.sh` has armed it at least once (that's what writes
`.remote-channels`) — a configured-but-never-armed remote seat is invisible
to the hook until its channel is armed, same as any config that has to be
written down somewhere before it can be read.

### Round-5 hardening (2026-08-09) — three real gaps found by adversarial review

A dedicated security/architecture review of the round described above found
one live-exploitable RCE and two more real gaps before this shipped. All are
closed now; documented here rather than swept into the narrative above so
the fix (and the reasoning behind it) stays visible on its own.

1. **Command injection via a remote-supplied filename (CRITICAL, live-
   demonstrated).** Both `remote_emit_new` and the hook's remote-channel
   check used to splice a filename **listed by the remote host itself** into
   an ssh command string with zero shell-metacharacter escaping — a file in
   the remote bus dir named e.g. `x'; id; echo '.md` executed arbitrary code
   on the hub, before any signature check ever ran. The listed filename is
   exactly as trustworthy as whoever can write into the remote bus dir — the
   population this whole extension exists to distrust — so this was a full
   compromise of the hub from an untrusted remote-writable directory.
   Client-side argv separation does not help here: ssh always re-joins its
   trailing arguments into ONE string for the remote shell to parse, so
   passing a value as a "separate" local argv element offers no protection.
   Fixed with one shared POSIX single-quote-escaping helper,
   `coord_remote_shquote` (`coord-remote-verify.sh`), applied to **every**
   value spliced into a remote command string in both scripts — and made a
   **hard dependency**: `coord-monitor.sh` now refuses to arm `--remote-host`
   at all if this helper isn't available, rather than ever falling back to
   unescaped interpolation (the pre-round-5 sourcing of `coord-remote-verify.sh`
   was best-effort, which was safe when the file's only job was optional
   signature annotation — no longer true once it also carries the escaping
   this extension's basic safety depends on).
2. **Four independently-drifting "is this a seat outbox" exclusion lists**
   (`coord-monitor.sh`'s local watch set, its remote sweep, and the hook's
   LOCAL and REMOTE checks each hand-maintained their own list of
   QUEUE.md/PROJECTS.md/queue-\*.md/\*.archive.md — and had already drifted;
   the hook's remote check excluded none of them, and its local check was
   still missing PROJECTS.md/queue-\*.md when this round started — round-5
   unified the other three sites but missed this fourth, older one, which
   predates the remote extension entirely). An ordinary deployment using a
   queue file — remote OR purely local, not a crafted attack — would
   permanently hard-block a hub commit via a false `FROM == basename(file)`
   structural mismatch. Now ONE shared predicate, `coord_is_seat_outbox_basename`
   (`coord-address-filter.sh`), used by all four call sites.
3. **A missing, empty, or redirected `.remote-channels` produced zero
   output** — indistinguishable from "no remote channel configured," and
   since this file is unsigned, gitignored, coord-dir-local state, an actor
   with write access to the coord-dir could point it at an empty decoy
   directory while a genuinely forged message sat in the real remote bus
   dir, for a fully silent bypass. The check 1c block now **always** prints
   exactly which `host:bus-dir` pair(s) it checked, even zero, and
   cross-checks a live `watcher-remote.pid` against an empty/missing
   `.remote-channels`, failing closed if a channel this host believes is
   armed isn't actually being verified. This does not cryptographically
   *prevent* a coord-dir-write-level actor from redirecting the file — and
   this is genuinely a WEAKER tier than `allowed_signers`, not the same one:
   `allowed_signers` is git-tracked (a tamper shows up as a reviewable diff)
   and is itself the thing every signature check authenticates against;
   `.remote-channels` is gitignored, coord-dir-local, unsigned state with
   none of that — no tracked history, no diff visibility, no cryptographic
   binding to anything. The round-6 fix makes a redirect **visible** at
   commit time (the always-printed channel count, the live-watcher cross-
   check) instead of silent, which meaningfully raises the bar — but it is
   not the same guarantee `allowed_signers` gets from git, and should not be
   described as such.

Two smaller items closed in the same pass, worth naming since they affect
day-to-day operation:

- **A remote seat running this same hook against its own bus-dir-as-
  coord-dir** (e.g. committing its own coord-dir content locally on the
  remote machine) would previously be permanently blocked by check 1b's
  local sig-verify — the same failure shape `coord-send.sh` had before its
  own `--remote-seat` fix, never addressed for the hook. `COORD_REMOTE_SEAT_HOOK=1`
  is the explicit escape (env-var-only — this hook has no CLI flag surface,
  wired via fixed positional args). **Deliberately a different variable**
  from `coord-send.sh`'s `COORD_REMOTE_SEAT`/`--remote-seat`: sharing one
  would mean setting it for the hook's benefit on a remote seat's machine
  also silently changes `coord-send.sh`'s behavior there (and vice versa on
  the hub) — two different explicit-vs-ambient risk profiles, kept
  separate on purpose. The compensating control either way is the hub's
  check 1c, which verifies this seat's traffic remotely regardless.
- `coord-send.sh`'s success line no longer claims "signed, verified" when
  `--remote-seat` deferred verification to the hub — it now says "signed;
  verification deferred to hub." And since `COORD_REMOTE_SEAT` is an
  environment variable (ambient authority — a stray `export` left in a
  shell profile, worst case on the **hub itself**, would silently defeat the
  enrollment readback-verify for what should be an ordinary, fully-checked
  local send), `coord-send.sh` now names its *source* (`--remote-seat` flag
  vs. the environment variable) in its output, with an extra `WARN` when the
  source is the environment — an operator seeing unexpected "skipping the
  local enrollment readback-verify" output has an immediate lead on why.

**One more ceiling, stated plainly and not previously written down
anywhere:** a signature proves *authorship*, not *placement*. Anyone with
write access to a remote bus dir can take a genuinely, validly signed
message and replay it into the correctly-named file, and it will verify
`✅` — because it legitimately IS that identity's real, unmodified,
signed content, just placed there by someone else. This is true of the
local channel too (there, that "someone else" is the operator's own tree,
a much smaller trust boundary) — it was simply never stated for the remote
case until now. Full defense against a hostile remote-bus-dir writer needs
OS-level access control on that directory, which is outside this protocol's
filesystem-perms-based trust model everywhere else, not just here.

---

## Protocol Version Handshake (Remote Ceiling) — PROTOCOL 1.5.0

Neither half of § Protocol Version Handshake (main `README.md`) is wired to
the remote channel today. Both scope statements are stated as design
decisions, not "not possible" — the framing matters for anyone considering
extending this later:

- **Part B (advisory re-arm alert).** Scoped to the LOCAL channel because a
  remote seat's `.presence` sidecar lives on a different host and isn't
  reachable via a local `presence_get` lookup at all — see main `README.md`
  § Protocol Version Handshake, Part B.
- **Part D (hard-block MAJOR-mismatch gate).** Different reason: a remote
  seat's presence sidecar IS partially reachable already, via
  `remote_sweep_script`'s existing `PRES <name> <mtime>` wire records (see
  § What `coord-monitor.sh`'s remote channel does now above) — but that
  record carries only the sidecar file's **mtime**, for `SEAT STALE`
  staleness detection (`remote_presence_check` above), never the sidecar's
  actual field VALUES. A remote peer's `protocol_version` is not on the wire
  today; reaching it would need either a new wire record type or a full
  remote fetch-and-parse of the presence file's content, neither of which
  exists. Even setting that aside, Part D's round-9 hardening (main
  `README.md`) specifically requires a SIGNED source (a peer's own
  already-signed `HEARTBEAT` body, verified via `coord-verify.sh`) precisely
  *because* the unsigned presence sidecar is coord-dir-write-forgeable and
  round-9 closed a live-demonstrated presence-forgery hole on the LOCAL
  channel over it. Wiring Part D to the remote channel would mean either (a)
  trusting remote presence anyway — reopening the exact forgery class
  round-9 just closed, just remotely — or (b) building the equivalent
  signed-HEARTBEAT-lookup machinery against a remote bus dir, which means
  extending `verify_remote_buffer`'s fetch-then-verify path (§ Message
  Authenticity above) to scan multiple historical messages per peer instead
  of the single most-recent one it handles today. Both are real, separate
  pieces of work — explicitly out of scope for the round that hardened the
  local case.

**Net effect:** a remote seat running a MAJOR-mismatched protocol version is
NOT caught by `coordination-precommit-hook.sh`'s hard-block gate, and not
surfaced by any automated alert on the remote channel either. The only
visibility is manual: a remote seat's own `coord-monitor.sh` arm banner
prints its own `PROTOCOL %s` stamp directly (e.g. "PROTOCOL 1.5.0") to
whoever is watching that seat's own output — `coord-status.sh` does not
currently surface a peer's protocol version at all. This is an accepted
ceiling for 1.5.0, not an oversight.

---

## Cutover checklist (hub)

1. Ensure remote ssh alias works non-interactively (`ssh -o BatchMode=yes <alias> true`).
2. Create the remote bus dir; spokes write only their own `<identity>.md` there.
3. Arm **local** monitor as usual.
4. Arm **remote** monitor with both `--remote-host` and `--remote-bus-dir`. This
   also auto-writes `<coord-dir>/.remote-channels` (`<host> <bus-dir>`, one line
   per channel, idempotent) — `coordination-precommit-hook.sh` reads this to
   know a remote channel exists at all; **no separate manual step** (2026-08-09 —
   see § Message Authenticity above).
5. `coord-status.sh` should show both channels alive for the hub identity.
6. Enroll each remote seat's pubkey into the hub's own LOCAL `allowed_signers`
   via the existing `coord-keygen.sh --enroll` mechanism (§ Message
   Authenticity above) — there is no separate remote trust root to stand up.
7. A remote seat's own `coord-send.sh` calls must pass `--remote-seat` (§ Weak
   seats above) — MANDATORY-EXPLICIT, not inferred.
8. Add `.remote-channels` to the **site overlay's** `.gitignore` alongside the
   host/bus paths it names — never commit it into this portable pack (same
   rule as the host/bus paths themselves, below).
9. Keep deployment-specific host/bus paths in the **site overlay** (e.g. workspace `.claude/` or a small env wrapper) — never commit them into this portable pack.
10. **Adopting an EXISTING remote bus dir** (one that predates PROTOCOL 1.4.0,
    or was populated by some other process): archive or truncate its
    pre-1.4.0 unsigned history first. Every message already in that file
    predates signing and will read `⚠️ UNVERIFIED` under `--strict` forever —
    the hook's check 1c has no git-anchor equivalent for a remote-host file
    to age old content out of scope the way the local hard-block does, so an
    un-archived legacy file is a **permanent** block, not a one-time
    transition cost. (Doc-only guidance — no new state to build for this;
    the existing archive-hygiene convention already covers it.)
11. **Rotating a remote seat's signing key** (`coord-keygen.sh --rotate`)
    requires archiving that seat's remote mailbox **in the same operation**.
    Every message it signed with the OLD key stays in the file, and once the
    new key is enrolled, those old entries read `❓ UNKNOWN-SIGNER` /
    `❌ INVALID` against the hub's now-current `allowed_signers` — same
    permanent-block risk as item 10 above, for the same underlying reason
    (no git-anchor equivalent for a remote-host file). Rotate the key,
    archive the mailbox, done in one step — not two that can drift apart.
