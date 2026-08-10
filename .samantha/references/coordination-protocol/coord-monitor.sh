#!/usr/bin/env bash
# coord-monitor.sh — persistent coordination monitor for the Monitor tool.
#
# Replaces the one-shot poll-and-EXIT watcher. Instead of exiting to wake the
# agent (which forced a re-arm after every fire and left a deaf gap in between),
# this runs FOREVER under a persistent Monitor and emits each new peer message
# to stdout. Monitor turns stdout lines into in-chat events, batching lines
# emitted within ~200ms into ONE notification — so a whole multi-line WO arrives
# as a single event carrying the FULL message text. The agent reads the message
# straight from the notification; no separate file Read, no re-arm, no deaf gap.
#
# RECEIVE PATH (phase 2, 2026-07-12): event-driven via `fswatch` when available,
# so a peer write is delivered in ~0.1s instead of poll/2 (~0.5s at --poll 1).
# A slow safety-poll (--safety-poll, default 10s) runs alongside to catch any
# coalesced/dropped fs-event and to pace the heartbeat mutual-monitor. If fswatch
# is not on PATH (or its pipeline dies), it falls back to the fixed-interval poll
# loop — no hard dependency. Both modes call the SAME sweep + emit machinery.
#
# NETWORK FILESYSTEMS (--force-poll, 2026-07-18): fswatch is built on OS-level
# filesystem-change notifications (FSEvents on macOS, inotify on Linux). Those
# notifications are LOCAL-only — a write made by a peer process on a different
# machine onto a network-mounted coord-dir (SMB/SSHFS/NFS) does NOT generate a
# local fs-event, so fswatch_loop goes silently deaf while still reporting
# itself armed. --force-poll skips fswatch entirely (even if it's on PATH) and
# runs poll_loop from the start. Polling is safe here because delta detection
# is size-based (emit_new stats + reads the file), not event-based — a plain
# stat/read sweep works identically over a network mount. Use --poll >=2 on
# network mounts: SMB/NFS client-side attribute caching can delay a remote
# writer's size change becoming visible by a couple of seconds, so treat the
# effective latency as low seconds, not milliseconds.
#
# Usage (under the Monitor tool, persistent:true):
#   coord-monitor.sh --identity orchestrator --role orchestrator --dir <coorddir> [--poll 2] [--safety-poll 10] [--force-poll]
#   coord-monitor.sh --identity impl-<name> --role implementer --dir <coorddir> ...
#
# STAR watch set (structural, not conditional — PROCESS-NOTE 2026-07-28):
#   orchestrator  → every *.md except own outbox, QUEUE.md, PROJECTS.md, queue-*.md, *.archive.md
#   implementer   → ONLY orchestrator.md (no spoke-to-spoke, no self)
# --role is explicit; if omitted, identity `orchestrator` ⇒ hub, anything else ⇒ spoke
# (prefix inference is a fallback only — prefer --role so non-impl-* spoke names still work).
# EXCEPTION (2026-07-18): own-file HEARTBEAT/IDLE-KICK via emit_own_idle_kick — the only
# self-wake path when peers are quiet (pre-fix: implementer heartbeats never reached
# their own agent).
#
# ADDRESSED→PROJECT WAKE FILTER (PROTOCOL 1.3.0): implementer seats
#   - watch orchestrator.md PLUS same-project impl-*.md (sibling awareness)
#   - on hub outbox, emit only messages whose TO is ALL, this seat, or same-project
#   - other-project traffic and hub self-nudge are silent catch-up
#   - orchestrator watches everything (unchanged)
# Filter helpers: coord-address-filter.sh. Project from --project, roster project:, or
# identity impl-<project>[-<lane>].
#
# SIG-VERDICT ANNOTATION (PROTOCOL 1.4.0): each emitted chunk is annotated inline
# with its coord-verify.sh --tail verdict (✅ VERIFIED / ⚠️ UNVERIFIED / ❌ INVALID)
# before the message text — informational only, never affects wake/addressing
# mechanics or delivery. See README.md § Message Authenticity (SSH signing) and
# coordination-precommit-hook.sh for the hard-block counterpart.
#
# PROTOCOL_VERSION: sourced from PROTOCOL-VERSION beside this script (docs+scripts share stamp).
#
# REMOTE CHANNEL (REMOTE-SEATS.md §3.4, 2026-07-18 ratified — hub-only, a SECOND,
# separate coord-monitor.sh process, never combined with the local channel above):
#   coord-monitor.sh --identity orchestrator --dir <coorddir> --remote-host <alias> \
#     [--remote-bus-dir <path>] [--poll 2]
# Watches remote seats' outboxes under $REMOTE_BUS_DIR/*.md (excluding the hub's own
# mirrored orchestrator.md, same STAR no-self-watch exclusion as the local channel)
# PLUS a lighter presence-staleness sweep over $REMOTE_BUS_DIR/.presence/*. fswatch
# does not apply here at all (no local fs-events for a remote host) — always polls,
# clamped to >=2s per spec. Same size-offset delta math as the local channel, but
# batched into ONE ssh exec per sweep for the common (nothing changed) case: a single
# remote one-liner reports every watched file's current size, and only files that
# actually grew get a SECOND, per-file ssh call to fetch their new tail bytes — this
# keeps a quiet remote bus cheap regardless of how many seats it has. Writes its
# watcher pidfile to watcher-remote.pid (not watcher.pid) so local + remote channels
# never collide; heartbeat.sh's dead-man switch enumerates BOTH (see its own header).
# Does NOT run emit_own_idle_kick (no "own file" content lives in the remote bus
# watch-set — the hub's own outbox is local) and does NOT run check_heartbeat (the
# LOCAL channel already does that mutual-monitor; running it twice would just double
# every HEARTBEAT-DOWN alert into chat).

