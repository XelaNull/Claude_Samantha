#!/usr/bin/env bash
# coord-send.sh — the SEND (publish) half of the coordination chat-room.
# Symmetric to coord-monitor.sh (the receive/subscribe half). The append-only
# coord files are the message bus; this script is how you post to it correctly
# without hand-crafting headers.
#
# It auto-fills: the UTC timestamp, your identity (FROM), and the canonical
# header format; appends atomically to YOUR OWN outbox (<identity>.md — which
# structurally enforces the "write only to your own file" rule); and reads the
# append back to VERIFY it landed before returning success.
#
# SIGNING (PROTOCOL 1.4.0 — see README.md § Message Authenticity): every
# message posted by this script is SSH-signed (ssh-keygen -Y sign, coord-dir
# trust root: allowed_signers). If no local signing key exists yet for
# --identity at its coord-keygen.sh-derived path, one is auto-provisioned
# before composing the message — there is never a legitimate reason to post
# unsigned. If `ssh-keygen -Y sign` fails for any reason (e.g. too old an
# ssh-keygen), this script FAILS LOUD and refuses to send unsigned — it does
# NOT silently degrade to an unsigned post, since a silent unsigned send is
# exactly what the coordination-precommit-hook's --strict gate exists to
# catch. Verify with coord-verify.sh.
#
# Usage:
#   coord-send.sh --to <recipient|ALL> --tag <TAG> --subject "<subject>" --body "<text>"
#   coord-send.sh --to ALL --tag DEPLOY-OPEN --subject "gameserver restart" --body-file note.md
#   printf '%s' "$LONG_BODY" | coord-send.sh --to impl-sectorwars --tag STATUS --subject "..."
#
# --tag accepts a friendly key OR a raw "emoji TEXT" string (passthrough):
#   HANDOFF STATUS DECISION ACK HEADS-UP PROCESS-NOTE QUEUE
#   DEPLOY-REQUEST DEPLOY-OPEN DEPLOY-CLOSED
#
# BODY SAFETY (impl-sectorwars' standing burn): prefer --body-file or a QUOTED stdin
# heredoc (<<'EOF') for any message with backticks/code/SHAs/paths. A double-quoted
# --body "..." lets the CALLING shell command-substitute backtick spans and silently
# drop them before this script ever sees the text. --body is safe only for trivial
# no-backtick one-liners (or single-quoted).

set -u
COORD_SEND_HOME="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
# shellcheck source=coord-keygen.sh
# Sourcing (not executing) coord-keygen.sh: its CLI dispatch is guarded behind
# a BASH_SOURCE==$0 check, so this only pulls in resolve_abs_dir/key_path_for —
# the exact same key-path derivation --generate uses, so the two scripts can
# never drift on where a given identity's signing key lives.
[ -f "$COORD_SEND_HOME/coord-keygen.sh" ] && . "$COORD_SEND_HOME/coord-keygen.sh"
IDENT="orchestrator"
DIR="${COORD_DIR:-$PWD/.samantha/coord}"
TO=""; TAG=""; SUBJECT=""; BODY=""; BODYFILE=""; USED_BODY_ARG=0
# --remote-seat / COORD_REMOTE_SEAT=1 (PROTOCOL 1.4.0 remote-seat extension,
# 2026-08-09): EXPLICIT, not inferred (same MANDATORY-EXPLICIT posture as
# heartbeat.sh's --weak-seat requiring --idle-policy) — a missing/empty
# allowed_signers at --dir is genuinely ambiguous between "this is a
# remote-seat bus dir, which has no local trust root by design (see
# REMOTE-SEATS.md § Message Authenticity)" and "this is an ordinary local
# coord-dir where someone forgot to enroll this identity" (the exact bug
# item 8's enrollment readback-verify below exists to catch). Inferring from
# file-absence alone cannot tell these apart and would silently defeat the
# unenrolled-identity check for the common local case too. A remote seat's
# own invocation must pass this explicitly.
REMOTE_SEAT="${COORD_REMOTE_SEAT:-0}"
# Round-5 (2026-08-09, item 6): track WHERE REMOTE_SEAT=1 came from — an
# explicit --remote-seat flag on THIS invocation, or the COORD_REMOTE_SEAT
# environment variable (ambient — could be a stray leftover in a shell
# profile, most dangerously the HUB's own, which would silently defeat the
# enrollment readback-verify for what should be an ordinary local send). The
# skip message below names the source so an operator seeing unexpected
# "skipping the local enrollment readback-verify" output on a send they
# expected to be fully checked has an immediate lead on why.
REMOTE_SEAT_SOURCE=""
[ "$REMOTE_SEAT" = 1 ] && REMOTE_SEAT_SOURCE="the COORD_REMOTE_SEAT environment variable"
while [ $# -gt 0 ]; do
  case "$1" in
    --identity) IDENT="$2"; shift 2;;
    --dir) DIR="$2"; shift 2;;
    --to) TO="$2"; shift 2;;
    --tag) TAG="$2"; shift 2;;
    --subject) SUBJECT="$2"; shift 2;;
    --body) BODY="$2"; USED_BODY_ARG=1; shift 2;;
    --body-file) BODYFILE="$2"; shift 2;;
    --remote-seat) REMOTE_SEAT=1; REMOTE_SEAT_SOURCE="the --remote-seat flag"; shift;;
    *) shift;;
  esac
