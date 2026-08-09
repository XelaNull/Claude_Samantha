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
