#!/usr/bin/env bash
# coord-remote-verify.sh — verify a buffer of mailbox bytes fetched from a
# REMOTE bus dir (over ssh) against the HUB's own LOCAL allowed_signers.
#
# WHY THIS EXISTS (PROTOCOL 1.4.0 remote-seat extension, 2026-08-09): a remote
# seat's coord-send.sh/heartbeat.sh already sign every message exactly like a
# local seat (see REMOTE-SEATS.md § Message Authenticity) — the gap was never
# in the crypto, it was that neither coord-monitor.sh's remote channel
# (`remote_emit_new`) nor coordination-precommit-hook.sh ever called
# coord-verify.sh on what they fetched over ssh. Both need the SAME
# fetch-a-buffer -> name-it-correctly -> verify-it logic; this file is the one
# place that logic lives, sourced by both, so they cannot drift apart.
#
# SINGLE CANONICAL TRUST ROOT (deliberate design choice, see REMOTE-SEATS.md):
# there is no separate "remote allowed_signers". A remote seat's pubkey is
# enrolled into the HUB'S OWN local allowed_signers via the existing
# `coord-keygen.sh --enroll` mechanism — enrollment only ever needs the
# pubkey STRING (parsed out of the seat's HEADS-UP body), never local
# filesystem access to the remote file it arrived in. This function therefore
# always verifies against a LOCAL --dir (the hub's own coord-dir), never
# anything remote-path-shaped.
#
# THE NAMING REQUIREMENT: coord-verify.sh's structural check requires
# `FROM == basename(file)` (single-writer-per-file invariant — see its own
# header comment). A buffer fetched over ssh has no local file of its own; it
# MUST be written to a local temp file whose BASENAME is the real remote
# identity's mailbox filename (e.g. `impl-remote1.md`), inside a FRESH temp
# DIRECTORY — never an arbitrary `mktemp` basename (that would make every
# remote message spuriously fail the structural check regardless of whether
# it is genuinely valid, since the check would compare FROM against the
# temp-file's random suffix instead of the real identity).
#
# SOURCEABLE: like coord-keygen.sh, only the helper function below is defined
# when sourced (guarded CLI dispatch further down, for standalone/manual use).

set -u

# coord_remote_shquote <value>
#   POSIX single-quote escaping for splicing an UNTRUSTED value (e.g. a
#   filename listed BY the remote host itself) into a command string that
#   will be sent to a remote shell over ssh. Round-5 CRITICAL fix (2026-08-09,
#   Cipher — live-demonstrated RCE): coord-monitor.sh's remote_emit_new and
#   coordination-precommit-hook.sh's check 1c both used to splice a remote-
#   listed filename into an ssh command string with ZERO escaping — a file
#   named e.g. "x'; id; echo '.md" in the remote bus dir executed arbitrary
#   code on the hub, before any signature check ever ran. Client-side argv
#   separation does NOT fix this: ssh always re-joins its trailing arguments
#   into ONE string that the remote shell parses, so passing a value as a
#   "separate" argument to the LOCAL ssh invocation offers no protection —
#   the escaping has to happen in the command TEXT itself. Standard technique:
#   replace each embedded ' with '\'' , then wrap the whole result in '...'.
#   This works for ANY remote shell (sh/dash/bash/ksh/zsh) — unlike bash's
#   `printf %q`, which emits bash-only $'...' escapes a POSIX remote shell may
#   not understand. Prints the quoted result (including its own outer quotes)
#   on stdout; the caller splices this text directly into a larger command
#   string, e.g.: "cat $(coord_remote_shquote "$bus")/$(coord_remote_shquote "$name")".
#   THIS FUNCTION IS A HARD DEPENDENCY for constructing any remote command
#   from a remote-supplied value — see coord-monitor.sh's mandatory-source
#   check for --remote-host and coordination-precommit-hook.sh's check 1c
#   guard, neither of which will construct a remote fetch command without it.
coord_remote_shquote() {
  local s
  s=$(printf '%s' "$1" | sed "s/'/'\\\\''/g")
  printf "'%s'" "$s"
}