done
[ -z "$TO" ]  && { echo "coord-send: --to <recipient> required" >&2; exit 2; }
[ -z "$TAG" ] && { echo "coord-send: --tag <TAG> required" >&2; exit 2; }

# `--body -` = read the body from stdin (the 2026-07-13 silent-loss bug: this used to
# post a literal "-" and DISCARD the piped heredoc — every heredoc send lost its body
# while the header-only readback reported success)
if [ "$BODY" = "-" ]; then
  BODY=""; USED_BODY_ARG=0
  if [ ! -t 0 ]; then BODY=$(cat); fi
  [ -z "$BODY" ] && { echo "coord-send: --body - given but stdin was EMPTY — refusing to post a bodyless message; use --body-file" >&2; exit 3; }
fi

# friendly tag → canonical emoji tag (unknown keys pass through verbatim)
case "$TAG" in
  HANDOFF)              TAG="🤝 HANDOFF";;
  STATUS)               TAG="📋 STATUS";;
  DECISION|DECISION-NEEDED) TAG="❓ DECISION-NEEDED";;
  ACK)                  TAG="🤝 ACK";;
  HEADS-UP|HEADSUP)     TAG="🛰️ HEADS-UP";;
  PROCESS-NOTE|NOTE)    TAG="💡 PROCESS-NOTE";;
  QUEUE|QUEUE-STATUS)   TAG="📋 QUEUE-STATUS";;
  DEPLOY-REQUEST)       TAG="🔧 DEPLOY-WINDOW REQUEST";;
  DEPLOY-OPEN)          TAG="🔧 DEPLOY-WINDOW-OPEN";;
  DEPLOY-CLOSED)        TAG="✅ DEPLOY-WINDOW-CLOSED";;
  *) : ;;
esac

# body precedence: --body, else --body-file, else piped stdin, else header-only
if [ -z "$BODY" ]; then
  if [ -n "$BODYFILE" ]; then BODY=$(cat "$BODYFILE")
  elif [ ! -t 0 ]; then BODY=$(cat)
  fi
fi

[ "$USED_BODY_ARG" = 1 ] && printf 'coord-send WARNING: --body is shell-fragile (a double-quoted arg command-substitutes backtick spans in the CALLING shell and drops them) — prefer --body-file or a quoted stdin heredoc for messages with code/SHAs/paths.\n' >&2

TS=$(date -u +%FT%TZ)
OUTBOX="$DIR/$IDENT.md"
HEADER="### $TS — $IDENT → $TO — $TAG${SUBJECT:+ [$SUBJECT]}"