set -u

# Resolve pack-dir even when invoked via absolute path / symlink.
COORD_MONITOR_HOME=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=coord-address-filter.sh
. "$COORD_MONITOR_HOME/coord-address-filter.sh"
# shellcheck source=coord-presence.sh
. "$COORD_MONITOR_HOME/coord-presence.sh"
# shellcheck source=coord-receipt.sh
. "$COORD_MONITOR_HOME/coord-receipt.sh"
# shellcheck source=coord-keygen.sh
# Sourcing (not executing) coord-keygen.sh: pulls in _acquire_signers_lock/
# _release_signers_lock (generic mkdir-based advisory lock, not actually
# allowed_signers-specific — see that file's own header) so the
# .remote-channels auto-write below (PROTOCOL 1.4.0 remote-seat extension)
# reuses the SAME race-safe read-decide-write pattern coord-keygen.sh's own
# --enroll already uses, instead of a second, potentially-drifting copy.
[ -f "$COORD_MONITOR_HOME/coord-keygen.sh" ] && . "$COORD_MONITOR_HOME/coord-keygen.sh"
# shellcheck source=coord-remote-verify.sh
# PROTOCOL 1.4.0 remote-seat extension (2026-08-09): shared fetch-a-buffer ->
# name-it-correctly -> verify-it-against-the-hub's-own-local-allowed_signers
# helper (verify_remote_buffer), used by remote_emit_new below AND
# coordination-precommit-hook.sh — one definition so the two can never drift
# on how a remote buffer gets verified. verify_remote_buffer itself stays
# BEST-EFFORT (remote_emit_new checks for its presence before calling it —
# a missing/erroring coord-verify.sh never blocks message delivery, same
# posture as the local channel's SIG-verdict annotation).
#
# coord_remote_shquote, defined in the SAME file (round-5, 2026-08-09 —
# Cipher CRITICAL RCE fix), is NOT best-effort: it is a hard dependency for
# --remote-host, enforced right after arg parsing below (see the ERROR/exit 2
# check) — this script refuses to arm the remote channel at all rather than
# ever construct a remote command from an unescaped remote-supplied filename.
[ -f "$COORD_MONITOR_HOME/coord-remote-verify.sh" ] && . "$COORD_MONITOR_HOME/coord-remote-verify.sh"
PROTOCOL_VERSION="unknown"
if [ -f "$COORD_MONITOR_HOME/PROTOCOL-VERSION" ]; then
  # shellcheck source=PROTOCOL-VERSION
  . "$COORD_MONITOR_HOME/PROTOCOL-VERSION"
fi

# F+ (AMEND-PROCESS-HYGIENE-20260726): --help must NEVER claim a seat pidfile.
# Previously `*) shift;;` swallowed --help and fell through to the default
# identity=orchestrator pidfile write — Cursor hung --help stole hub watcher.pid.
for _a in "$@"; do
  case "$_a" in
    -h|--help)
      printf 'Usage: coord-monitor.sh --identity <id> [--role orchestrator|implementer] [--project <name>] --dir <coorddir> [--poll N] [--safety-poll N] [--force-poll]\n'
      printf '       coord-monitor.sh --identity <id> --dir <coorddir> --remote-host <alias> --remote-bus-dir <path> [--poll N]\n'
      printf 'STAR: hub watches all peers; spoke watches orchestrator.md + same-project impl-*.md.\n'
      printf 'Spoke hub-outbox filter: TO in {me, ALL, same-project seats}. PROTOCOL %s\n' "$PROTOCOL_VERSION"
      printf 'Persistent STAR inbox monitor. Exits 0 on help WITHOUT writing any pidfile.\n'
      exit 0
      ;;
  esac
done
IDENT="orchestrator"
ROLE=""           # orchestrator | implementer — empty ⇒ infer from IDENT
PROJECT_EXPLICIT=""  # optional --project; else roster project: / identity inference
DIR="${COORD_DIR:-$PWD/.samantha/coord}"
POLL=2            # fallback poll interval (used only when fswatch is unavailable, or --force-poll)
SAFETY_POLL=10    # event-mode slow-poll backstop + heartbeat-check cadence
FORCE_POLL=0      # skip fswatch entirely and run poll_loop — for network-mounted coord-dirs
REMOTE_HOST=""    # §3.4 remote channel — set = this invocation watches $REMOTE_BUS_DIR over ssh instead
REMOTE_BUS_DIR=""   # optional remote channel — REQUIRED with --remote-host (see advanced/REMOTE-SEATS.md)
while [ $# -gt 0 ]; do
  case "$1" in
    --identity) IDENT="$2"; shift 2;;
    --role) ROLE="$2"; shift 2;;
    --project) PROJECT_EXPLICIT="$2"; shift 2;;
    --dir) DIR="$2"; shift 2;;
    --poll) POLL="$2"; shift 2;;
    --safety-poll) SAFETY_POLL="$2"; shift 2;;
    --force-poll) FORCE_POLL=1; shift;;
    --remote-host) REMOTE_HOST="$2"; shift 2;;
    --remote-bus-dir) REMOTE_BUS_DIR="$2"; shift 2;;
    -h|--help) exit 0;;  # already handled above; keep for completeness
    *) shift;;
  esac