# verify_remote_buffer <local-coord-dir> <remote-md-basename> <coord-verify.sh-path> [--strict]
#   Reads the buffer to verify from STDIN. Writes it to
#   <fresh-tmp-dir>/<remote-md-basename>, runs coord-verify.sh against it with
#   --dir <local-coord-dir> (so allowed_signers is read from the HUB's own
#   local trust root, never anything remote), prints coord-verify.sh's
#   stdout+stderr verbatim, and returns its exit code. Always cleans up the
#   temp dir, success or failure.
#
#   <remote-md-basename> MUST be the real identity's mailbox filename (e.g.
#   "impl-remote1.md", exactly what the remote bus dir names it) — this is
#   what makes the structural FROM==basename(file) check meaningful for
#   content that never had a local file of its own.
verify_remote_buffer() {
  local local_coord_dir="$1" remote_basename="$2" coord_verify_sh="$3"
  shift 3 || true
  local extra_args=("$@")

  # Round-6 (2026-08-09, Cipher): also reject an embedded newline/CR, not
  # just a path-traversal shape — consumption-side defense in depth for the
  # same class of bad name coord-monitor.sh's remote_sweep_script now refuses
  # to even LIST (see that function's header for the wire-format-injection
  # this closes at the source; this check does not by itself undo an
  # already-injected fake record upstream, but it stops THIS function from
  # ever writing a newline-bearing "basename" into a local temp-file path).
  case "$remote_basename" in
    */*|""|.|..|*$'\n'*|*$'\r'*)
      echo "ERROR [coord-remote-verify]: refusing unsafe remote basename: '$remote_basename'" >&2
      return 2
      ;;
  esac

  local tmpdir rc=0
  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/coord-remote-verify.XXXXXX") || {
    echo "ERROR [coord-remote-verify]: could not create temp dir." >&2
    return 2
  }
  cat > "$tmpdir/$remote_basename"

  # bash 3.2 nounset-safe empty-array expansion (macOS system bash — a bare
  # "${extra_args[@]}" throws "unbound variable" under `set -u` when the
  # array is empty, pre-4.4).
  bash "$coord_verify_sh" --dir "$local_coord_dir" --file "$tmpdir/$remote_basename" \
    ${extra_args[@]+"${extra_args[@]}"} 2>&1
  rc=$?

  rm -rf "$tmpdir"
  return "$rc"
}

# ── CLI (only runs when this file is executed directly, not sourced) ─────────
# Manual/debugging use: pipe a buffer in, get the same output a caller would.
if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  LOCAL_DIR=""
  REMOTE_NAME=""
  CV_SH="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/coord-verify.sh"
  STRICT_ARG=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir) LOCAL_DIR="$2"; shift 2 ;;
      --name) REMOTE_NAME="$2"; shift 2 ;;
      --strict) STRICT_ARG=(--strict); shift ;;
      -h|--help)
        cat <<'USAGE'
Usage: buffer-source | coord-remote-verify.sh --dir <local-coord-dir> --name <remote-md-basename> [--strict]
Verifies a mailbox buffer (read from stdin) that was fetched from a remote
bus dir, against the LOCAL coord-dir's allowed_signers — see this file's
header comment for why the buffer must be written to a correctly-named temp
file before coord-verify.sh can meaningfully check it.
USAGE
        exit 0
        ;;
      *) echo "ERROR [coord-remote-verify]: unknown argument: $1" >&2; exit 1 ;;
    esac
  done
  if [[ -z "$LOCAL_DIR" || -z "$REMOTE_NAME" ]]; then
    echo "ERROR [coord-remote-verify]: --dir and --name are required." >&2
    exit 2
  fi
  verify_remote_buffer "$LOCAL_DIR" "$REMOTE_NAME" "$CV_SH" ${STRICT_ARG[@]+"${STRICT_ARG[@]}"}
  exit $?
fi