[ -f "$OUTBOX" ] || { echo "coord-send: outbox $OUTBOX does not exist (wrong --identity/--dir?)" >&2; exit 2; }

# Pre-publish loop-health check (pre-publish loop-health check): verify the channel before transmitting.
# Run coord-status.sh and surface it. Warn-and-PROCEED on DEGRADED — never block, since
# you may need to send precisely because the loop is degraded (e.g. an alert).
STATUS_SH="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/coord-status.sh"
if [ -x "$STATUS_SH" ]; then
  "$STATUS_SH" --identity "$IDENT" --dir "$DIR" || printf 'coord-send: ⚠️ coordination loop DEGRADED (above) — publishing anyway; fix the loop.\n' >&2
fi

# ── sign (PROTOCOL 1.4.0 — mandatory; never post unsigned) ───────────────────
# Auto-provision + sign via coord-keygen.sh's shared helpers (ensure_signing_key /
# sign_message_file) — the exact same mechanics heartbeat.sh uses for its own
# append sites, so the two appenders can never drift on signing behavior.
if ! command -v ensure_signing_key >/dev/null 2>&1; then
  echo "coord-send: FATAL — coord-keygen.sh not found beside this script ($COORD_SEND_HOME); cannot sign. Refusing to send unsigned." >&2
  exit 1
fi

PRIVKEY=$(ensure_signing_key "$COORD_SEND_HOME/coord-keygen.sh" "$IDENT" "$DIR")
if [ -z "$PRIVKEY" ]; then
  echo "coord-send: FATAL — signing key still missing after auto-provision attempt for $IDENT. Refusing to send unsigned." >&2
  exit 1
fi

# Build the exact bytes to sign ONCE, into a file — signed and appended from
# the SAME file, so what gets signed and what gets posted cannot drift.
SIGN_TMP=$(mktemp "${TMPDIR:-/tmp}/coord-sign.XXXXXX")
{ printf '%s\n' "$HEADER"; [ -n "$BODY" ] && printf '%s\n' "$BODY"; } > "$SIGN_TMP"

SIG_BLOCK=$(sign_message_file "$PRIVKEY" "$IDENT" "$SIGN_TMP")
SIGN_RC=$?
if [ "$SIGN_RC" -ne 0 ] || [ -z "$SIG_BLOCK" ]; then
  echo "coord-send: FATAL — ssh-keygen -Y sign FAILED — refusing to send unsigned (this is the hard-block; do not route around it)." >&2
  rm -f "$SIGN_TMP"
  exit 1
fi

# one atomic append to the OWN outbox — leading separator + the exact signed
# file + SIG block together.
{ printf '\n'; cat "$SIGN_TMP"; printf '%s' "$SIG_BLOCK"; } >> "$OUTBOX"
rm -f "$SIGN_TMP"

# readback-verify (never assert a send without confirming it landed).
# 2026-07-13 hardening: verify the BODY landed too, not just the header — the
# header-only check reported ✅ all day while every heredoc body was being lost.
if ! tail -n 400 "$OUTBOX" | grep -qF "$HEADER"; then
  echo "coord-send ⚠️ FAILED to verify the append landed in $(basename "$OUTBOX")" >&2
  exit 1
fi
if [ -n "$BODY" ]; then
  BODYHEAD=$(printf '%s\n' "$BODY" | grep -m1 . || true)
  if [ -n "$BODYHEAD" ] && ! tail -n 400 "$OUTBOX" | grep -qF "$BODYHEAD"; then
    echo "coord-send ⚠️ header landed but BODY readback FAILED (first line not found) in $(basename "$OUTBOX")" >&2
    exit 1
  fi
fi
if ! tail -n 400 "$OUTBOX" | grep -qF "BEGIN SSH SIGNATURE"; then
  echo "coord-send ⚠️ header/body landed but SIGNATURE readback FAILED in $(basename "$OUTBOX")" >&2
  exit 1
fi

