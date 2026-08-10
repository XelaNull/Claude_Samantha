#!/usr/bin/env bash
# coord-presence.sh — presence sidecar helpers (PROTOCOL 1.3.0 Phase 4)
#
# Presence (PIDs, state, project) lives in <coord-dir>/.presence/<identity>
# as KEY=VALUE lines. The mailbox <identity>.md stays append-only for messages
# so size-delta monitors are not corrupted by PID field width changes.
#
# Source from other scripts. Backward compatible: readers may fall back to
# roster fields embedded in the mailbox header if the sidecar is missing.

# presence_path <coord-dir> <identity>
presence_path() {
  printf '%s/.presence/%s' "$1" "$2"
}

# presence_get <coord-dir> <identity> <key>
presence_get() {
  local dir="$1" id="$2" key="$3" f
  f=$(presence_path "$dir" "$id")
  [ -f "$f" ] || return 1
  awk -F= -v k="$key" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$f"
}

# presence_set <coord-dir> <identity> <key> <value>
# Rewrites one key; creates file/dir as needed. Not append-only (sidecar is mutable).
presence_set() {
  local dir="$1" id="$2" key="$3" val="$4" f tmp
  mkdir -p "$dir/.presence"
  f=$(presence_path "$dir" "$id")
  tmp=$(mktemp "$dir/.presence/.${id}.XXXXXX")
  if [ -f "$f" ]; then
    awk -F= -v k="$key" -v v="$val" '
      BEGIN { done = 0 }
      $1 == k { print k "=" v; done = 1; next }
      { print }
      END { if (!done) print k "=" v }
    ' "$f" > "$tmp"
  else
    printf '%s=%s\n' "$key" "$val" > "$tmp"
  fi
  mv "$tmp" "$f"
}

# protocol_version_major <version>
#   Prints the leading dot-separated component of a PROTOCOL-VERSION string
#   (e.g. "1" from "1.5.0"). Plain `cut`, no semver library — matches this
#   codebase's existing simple-parsing style elsewhere (protocol_version is
#   always written by this pack's own scripts, never external input).
protocol_version_major() {
  printf '%s' "$1" | cut -d. -f1
}

# protocol_mismatch_severity <mine> <theirs>
#   Prints MAJOR if the leading version component differs, else MINOR/PATCH.
#   PROTOCOL 1.5.0 § Message Authenticity, Protocol Version Handshake:
#   MAJOR = wire/grammar-breaking (one side cannot correctly produce or parse
#   what the other expects); MINOR = additive/backward-compatible; PATCH =
#   non-semantic. Nothing shipped 1.1.0-1.4.0 was ever a MAJOR bump under
#   this definition — see the README subsection for the full convention.
protocol_mismatch_severity() {
  local mine="$1" theirs="$2"
  if [ "$(protocol_version_major "$mine")" != "$(protocol_version_major "$theirs")" ]; then
    printf 'MAJOR'
  else
    printf 'MINOR/PATCH'
  fi
}