done

# Resolve STAR role (explicit --role wins; else identity-based fallback).
if [ -z "$ROLE" ]; then
  if [ "$IDENT" = "orchestrator" ]; then
    ROLE="orchestrator"
  else
    ROLE="implementer"
  fi
fi
case "$ROLE" in
  orchestrator|implementer) ;;
  *)
    printf '┃ coord-monitor: invalid --role %s (want orchestrator|implementer)\n' "$ROLE" >&2
    exit 2
    ;;
esac

# Project scope for spoke filter + same-project peer watch (PROTOCOL 1.3.0).
PROJECT=$(protocol_resolve_project "$IDENT" "$PROJECT_EXPLICIT" "$DIR/$IDENT.md" "$DIR")
if [ "$ROLE" = "implementer" ] && [ -z "$PROJECT" ]; then
  printf '┃ coord-monitor: WARN implementer %s has no resolvable project — hub filter falls back to self|ALL only; pass --project or set project: in presence\n' "$IDENT" >&2
fi

# §3.4: remote channel polls only — no fs-events exist for a different machine.
# poll >= 2s per spec; clamp rather than silently accept a tighter interval that
# would just hammer ssh for no benefit (there is no event-driven path to fall back
# FROM here — --force-poll's whole point doesn't apply, this mode has no fswatch
# branch to skip in the first place).
# Portable rule: remote channel requires an explicit bus dir (no baked project path).
if [ -n "$REMOTE_HOST" ] && [ -z "$REMOTE_BUS_DIR" ]; then
  echo "ERROR: --remote-host requires --remote-bus-dir <path> (see advanced/REMOTE-SEATS.md)." >&2
  exit 2
fi

# HARD DEPENDENCY (round-5, 2026-08-09 — Cipher CRITICAL, live-demonstrated
# RCE): the remote channel constructs ssh command strings from filenames the
# REMOTE HOST lists — i.e. attacker-controlled if anyone can write into the
# remote bus dir, exactly the population this extension exists to distrust.
# coord_remote_shquote (coord-remote-verify.sh) is the ONLY thing standing
# between that and command injection. This used to be sourced best-effort
# ("degrade to unverified-but-functional if missing") because the file's ONLY
# job was thought to be optional signature verification — that framing
# predates the RCE finding and is no longer safe: a missing quoting helper
# must never silently fall back to unescaped interpolation. Refuse to arm.
if [ -n "$REMOTE_HOST" ] && ! command -v coord_remote_shquote >/dev/null 2>&1; then
  echo "ERROR: --remote-host requires coord-remote-verify.sh beside this script (missing coord_remote_shquote — the shell-quoting helper required to safely build remote commands from remote-host-supplied filenames; see advanced/REMOTE-SEATS.md § Message Authenticity)." >&2
  exit 2
fi

if [ -n "$REMOTE_HOST" ] && [ "$POLL" -lt 2 ] 2>/dev/null; then
  printf '┃ coord-monitor: --poll %s below the §3.4 remote-channel floor — clamping to 2s\n' "$POLL"
  POLL=2
fi

STATEDIR="$DIR/.watch-state/$IDENT/monitor"
mkdir -p "$STATEDIR"

# Claim the watcher-liveness slot. heartbeat.sh and coord-status.sh both check
# <identity>/watcher.pid; writing our own PID there lets the EXISTING dead-man
# backstop watch THIS monitor — if it ever dies, the heartbeat fires exit-42 and
# the agent relaunches. Same safety net, zero new machinery. (Stop the old
# one-shot watcher BEFORE launching this, or they fight over the file.)
# §3.4: the remote channel claims a SEPARATE pidfile (watcher-remote.pid) so it
# never collides with a simultaneously-running LOCAL channel for the same identity
# — the hub runs both channels as two independent coord-monitor.sh processes.
if [ -n "$REMOTE_HOST" ]; then
  WATCHER_PID_FILE="$DIR/.watch-state/$IDENT/watcher-remote.pid"
else
  WATCHER_PID_FILE="$DIR/.watch-state/$IDENT/watcher.pid"
fi
printf '%s' "$$" > "$WATCHER_PID_FILE"
presence_ensure_from_mailbox "$DIR" "$IDENT"
presence_set "$DIR" "$IDENT" "watcher_pid" "$$"
presence_set "$DIR" "$IDENT" "role" "$ROLE"
presence_set "$DIR" "$IDENT" "protocol_version" "$PROTOCOL_VERSION"
[ -n "$PROJECT" ] && presence_set "$DIR" "$IDENT" "project" "$PROJECT"

