#!/usr/bin/env bash
# coord-receipt.sh — Rule-4 mailbox-read receipt helpers (PROTOCOL 1.4.0)
#
# A receipt (<coord-dir>/.watch-state/<id>/<file>.size) records how far an
# identity has acknowledged into a mailbox file. Written by coord-monitor.sh
# on every wake and by coordination-precommit-hook.sh's first-run auto-init;
# read by the hook to gate commits (Rule 4: read your mailbox first).
#
# RECEIPT-FORGERY HARDENING (item 1, 2026-08-09): a bare integer offset let
# anything (a bug, a stray `echo 99999 > receipt`, a hand-edit) silently
# disable the gate forever, with nothing to detect the forgery. The receipt
# is now two fields:
#   offset=<n>
#   verified_sha256=<sha256 of the file's first n bytes, computed by whoever
#                     wrote this receipt>
# A reader recomputes sha256 of the CURRENT file's first n bytes and refuses
# to trust the receipt unless it matches — the prefix those n bytes cover
# cannot silently change out from under an honest receipt (a legitimate
# writer only ever advances offset forward over content it just read; the
# hash of everything before that point is stable). Ceiling: sha256 is not a
# keyed MAC — an attacker with write access to the coord-dir can compute a
# matching hash for whatever prefix they choose just as easily as an honest
# writer can; this closes the "bump a bare integer past reality" bypass and
# detects a stale/corrupted receipt, not a determined on-box forger (same
# ceiling as every other filesystem-perms-only control in this protocol —
# see README.md § Message Authenticity).
#
# Source from other scripts; do not execute standalone.

# compute_prefix_sha256 <file> <n> — sha256 of the file's first n bytes.
# Prints nothing and returns nonzero if neither shasum nor sha256sum exists.
compute_prefix_sha256() {
  local f="$1" n="$2" hasher
  if command -v shasum >/dev/null 2>&1; then
    hasher=(shasum -a 256)
  elif command -v sha256sum >/dev/null 2>&1; then
    hasher=(sha256sum)
  else
    return 1
  fi
  if [[ "$n" -eq 0 ]]; then
    # BSD head (macOS) rejects `-c 0` as an "illegal byte count" and exits
    # nonzero even though zero bytes is a perfectly legitimate prefix length
    # (a receipt reset to "nothing acknowledged yet", or the very first
    # message in a brand-new file) — under `set -o pipefail` (every caller
    # of this file runs with it) that nonzero poisons the whole pipeline's
    # exit status even though the hash it prints is correct. Skip head
    # entirely for this case and hash empty input directly.
    printf '' | "${hasher[@]}" 2>/dev/null | awk '{print $1}'
  else
    head -c "$n" "$f" 2>/dev/null | "${hasher[@]}" 2>/dev/null | awk '{print $1}'
  fi
}

# write_receipt <receipt-file> <offset> <file>
# Computes verified_sha256 over <file>'s first <offset> bytes and writes the
# two-field receipt. Returns nonzero (and writes nothing) if the hash can't
# be computed — callers must not fall back to writing a bare/unbound offset.
write_receipt() {
  local rf="$1" off="$2" f="$3" hash
  hash=$(compute_prefix_sha256 "$f" "$off") || return 1
  [[ -n "$hash" ]] || return 1
  { printf 'offset=%s\n' "$off"; printf 'verified_sha256=%s\n' "$hash"; } > "$rf" 2>/dev/null
}

# read_receipt <receipt-file> <file>
# Parses the two-field receipt and validates it against <file>'s CURRENT
# content: recomputes sha256 over the claimed offset's worth of bytes and
# rejects (falls back to 0) on any mismatch or malformed field. Prints the
# trusted offset on stdout (always — 0 on any rejection, never partially
# trusted). WARN/FAIL diagnostics go to stderr; callers that want to
# distinguish "clean" from "rejected" should also inspect stderr output
# instead of only stdout.
read_receipt() {
  local rf="$1" f="$2" file_sz off="" hash="" ok=1 recomputed
  file_sz=$(wc -c < "$f" 2>/dev/null | tr -d ' ') || file_sz=0
  [[ -z "$file_sz" ]] && file_sz=0

  while IFS='=' read -r k v; do
    case "$k" in
      offset) off="$v" ;;
      verified_sha256) hash="$v" ;;
    esac
  done < <(tr -d '\r' < "$rf" 2>/dev/null || true)

  if ! [[ "$off" =~ ^[0-9]+$ ]] || [[ "$off" -gt "$file_sz" ]]; then
    echo "WARN [coord-receipt]: receipt offset ('${off}') in $rf is invalid or exceeds file size; treating as 0 (unread)." >&2
    ok=0
  elif ! [[ "$hash" =~ ^[0-9a-f]{64}$ ]]; then
    echo "WARN [coord-receipt]: receipt $rf is missing/malformed verified_sha256; treating as 0 (unread)." >&2
    ok=0
  else
    recomputed=$(compute_prefix_sha256 "$f" "$off") || recomputed=""
    if [[ -z "$recomputed" ]]; then
      echo "WARN [coord-receipt]: could not recompute receipt hash for $rf (no shasum/sha256sum on PATH); treating as 0 (unread)." >&2
      ok=0
    elif [[ "$recomputed" != "$hash" ]]; then
      echo "FAIL [coord-receipt]: receipt hash mismatch for $rf — claimed verified_sha256 does not match $f's actual first ${off}B. Forged, corrupted, or stale receipt; treating as 0 (unread), never silently trusted." >&2
      ok=0
    fi
  fi

  if [[ "$ok" -eq 1 ]]; then
    printf '%s' "$off"
  else
    printf '0'
  fi
}
