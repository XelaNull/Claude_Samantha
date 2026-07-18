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
IDENT="orchestrator"
DIR="/Users/mrathbone/github/Nebuspace/.samantha/coord"
TO=""; TAG=""; SUBJECT=""; BODY=""; BODYFILE=""; USED_BODY_ARG=0
while [ $# -gt 0 ]; do
  case "$1" in
    --identity) IDENT="$2"; shift 2;;
    --dir) DIR="$2"; shift 2;;
    --to) TO="$2"; shift 2;;
    --tag) TAG="$2"; shift 2;;
    --subject) SUBJECT="$2"; shift 2;;
    --body) BODY="$2"; USED_BODY_ARG=1; shift 2;;
    --body-file) BODYFILE="$2"; shift 2;;
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

# Pre-publish loop-health check (Max's request): verify the channel before transmitting.
# Run coord-status.sh and surface it. Warn-and-PROCEED on DEGRADED — never block, since
# you may need to send precisely because the loop is degraded (e.g. an alert).
STATUS_SH="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/coord-status.sh"
if [ -x "$STATUS_SH" ]; then
  "$STATUS_SH" --identity "$IDENT" --dir "$DIR" || printf 'coord-send: ⚠️ coordination loop DEGRADED (above) — publishing anyway; fix the loop.\n' >&2
fi

# one atomic append to the OWN outbox
{ printf '\n%s\n' "$HEADER"; [ -n "$BODY" ] && printf '%s\n' "$BODY"; } >> "$OUTBOX"

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
  BODYLEN=$(printf '%s' "$BODY" | wc -c | tr -d ' ')
  echo "coord-send ✅ posted to $(basename "$OUTBOX") @ $TS — $TAG → $TO${SUBJECT:+ [$SUBJECT]} (body ${BODYLEN}B verified)"
else
  echo "coord-send ✅ posted to $(basename "$OUTBOX") @ $TS — $TAG → $TO${SUBJECT:+ [$SUBJECT]} (HEADER-ONLY — no body)"
fi