# Enrollment readback-verify (item 8, 2026-08-09): the checks above only
# confirm SIG-SHAPED BYTES landed (header text, body text, a PEM marker) —
# none of them actually run the cryptographic check, so a message could post
# "successfully" while $IDENT isn't enrolled in allowed_signers yet (a
# propagation race, or a key that got generated but never handed to the
# Orchestrator to enroll) and every reader sees UNKNOWN-SIGNER/INVALID with
# no feedback at send time. Run the SAME coord-verify.sh readers use, over
# the tail window, and require the LAST verdict for $IDENT in that window
# (i.e. the message just posted, per the single-writer-per-file invariant —
# nothing else appends to this outbox) to read ✅ VERIFIED.
if [ -f "$COORD_SEND_HOME/coord-verify.sh" ]; then
  if [ "$REMOTE_SEAT" = 1 ]; then
    echo "coord-send: INFO — remote-seat mode active (source: $REMOTE_SEAT_SOURCE): skipping the local enrollment readback-verify against $DIR/allowed_signers (this bus dir has no local trust root by design — see REMOTE-SEATS.md § Message Authenticity). Verification happens at the hub when it fetches this message." >&2
    if [ "$REMOTE_SEAT_SOURCE" = "the COORD_REMOTE_SEAT environment variable" ]; then
      echo "coord-send: WARN — this came from the COORD_REMOTE_SEAT environment variable, not an explicit --remote-seat flag on this call. If that is unexpected here (e.g. a stray export left in a shell profile — especially on a HUB, which should almost never set this), the local enrollment readback-verify is silently NOT protecting this send right now." >&2
    fi
  else
    VERIFY_OUT=$(bash "$COORD_SEND_HOME/coord-verify.sh" --dir "$DIR" --file "$OUTBOX" --tail 400 2>&1)
    LAST_VERDICT=$(printf '%s\n' "$VERIFY_OUT" | grep -E "(✅|⚠️|❓|❌)[^ ]* [A-Z-]+.* ${IDENT} " | tail -1)
    if ! printf '%s' "$LAST_VERDICT" | grep -q '^✅ VERIFIED'; then
      echo "coord-send ⚠️ header/body/signature landed but enrollment readback-verify FAILED for $IDENT — coord-verify.sh does not show ✅ VERIFIED for the just-posted message:" >&2
      echo "  ${LAST_VERDICT:-<no matching verdict line found in tail>}" >&2
      echo "The message is already on disk (cannot be un-posted) but is likely UNKNOWN-SIGNER/INVALID to every reader. Check enrollment in $DIR/allowed_signers. If this IS a remote-seat bus dir (no local trust root by design), pass --remote-seat / COORD_REMOTE_SEAT=1 — see REMOTE-SEATS.md § Message Authenticity." >&2
      exit 1
    fi
  fi
else
  echo "coord-send: INFO — coord-verify.sh not found beside this script ($COORD_SEND_HOME); skipping enrollment readback-verify." >&2
fi

# Round-5 (2026-08-09, item 6): --remote-seat deliberately skips the local
# enrollment readback-verify above (no local trust root at this bus dir by
# design) — the success line must not claim "verified" when that check never
# ran. "Verification deferred to hub" states plainly what actually happened.
if [ "$REMOTE_SEAT" = 1 ]; then
  SIGN_STATUS="signed; verification deferred to hub"
else
  SIGN_STATUS="signed, verified"
fi
if [ -n "$BODY" ]; then
  BODYLEN=$(printf '%s' "$BODY" | wc -c | tr -d ' ')
  echo "coord-send ✅ posted to $(basename "$OUTBOX") @ $TS — $TAG → $TO${SUBJECT:+ [$SUBJECT]} (body ${BODYLEN}B, $SIGN_STATUS)"
else
  echo "coord-send ✅ posted to $(basename "$OUTBOX") @ $TS — $TAG → $TO${SUBJECT:+ [$SUBJECT]} (HEADER-ONLY — no body, $SIGN_STATUS)"
fi