# ── §3.4 remote channel: a fully separate code path that exits below, before
#    reaching any local-mode function/variable (watched/emit_new/sweep/fswatch/
#    etc.) — the local-mode code from here to the bottom of the file is verbatim
#    unreached, and unmodified, when --remote-host is absent. ──
if [ -n "$REMOTE_HOST" ]; then
  remote_offset_file() { printf '%s/remote.%s.off' "$STATEDIR" "$1"; }

  # ONE ssh exec per sweep for the common case: "MSG <name> <size>" for every
  # *.md in the bus dir plus "PRES <name> <mtime>" for every .presence/* file.
  # Round-5 (2026-08-09, Rook BLOCKER): this used to filter self/QUEUE.md/
  # PROJECTS.md/queue-*.md server-side (and had DRIFTED from the local
  # watched()'s exclusion set — missing archives entirely). Filtering now
  # happens LOCALLY, uniformly, via remote_should_process_name() below (which
  # composes the shared coord_is_seat_outbox_basename() predicate with self-
  # exclusion) — this script lists everything and applies ONE filter after
  # the fact, instead of maintaining a second, independently-drifting
  # exclusion list embedded in remote-executed shell text.
  # Embedded single-quoted: the script is 100% program-constructed from our
  # own vars ($REMOTE_BUS_DIR — a local, operator-supplied CLI arg, never
  # remote-supplied), grep-verified to contain zero embedded single quotes
  # (see remote_sweep_sizes below), and this ALSO avoids any pipe/stdin
  # trickery since there's no payload competing for stdin here at all
  # (read-only listing).
  #
  # ROUND-6 (2026-08-09, Cipher — live-demonstrated): the wire format below
  # is ONE RECORD PER LINE ("MSG <name> <size>" / "PRES <name> <mtime>"),
  # parsed by sweep_remote()'s `while IFS=' ' read -r kind name val` on the
  # RECEIVING side. A real filesystem permits a literal embedded NEWLINE (or
  # CR) in a filename — only "/" and NUL are forbidden. A file named e.g.
  # "a-evil.md\nMSG victim.md 999999999" gets listed here as ONE $f, but
  # `printf "MSG %s %s\n" "$f" ...` then emits it as TWO lines on the wire —
  # the second one a fully-formed, attacker-chosen FAKE record. Cipher
  # live-confirmed this poisons a DIFFERENT peer's offset tracker: the fake
  # oversized size baselines "victim.md" artificially high, so its real
  # (smaller) subsequent growth hits the "rewritten/archived, baseline reset"
  # branch in remote_emit_new and is silently DISCARDED — never fetched,
  # never verified, no error. This is a distinct sink from the round-5
  # command-injection fix (that one targeted the FETCH command; this one
  # targets the LISTING protocol itself) and needed its own fix: reject any
  # name containing an embedded newline/CR at the point it's listed, before
  # it can ever be split into extra fake wire records. Consumption-side
  # defense in depth for the same class of bad name lives in
  # coord-remote-verify.sh's verify_remote_buffer (extended alongside this).
  remote_sweep_script() {
    cat <<REMOTESCRIPT
cd "$REMOTE_BUS_DIR" 2>/dev/null || exit 0
_rc_nl=\$(printf "\nX"); _rc_nl=\${_rc_nl%X}
_rc_cr=\$(printf "\rX"); _rc_cr=\${_rc_cr%X}
for f in *.md; do
  [ -e "\$f" ] || continue
  case "\$f" in *"\$_rc_nl"*|*"\$_rc_cr"*) continue ;; esac
  printf "MSG %s %s\n" "\$f" "\$(wc -c < "\$f" | tr -d " ")"