# protocol_mismatch_message <my-identity> <my-version> <their-identity> <their-version>
#   Plain-language body for a PROTOCOL-VERSION mismatch notice — the ONE
#   place this wording is composed, shared by coord-monitor.sh's re-arm-time
#   staleness check (§3.5 Part B) and documented in README's Bootstrap
#   Checklist (§ Identity Bootstrap, ASSIGN-IDENTITY reply, Part A) so a
#   human composing that reply by hand can match it, rather than the two
#   drifting on wording independently.
#
#   POINTER, NOT A PAYLOAD (human's explicit design call, 2026-08-09): this
#   NEVER embeds file content, a diff, or a script — only a location string
#   + version numbers + a human-readable instruction. The receiving seat's
#   own agent session is responsible for fetching/copying under its own
#   local tooling, exactly like a manual sync today. If a future edit here
#   starts embedding more than that, stop and flag it back rather than
#   building it — this must never become a distribution channel.
#
#   Remediation text: LOCAL/shared-repo topology (the common case — this
#   framework's own DEPLOYMENTS.md model is copy-based, not centrally
#   pushed) gets "git pull, then re-arm" by default. COORD_CANONICAL_SOURCE
#   (optional env var, empty by default) is ONLY for a genuinely cross-repo/
#   remote-seat topology, where there is no shared checkout to pull — unset,
#   the message says to ask the Orchestrator/human rather than fabricate a
#   path.
protocol_mismatch_message() {
  local my_id="$1" my_ver="$2" their_id="$3" their_ver="$4" sev sev_note remediation canonical_source
  sev=$(protocol_mismatch_severity "$my_ver" "$their_ver")
  if [ "$sev" = "MAJOR" ]; then
    sev_note="MAJOR — wire/grammar-breaking: one side cannot correctly produce or parse what the other expects. This will block hub commits (coordination-precommit-hook.sh's protocol-version gate) until resolved."
  else
    sev_note="MINOR/PATCH — additive/backward-compatible or non-semantic. No functional break; upgrade at your convenience, this is advisory only."
  fi
  # ROUND-9 (item 3, team-lead): the same newline/CR-injection shape round 6
  # closed at 4 other sites (coord-remote-verify.sh, coordination-precommit-
  # hook.sh's remote-channel listing, coord-monitor.sh's remote_sweep_script,
  # coord-keygen.sh's --pubkey-line) — a value with an embedded newline
  # spliced straight into a signed message body could read as a spoofed
  # `### <ts> — x → ALL — TAG` header to anything naively splitting on that
  # marker, even though it's still inside THIS message's real signature.
  # Reject rather than strip/continue: a malformed COORD_CANONICAL_SOURCE is
  # a misconfiguration worth falling back on, not silently mangling.
  canonical_source=""
  if [ -n "${COORD_CANONICAL_SOURCE:-}" ]; then
    case "$COORD_CANONICAL_SOURCE" in
      *$'\n'*|*$'\r'*)
        echo "WARN [protocol-version]: COORD_CANONICAL_SOURCE contains an embedded newline/CR — refusing to splice it into a signed message body; falling back to the default remediation wording." >&2
        ;;
      *)
        canonical_source="$COORD_CANONICAL_SOURCE"
        # Cap length so a pathological value can't bloat a routine alert body.
        [ "${#canonical_source}" -gt 200 ] && canonical_source="${canonical_source:0:200}...(truncated)"
        ;;
    esac
  fi
  if [ -n "$canonical_source" ]; then
    remediation="Cross-repo/remote-seat topology: the canonical framework lives at: ${canonical_source}. Fetch/copy the newer coordination-protocol from there under your own local tooling, then re-arm your watcher/heartbeat."
  else
    remediation="If you share a repo checkout with the other side (the common, zero-cost case): git pull the coordination-protocol, then re-arm your watcher/heartbeat. If this is instead a cross-repo/remote-seat topology, ask your Orchestrator/human where the canonical framework repo lives (set COORD_CANONICAL_SOURCE to point at it directly next time)."
  fi
  printf 'PROTOCOL-VERSION mismatch: %s is running %s; %s is running %s.\nSeverity: %s\n%s\nThis is a pointer, not a payload — no file content, diff, or script is embedded here.\n' \
    "$their_id" "$their_ver" "$my_id" "$my_ver" "$sev_note" "$remediation"
}

# presence_ensure_from_mailbox <coord-dir> <identity>
# One-time seed from legacy mailbox header fields if sidecar missing.
presence_ensure_from_mailbox() {
  local dir="$1" id="$2" f mb
  f=$(presence_path "$dir" "$id")
  [ -f "$f" ] && return 0
  mb="$dir/$id.md"
  [ -f "$mb" ] || return 0
  mkdir -p "$dir/.presence"
  {
    printf 'identity=%s\n' "$id"
    awk '
      /^role:[[:space:]]*/ { sub(/^role:[[:space:]]*/, ""); gsub(/[[:space:]]+#.*$/, ""); print "role=" $0 }
      /^project:[[:space:]]*/ { sub(/^project:[[:space:]]*/, ""); gsub(/[[:space:]]+#.*$/, ""); print "project=" $0 }
      /^zone:[[:space:]]*/ { sub(/^zone:[[:space:]]*/, ""); gsub(/[[:space:]]+#.*$/, ""); print "zone=" $0 }
      /^state:[[:space:]]*/ { sub(/^state:[[:space:]]*/, ""); gsub(/[[:space:]]+#.*$/, ""); print "state=" $0 }
      /^watcher_pid:[[:space:]]*/ { sub(/^watcher_pid:[[:space:]]*/, ""); gsub(/[[:space:]]+#.*$/, ""); print "watcher_pid=" $0 }
      /^heartbeat_pid:[[:space:]]*/ { sub(/^heartbeat_pid:[[:space:]]*/, ""); gsub(/[[:space:]]+#.*$/, ""); print "heartbeat_pid=" $0 }
    ' "$mb"
  } > "$f"
}