done
[ -d .presence ] && for f in .presence/*; do
  [ -e "\$f" ] || continue
  case "\$f" in *"\$_rc_nl"*|*"\$_rc_cr"*) continue ;; esac
  printf "PRES %s %s\n" "\$(basename "\$f")" "\$(stat -c %Y "\$f" 2>/dev/null || echo 0)"
done
REMOTESCRIPT
  }

  # remote_should_process_name <name> — composes the shared
  # coord_is_seat_outbox_basename() infra-file exclusion with this monitor's
  # own IDENT-specific self-exclusion (excluding the hub's own mirrored
  # outbox from the remote bus, same STAR no-self-watch rule as the local
  # channel's watched()).
  remote_should_process_name() {
    [ "$1" = "$IDENT.md" ] && return 1
    coord_is_seat_outbox_basename "$1"
  }

  remote_sweep_sizes() {
    local script; script=$(remote_sweep_script)
    case "$script" in *"'"*)
      printf '┃ COORD ⚠️ INTERNAL BUG — remote sweep script contains a single quote, refusing to run it\n' >&2
      return 1
      ;;
    esac
    # -n: redirect ssh's own stdin from /dev/null. Round-5 (2026-08-09):
    # sweep_remote() below runs this via `done < <(remote_sweep_sizes)`,
    # redirecting fd0 for its WHOLE loop body (including remote_emit_new's
    # own ssh call) to this process substitution's pipe. Without -n, ssh (no
    # -n/-t) reads+forwards local stdin by default regardless of whether the
    # remote command uses it — it would race to drain that pipe itself,
    # silently truncating the outer `read` loop's remaining input. None of
    # this script's remote commands read stdin; -n removes the hazard.
    ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE_HOST" "bash -c '$script'" 2>/dev/null
  }

  remote_emit_new() {
    local name="$1" cur="$2" of prev chunk chunk_raw filtered verify_out q_bus q_name
    of=$(remote_offset_file "$name"); prev=$(cat "$of" 2>/dev/null || echo 0)
    [ -z "${cur:-}" ] && return 0
    if [ "$cur" -lt "$prev" ]; then
      printf '┃ COORD ⟳ %s (remote) rewritten/archived (%s→%s bytes) — baseline reset @ %s\n' \
        "$name" "$prev" "$cur" "$(date -u +%FT%TZ)"
      printf '%s' "$cur" > "$of"; return 0
    fi
    if [ "$cur" -gt "$prev" ]; then
      # Round-5 CRITICAL (2026-08-09, Cipher — live-demonstrated RCE): $name
      # came from a `for f in *.md` listing run ON THE REMOTE HOST — as
      # trustworthy as whoever can write a file into the remote bus dir,
      # exactly the population this extension exists to distrust. A file
      # named e.g. "x'; id; echo '.md" used to execute arbitrary code here,
      # before any signature check ever ran. coord_remote_shquote (hard
      # dependency, enforced at arg-parse time above) closes this — every
      # value spliced into the remote command string goes through it.
      q_bus=$(coord_remote_shquote "$REMOTE_BUS_DIR")
      q_name=$(coord_remote_shquote "$name")
      chunk=$(ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE_HOST" "tail -c +$((prev + 1)) $q_bus/$q_name" 2>/dev/null) || chunk=""
      chunk_raw="$chunk"
      printf '%s' "$cur" > "$of"
      if [ "$ROLE" = "implementer" ]; then
        if ! filtered=$(spoke_filter_delta "$IDENT" "$PROJECT" "$chunk"); then
          return 0
        fi
        chunk=$filtered
      fi
      printf '┃ COORD ▼ new message on %s (remote) · %s bytes @ %s\n' "$name" "$((cur - prev))" "$(date -u +%FT%TZ)"
      printf '%s' "$chunk"
      # PROTOCOL 1.4.0 remote-seat extension (2026-08-09): informational
      # SIG-verdict annotation, same as the local channel's emit_new — this
      # used to be entirely missing for the remote channel (REMOTE-SEATS.md's
      # own documented scoping gap; see that file's § Message Authenticity
      # for the closed history). Verified against the RAW (pre-spoke-filter)
      # chunk, same reasoning as the local channel: signature validity is a
      # property of the underlying message, independent of whether THIS
      # seat's addressing filter chooses to display it. Batched block AFTER
      # the message text, not interleaved (same round-2/item-17-reversion
      # reasoning as the local channel — see emit_new below). Best-effort:
      # a missing coord-remote-verify.sh/coord-verify.sh never blocks
      # delivery of the message itself, same posture as the local channel.
      if command -v verify_remote_buffer >/dev/null 2>&1 && [ -x "$COORD_MONITOR_HOME/coord-verify.sh" ]; then
        verify_out=$(printf '%s' "$chunk_raw" | verify_remote_buffer "$DIR" "$name" "$COORD_MONITOR_HOME/coord-verify.sh" 2>/dev/null | grep -E '^(✅|⚠️|❓|❌)') || true
        [ -n "$verify_out" ] && printf '%s\n' "$verify_out" | sed 's/^/┃ COORD SIG /'
      fi
      printf '┃ COORD ▲ end %s (remote) — re-run coord-status.sh if you acted on a DEPLOY/DECISION\n' "$name"
    fi
    return 0
  }

  # Presence staleness (§5, soft threshold 20min — a mid-WO ping-then-reclaim
  # threshold of 2h is a hub-decision escalation, not this monitor's job; this
  # only surfaces the signal once per stale-transition, never every tick).
  PRESENCE_STALE_SOFT=1200
  remote_presence_check() {
    local name="$1" mtime="$2" of now age wasstale
    [ -z "${mtime:-}" ] && return 0
    of="$STATEDIR/remote.presence.$name.state"
    now=$(date +%s); age=$((now - mtime))
    wasstale=$(cat "$of" 2>/dev/null || echo 0)
    if [ "$age" -ge "$PRESENCE_STALE_SOFT" ]; then
      if [ "$wasstale" != "1" ]; then
        printf '┃ COORD ⚠️ SEAT STALE — %s presence not touched in %ss (soft threshold %ss) @ %s\n' \
          "$name" "$age" "$PRESENCE_STALE_SOFT" "$(date -u +%FT%TZ)"
        printf '1' > "$of"
      fi
    else
      [ "$wasstale" = "1" ] && printf '┃ COORD ✅ %s presence RECOVERED @ %s\n' "$name" "$(date -u +%FT%TZ)"
      printf '0' > "$of"
    fi
    return 0
  }

  sweep_remote() {
    local kind name val
    while IFS=' ' read -r kind name val; do
      [ -z "$kind" ] && continue
      case "$kind" in
        MSG)  remote_should_process_name "$name" && remote_emit_new "$name" "$val" ;;
        PRES) remote_presence_check "$name" "$val" ;;
      esac
    done < <(remote_sweep_sizes)
  }

  # Initialize offsets to CURRENT end so arm streams only NEW messages, never replays history.
  while IFS=' ' read -r kind name val; do
    [ "$kind" = "MSG" ] && remote_should_process_name "$name" && printf '%s' "$val" > "$(remote_offset_file "$name")"
  done < <(remote_sweep_sizes)

  # .remote-channels auto-write (PROTOCOL 1.4.0 remote-seat extension,
  # 2026-08-09, real gap 2): coordination-precommit-hook.sh has no way to
  # know a remote channel even exists (a remote bus dir lives on a different
  # host by definition — nothing on the local filesystem points at it)
  # unless something writes that down. This used to be left as a manual
  # documentation step in REMOTE-SEATS.md's Cutover Checklist — exactly the
  # kind of quiet gap this whole amendment has been closing elsewhere (an
  # operator forgetting one manual step silently leaves the hard-block blind
  # to a whole channel). Auto-written HERE, at arm time, idempotent
  # (de-duplicated, one line per distinct host+bus-dir pair), lock-guarded
  # against a concurrent second remote channel arming at the same instant.
  # Gitignored by convention in the ADOPTING project (site-specific
  # host/bus paths never get committed — same rule as item 6 of the Cutover
  # Checklist below).
  _RC_FILE="$DIR/.remote-channels"
  _RC_LINE="$REMOTE_HOST $REMOTE_BUS_DIR"
  if command -v _acquire_signers_lock >/dev/null 2>&1; then
    if _acquire_signers_lock "$_RC_FILE"; then
      touch "$_RC_FILE" 2>/dev/null || true
      if ! grep -qxF "$_RC_LINE" "$_RC_FILE" 2>/dev/null; then
        _rc_tmp=$(mktemp "$_RC_FILE.XXXXXX") || _rc_tmp=""
        if [ -n "$_rc_tmp" ]; then
          cat "$_RC_FILE" > "$_rc_tmp" 2>/dev/null || true
          printf '%s\n' "$_RC_LINE" >> "$_rc_tmp"
          mv "$_rc_tmp" "$_RC_FILE"
        fi
        unset _rc_tmp
      fi
      _release_signers_lock "$_RC_FILE"
    else
      printf '┃ coord-monitor ⚠️ could not lock %s to register this remote channel — coordination-precommit-hook.sh may not see it. Add "%s" to it manually.\n' \
        "$_RC_FILE" "$_RC_LINE" >&2
    fi
  fi
  unset _RC_FILE _RC_LINE

  printf '┃ coord-monitor ARMED for %s (REMOTE channel, §3.4) @ %s — host: %s · bus: %s · poll: %ss\n' \
    "$IDENT" "$(date -u +%FT%TZ)" "$REMOTE_HOST" "$REMOTE_BUS_DIR" "$POLL"

  while true; do sweep_remote; sleep "$POLL"; done
  exit 0
fi

# Peer files — STAR + project scope (PROTOCOL 1.3.0):
#   hub (orchestrator)  → all *.md except own / QUEUE / PROJECTS / queue-* / archives
#   spoke (implementer) → orchestrator.md + same-project impl-*.md (not self, not other projects)
watched() {
  local f b stem p
  if [ "$ROLE" = "implementer" ]; then
    f="$DIR/orchestrator.md"
    [ -e "$f" ] && printf '%s\n' "$f"
    if [ -n "$PROJECT" ]; then
      for f in "$DIR"/impl-*.md; do
        [ -e "$f" ] || continue
        b=$(basename "$f" .md)
        [ "$b" = "$IDENT" ] && continue
        p=$(protocol_project_of_identity "$b")
        [ "$p" = "$PROJECT" ] || continue
        printf '%s\n' "$f"
      done
    fi
    return 0
  fi
  for f in "$DIR"/*.md; do
    [ -e "$f" ] || continue
    b=$(basename "$f")
    [ "$b" = "$IDENT.md" ] && continue
    # Round-5 (2026-08-09, Rook BLOCKER): shared with the remote channel's
    # remote_should_process_name() and coordination-precommit-hook.sh's check
    # 1c — see coord-address-filter.sh's coord_is_seat_outbox_basename for why
    # this used to be three independently-drifting exclusion lists.
    coord_is_seat_outbox_basename "$b" || continue
    printf '%s\n' "$f"
  done
}

offset_file() { printf '%s/%s.off' "$STATEDIR" "$(basename "$1")"; }
size_of() { wc -c < "$1" 2>/dev/null | tr -d ' '; }

emit_new() {
  local f="$1" of cur prev chunk filtered
  of=$(offset_file "$f"); cur=$(size_of "$f"); prev=$(cat "$of" 2>/dev/null || echo 0)
  [ -z "${cur:-}" ] && return 0
  if [ "$cur" -lt "$prev" ]; then
    printf '┃ COORD ⟳ %s rewritten/archived (%s→%s bytes) — baseline reset @ %s\n' \
      "$(basename "$f")" "$prev" "$cur" "$(date -u +%FT%TZ)"
    printf '%s' "$cur" > "$of"; return 0
  fi
  if [ "$cur" -gt "$prev" ]; then
    chunk=$(tail -c "+$((prev+1))" "$f")
    # Lines in the RAW (pre-filter) chunk — used only to size the coord-verify.sh
    # --tail window below, so a project-filtered spoke still verifies against the
    # actual file region the new bytes came from, not the (possibly smaller)
    # post-filter chunk.
    raw_lines=$(printf '%s' "$chunk" | wc -l | tr -d ' ')
    [ -z "${raw_lines:-}" ] && raw_lines=0
    # Advance offset + Rule-4 receipt BEFORE wake decision — silent catch-up must not
    # re-deliver on the next sweep (PROTOCOL 1.2.1 addressed wake filter).
    printf '%s' "$cur" > "$of"
    # Advance the pre-commit hook's Rule-4 mailbox receipt too (ratified 2026-07-16, impl
    # PROCESS-NOTE 2026-07-15): streamed-into-chat == delivered == read, matching the retired
    # watcher's behavior — without this, a caught-up implementer gets commit-denied until a
    # manual `wc -c > receipt`. GROWTH PATH ONLY: on shrink/rotation (above) the receipt is
    # deliberately left stale-large so the hook's F6 forces one catch-up read of the new file.
    # Spoke silent-filter still advances receipt: the bytes were observed; they were not for us.
    # Two-field offset+verified_sha256 format (item 1, 2026-08-09) via coord-receipt.sh's
    # write_receipt — see that file's header for why a bare integer was forgeable.
    write_receipt "$DIR/.watch-state/$IDENT/$(basename "$f").size" "$cur" "$f" 2>/dev/null || true

    if [ "$ROLE" = "implementer" ]; then
      # Hub outbox: project filter. Same-project peer outboxes: emit whole delta
      # (watch set already excludes other projects).
      case "$(basename "$f")" in
        orchestrator.md)
          if ! filtered=$(spoke_filter_delta "$IDENT" "$PROJECT" "$chunk"); then
            return 0
          fi
          chunk=$filtered
          ;;
      esac
    fi
    # One tight burst → Monitor batches it into a single notification carrying the whole message.
    printf '┃ COORD ▼ new message on %s · %s bytes @ %s\n' "$(basename "$f")" "$((cur-prev))" "$(date -u +%FT%TZ)"
    printf '%s' "$chunk"
    # PROTOCOL 1.4.0 — informational SIG-verdict annotation only; never affects
    # wake/addressing mechanics. Best-effort: a missing/erroring coord-verify.sh
    # never blocks delivery of the message itself. Printed as a single batched
    # block AFTER the message text, not interleaved per-message: an earlier
    # per-message interleaving (item 17, 2026-08-09) paired the Nth verdict
    # with the Nth displayed message block, but on the spoke path the verdict
    # list is computed from coord-verify.sh's raw unfiltered window while the
    # displayed chunk has messages dropped by spoke_filter_delta — the two
    # can disagree in length/order, so ordinal pairing silently mispairs a
    # verdict with the wrong message (Rook, round-2 review). Not worth
    # hardening pairing further for an informational-only annotation.
    if [ -x "$COORD_MONITOR_HOME/coord-verify.sh" ]; then
      verify_out=$("$COORD_MONITOR_HOME/coord-verify.sh" --dir "$DIR" --file "$f" --tail "$((raw_lines + 5))" 2>/dev/null | grep -E '^(✅|⚠️|❓|❌)') || true
      [ -n "$verify_out" ] && printf '%s\n' "$verify_out" | sed 's/^/┃ COORD SIG /'
    fi
    printf '┃ COORD ▲ end %s — re-run coord-status.sh if you acted on a DEPLOY/DECISION\n' "$(basename "$f")"
  fi
  return 0
}

# Self-nudge: own outbox is NOT in watched() (STAR no-self-watch for peer chatter).
# But 💓 HEARTBEAT / ⚡ IDLE-KICK / ⚠️ WATCHER-DOWN on the own file MUST wake this seat —
# otherwise an idle implementer never learns it is idle (Max has to poke by hand).
# STATUS/ACK we write ourselves advance the offset silently (no emit → no self-loop).
emit_own_idle_kick() {
  local f="$DIR/$IDENT.md" of cur prev chunk
  [ -f "$f" ] || return 0
  of=$(offset_file "$f"); cur=$(size_of "$f"); prev=$(cat "$of" 2>/dev/null || echo 0)
  [ -z "${cur:-}" ] && return 0
  if [ "$cur" -lt "$prev" ]; then
    printf '%s' "$cur" > "$of"; return 0
  fi
  if [ "$cur" -gt "$prev" ]; then
    chunk=$(tail -c "+$((prev+1))" "$f")
    printf '%s' "$cur" > "$of"
    # Always advance offset — including for our own STATUS writes.
    if printf '%s' "$chunk" | grep -qE '^### .*(💓 HEARTBEAT|⚠️ WATCHER-DOWN)|^⚡ \*\*IDLE-KICK\*\*'; then
      printf '┃ IDLE-KICK ▼ own-file nudge on %s · %s bytes @ %s\n' \
        "$(basename "$f")" "$((cur-prev))" "$(date -u +%FT%TZ)"
      printf '%s' "$chunk"
      printf '\n┃ IDLE-KICK ▲ end — mid-task CONTINUE; else start idle_policy work NOW (do not stand by)\n'
    fi
  fi
  return 0
}

# Initialize offsets to the CURRENT end so we stream only NEW messages, never replay history.
for f in $(watched); do printf '%s' "$(size_of "$f")" > "$(offset_file "$f")"; done
# Own file: baseline at EOF too (first HEARTBEAT after arm is the first kick).
OWN_FILE="$DIR/$IDENT.md"
[ -f "$OWN_FILE" ] && printf '%s' "$(size_of "$OWN_FILE")" > "$(offset_file "$OWN_FILE")"

# sweep: peer deltas + own-file idle-kick filter.
sweep() {
  local f
  for f in $(watched); do emit_new "$f"; done
  emit_own_idle_kick
}

# MUTUAL MONITORING. The heartbeat watches THIS monitor (via watcher.pid) and exit-42s if
# it dies; this monitor watches the heartbeat (via heartbeat.pid) and ALERTS in-chat if IT
# dies — while staying alive (no exit needed). So a single failure of EITHER process is
# always caught by the survivor; only a simultaneous double-death is uncovered. Alert once
# per down-transition, with a ~3-tick tolerance so a heartbeat relaunch doesn't false-alarm.
HB_PID_FILE="$DIR/.watch-state/$IDENT/heartbeat.pid"
hb_dead=0; hb_alerted=0
# D: bridged liveness — process must exist AND ppid≠1 (unless COORD_ALLOW_PPID1).
heartbeat_bridged_alive() {
  local hp pp
  hp=$(cat "$HB_PID_FILE" 2>/dev/null)
  [ -n "$hp" ] && ps -p "$hp" >/dev/null 2>&1 || return 1
  pp=$(ps -p "$hp" -o ppid= 2>/dev/null | tr -d ' ')
  if [ -z "${COORD_ALLOW_PPID1:-}" ] && [ "$pp" = "1" ]; then
    return 1
  fi
  return 0
}
check_heartbeat() {
  local hp; hp=$(cat "$HB_PID_FILE" 2>/dev/null)
  if heartbeat_bridged_alive; then
    [ "$hb_alerted" = 1 ] && printf '┃ COORD ✅ heartbeat RECOVERED (pid %s) @ %s\n' "$hp" "$(date -u +%FT%TZ)"
    hb_dead=0; hb_alerted=0
  else
    hb_dead=$((hb_dead+1))
    if [ "$hb_dead" -ge 3 ] && [ "$hb_alerted" = 0 ]; then
      printf '┃ COORD ⚠️ HEARTBEAT DOWN @ %s (mutual-monitor) — the liveness backstop is gone (missing or ORPHAN ppid=1); relaunch heartbeat.sh --identity %s (Bash run_in_background + notify_on_output / dangerouslyDisableSandbox), then coord-status.sh to confirm BOTH ALIVE\n' "$(date -u +%FT%TZ)" "$IDENT"
      hb_alerted=1
    fi
  fi
}

# ── run modes (both call sweep + check_heartbeat; only the trigger differs) ──
poll_loop() {   # fallback: fixed-interval poll — used iff fswatch is absent, after an fswatch exit,
  # or --force-poll (network-mounted coord-dirs, where fs-events never see a remote peer's write)
  while true; do sweep; check_heartbeat; sleep "$POLL"; done
}

fswatch_loop() {   # primary: event-driven. Delivers a peer write in ~0.1s; a SAFETY_POLL-second
  # read timeout drives the slow-poll safety net + heartbeat cadence; fswatch death → fall back.
  #
  # bash 3.2 (macOS system bash) returns rc=1 from `read -t` on BOTH timeout AND EOF (the >128
  # timeout convention is 4.0+), so rc alone can't tell them apart. We capture fswatch's PID via a
  # FIFO and disambiguate with `kill -0`: fswatch ALIVE on a nonzero read = timeout (safety sweep,
  # stay in event mode); fswatch DEAD = EOF (break → caller drops to poll_loop, never going deaf).
  # -e '\.watch-state' excludes the offset dir emit_new writes to (FSEvents is recursive on macOS),
  # else every offset write would retrigger fswatch. -l 0.1 = 100ms batch latency.
  local rc _p fw_pid fifo
  fifo="$STATEDIR/fsevents.$$.fifo"
  rm -f "$fifo"; mkfifo "$fifo" 2>/dev/null || return 1     # no FIFO → caller falls back to poll
  fswatch -0 -l 0.1 -e '\.watch-state' "$DIR" > "$fifo" 2>/dev/null &
  fw_pid=$!
  # Cleanup so fswatch never orphans. TERM/INT must EXIT (an external stop = die), NOT fall through —
  # otherwise the trap kills fswatch, the read below sees EOF, and we'd wrongly drop into poll_loop and
  # survive the stop (→ a zombie second monitor at the next cutover). Only fswatch dying ON ITS OWN
  # (no signal) reaches the EOF→poll fallback path.
  trap 'kill "$fw_pid" 2>/dev/null; rm -f "$fifo"; exit 0' TERM INT
  trap 'kill "$fw_pid" 2>/dev/null; rm -f "$fifo"' EXIT
  exec 3< "$fifo"
  while true; do
    IFS= read -r -d '' -t "$SAFETY_POLL" _p <&3; rc=$?
    if [ "$rc" -ne 0 ]; then
      kill -0 "$fw_pid" 2>/dev/null || break   # nonzero + fswatch dead = EOF → fall back to poll
    fi                                          # nonzero + fswatch alive = timeout → safety sweep
    sweep; check_heartbeat                      # rc 0 (event) or timeout: both sweep
  done
  exec 3<&-
  kill "$fw_pid" 2>/dev/null; rm -f "$fifo"; trap - EXIT TERM INT
  return 0
}

if [ "$FORCE_POLL" = 1 ]; then
  MODE="poll ${POLL}s (--force-poll — fswatch skipped; use for network-mounted coord-dirs, e.g. SMB/SSHFS/NFS)"
elif command -v fswatch >/dev/null 2>&1; then
  MODE="fswatch event-driven (latency 0.1s · safety-poll ${SAFETY_POLL}s)"
else
  MODE="poll ${POLL}s (fswatch not on PATH — install it for event-driven receive)"
fi
printf '┃ coord-monitor ARMED for %s (role=%s project=%s) @ %s — watching: %s · MODE: %s · PROTOCOL %s · mutual-monitoring the heartbeat\n' \
  "$IDENT" "$ROLE" "${PROJECT:-—}" "$(date -u +%FT%TZ)" "$(watched | xargs -n1 basename 2>/dev/null | tr '\n' ' ')" "$MODE" "$PROTOCOL_VERSION"

if [ "$FORCE_POLL" != 1 ] && command -v fswatch >/dev/null 2>&1; then
  fswatch_loop
  printf '┃ COORD ⚠️ fswatch pipeline exited @ %s — falling back to %ss poll loop (receive still works, just slower)\n' "$(date -u +%FT%TZ)" "$POLL"
  poll_loop
else
  poll_loop
fi
