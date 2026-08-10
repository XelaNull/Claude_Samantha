#!/usr/bin/env bash
# coord-keygen.sh — SSH signing-key lifecycle for coord-dir message authenticity.
# PROTOCOL-VERSION: 1.4.0 (Message Authenticity amendment — see README.md
# § Message Authenticity (SSH signing)).
#
# MECHANISM: `ssh-keygen -Y sign` / `-Y verify` — OpenSSH's native signing
# facility, the same one git uses for SSH-signed commits. No new dependency:
# every implementer's box already has it. Namespace string "samantha-coord"
# scopes signatures so they can't be replayed as e.g. git-commit signatures.
#
# KEY STORAGE (per-seat private key, NEVER committed):
#   ~/.samantha/coord-keys/<dirhash>/<identity>_ed25519
#   <dirhash> = first 12 hex chars of sha256(<coord-dir>/.coord-id contents).
#   .coord-id is a stable random token, generated once and written into the
#   coord-dir itself (committed to git) — NOT a hash of the absolute
#   <coord-dir> path (2026-08-09, item 7 hardening): an absolute-path hash
#   silently orphaned every already-provisioned key the moment this portable
#   framework's checkout was moved, renamed, or re-cloned to a different
#   location, since the derived key namespace changed out from under it with
#   no error, just "no key found, re-provision" on the new (wrong) path. The
#   id file travels WITH the coord-dir instead, so the namespace survives a
#   move/rename/reclone exactly like allowed_signers already does.
#   Scopes keys per coord-dir so the same identity string (e.g. two different
#   projects both having "impl-alpha") never collides across projects on one
#   machine. Mode 0600 (dir 0700). Generated passphrase-less (-N "") —
#   proportionate for a local automation key protected by filesystem perms,
#   the same trust tier as an unattended CI deploy key. Documented here, not
#   hidden: a passphrase-less key is only as safe as the box it lives on.
#
# TRUST ROOT: <coord-dir>/allowed_signers — OpenSSH allowed_signers format,
#   one line per identity:
#     <identity> namespaces="samantha-coord" <key-type> <base64-key>
#   Single-writer: Orchestrator only (same pattern as QUEUE.md, M7 — see
#   README.md § Topology — STAR). This file IS committed/shared: public keys
#   only, Rule 5-safe (a public key is not a secret).
#
# MODES:
#   --generate --identity <id> --dir <coord-dir>
#     Idempotent. Existing private key at the derived path -> no-op, prints
#     the existing RAW pubkey line (ssh-keygen's native `<type> <base64>
#     <comment>` format — i.e. the verbatim contents of <key>.pub) to stdout.
#     No existing key -> generates one, prints the new raw pubkey line to
#     stdout. Guidance goes to stderr (stdout stays clean for $(...) capture,
#     matching bootstrap-identity.sh's stdout/stderr split).
#
#   --enroll --identity <id> --pubkey-line "<raw-pubkey-line>" --dir <coord-dir> [--rotate]
#     Orchestrator-only by convention (not mechanically enforced here, same
#     as QUEUE.md's documented-not-coded single-writer rule). Composes
#     "<id> namespaces=\"samantha-coord\" <raw-pubkey-line>" and atomically
#     appends it to allowed_signers (write-temp-then-rename). If <id> already
#     has a DIFFERENT key on file, refuses unless --rotate is also given —
#     this prevents a silent key-swap (an impersonation vector). M4: reads
#     the write back and confirms it landed.
#
#   --rotate --identity <id> --pubkey-line "<raw-pubkey-line>" --dir <coord-dir>
#     Same write mechanics as --enroll, but allowed to replace an existing
#     entry. Equivalent to `--enroll ... --rotate`. Prints a loud stderr
#     notice when an actual replacement happens — this should be a rare,
#     deliberate action, not routine traffic.
#
#   --fingerprint --identity <id> --dir <coord-dir>
#     Prints `ssh-keygen -lf <path>.pub` output, for display in ACK/roster
#     messages.
#
# USAGE:
#   PUBLINE=$(./coord-keygen.sh --generate --identity impl-alpha --dir <coord-dir>)
#   ./coord-keygen.sh --enroll --identity impl-alpha --pubkey-line "$PUBLINE" --dir <coord-dir>
#   ./coord-keygen.sh --rotate  --identity impl-alpha --pubkey-line "$PUBLINE" --dir <coord-dir>
#   ./coord-keygen.sh --fingerprint --identity impl-alpha --dir <coord-dir>
#
# SOURCEABLE: when sourced (not executed directly), only the helper functions
# below (resolve_abs_dir / compute_dirhash / key_path_for /
# identity_charset_check) are defined — no arg-parsing or dispatch runs. This
# lets coord-send.sh source the exact same key-path derivation it needs to
# auto-provision, so the two scripts never drift on where a key lives (same
# dual-mode pattern as coord-protocol-metrics.sh).

set -uo pipefail

# ── shared helpers (used standalone AND when sourced by coord-send.sh) ────────

resolve_abs_dir() {
  local d="$1"
  mkdir -p "$d" 2>/dev/null
  (cd "$d" 2>/dev/null && pwd -P)
}

# _generate_coord_id — a fresh random token for a new .coord-id. Not a
# secret (it only scopes a local key-storage namespace and gets committed
# to git) — /dev/urandom or openssl if available, a best-effort mix
# otherwise (still unique per machine/moment, just not cryptographically
# strong; fine for a namespace key).
_generate_coord_id() {
  local id=""
  if command -v openssl >/dev/null 2>&1; then
    id=$(openssl rand -hex 16 2>/dev/null) || id=""
  fi
  if [ -z "$id" ] && [ -r /dev/urandom ]; then
    id=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n') || id=""
  fi
  if [ -z "$id" ]; then
    id=$(printf '%s-%s-%s' "$(date +%s 2>/dev/null)" "$$" "$RANDOM$RANDOM")
  fi
  printf '%s' "$id"
}

# coord_id_for <abs-coord-dir> — reads (or creates, write-temp-then-rename)
# the stable per-coord-dir token at <abs-coord-dir>/.coord-id.
coord_id_for() {
  local abs_dir="$1" idfile="$1/.coord-id" id tmp
  if [ -s "$idfile" ]; then
    tr -d '[:space:]' < "$idfile"
    return 0
  fi
  id=$(_generate_coord_id) || return 1
  [ -n "$id" ] || return 1
  tmp=$(mktemp "$abs_dir/.coord-id.XXXXXX") || return 1
  printf '%s\n' "$id" > "$tmp"
  mv "$tmp" "$idfile"
  # M4 read-back-after-write (round-2, item 6): two concurrent first-runs
  # can both pass the `[ -s "$idfile" ]` check as false, each generate their
  # OWN id, and each `mv` their own tmp file to the same target -- the last
  # mv wins on disk, but printing the in-memory $id instead of re-reading
  # meant the LOSER would derive its key namespace from a token no longer
  # actually on disk, then silently re-key on its very next run when it
  # re-reads and finds the winner's id instead. Re-reading here means both
  # processes always agree with whatever actually landed, race or not.
  [ -s "$idfile" ] && tr -d '[:space:]' < "$idfile" || printf '%s' "$id"
}

compute_dirhash() {
  local abs_dir="$1" id
  id=$(coord_id_for "$abs_dir") || return 1
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$id" | shasum -a 256 | awk '{print $1}' | cut -c1-12
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$id" | sha256sum | awk '{print $1}' | cut -c1-12
  else
    echo "ERROR [coord-keygen]: neither shasum nor sha256sum found — cannot derive per-coord-dir key namespace." >&2
    return 1
  fi
}

# Portable (macOS + Linux) advisory lock via atomic `mkdir` — no dependency
# on flock(1), which ships on Linux (util-linux) but is NOT present by
# default on macOS (item 16, 2026-08-09). Guards do_enroll's read-decide-
# write critical section against a concurrent enroll on the SAME
# allowed_signers racing a lost update: two enrolls both reading "no
# existing entry" for different identities, both building a tmp file from
# the SAME stale snapshot, and whichever `mv`s second silently discards the
# other's addition.
_acquire_signers_lock() {
  local lockdir="$1.lock" waited_ms=0 max_wait_ms=20000 age
  while ! mkdir "$lockdir" 2>/dev/null; do
    if [ -d "$lockdir" ]; then
      age=$(( $(date +%s) - $(stat -f %m "$lockdir" 2>/dev/null || stat -c %Y "$lockdir" 2>/dev/null || date +%s) ))
      if [ "$age" -gt 20 ]; then
        echo "WARN [coord-keygen]: breaking stale enroll lock $lockdir (age ${age}s — assuming an abandoned/crashed holder)." >&2
        rmdir "$lockdir" 2>/dev/null || true
        continue
      fi
    fi
    sleep 0.2
    waited_ms=$((waited_ms + 200))
    if [ "$waited_ms" -ge "$max_wait_ms" ]; then
      echo "ERROR [coord-keygen]: could not acquire enroll lock $lockdir after 20s — refusing to enroll without it (avoids a silent lost-update race)." >&2
      return 1
    fi
  done
  return 0
}

_release_signers_lock() {
  rmdir "$1.lock" 2>/dev/null || true
}

# Same charset rule as coordination-precommit-hook.sh's MY_ID assertion — an
# identity is interpolated into filenames and grep -E patterns elsewhere in
# this protocol; a metachar makes those silently mis-behave.
identity_charset_check() {
  local id="$1"
  if [[ -z "$id" || ! "$id" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "ERROR [coord-keygen]: identity '$id' must be non-empty and match [A-Za-z0-9._-]+." >&2
    return 1
  fi
}

key_path_for() {
  # Charset-validates EVERY caller (item 13, 2026-08-09), not just this
  # script's own CLI dispatch — the identity ends up interpolated straight
  # into a filesystem path here, so a caller reaching this indirectly (e.g.
  # coord-send.sh/heartbeat.sh via ensure_signing_key below, or
  # bootstrap-identity.sh calling this directly) previously got NO validation
  # at all unless coord-keygen.sh's own CLI happened to run first.
  local abs_dir="$1" identity="$2" hash
  identity_charset_check "$identity" || return 1
  hash=$(compute_dirhash "$abs_dir") || return 1
  printf '%s/.samantha/coord-keys/%s/%s_ed25519' "$HOME" "$hash" "$identity"
}

# ── shared signing helpers (sourced by coord-send.sh AND heartbeat.sh) ───────
# Pulled out so the two appenders can never drift on signing mechanics the
# same way they already can't drift on key-path derivation (above).

# ensure_signing_key <coord-keygen.sh-path> <identity> <coord-dir>
# Prints the private key path on stdout. Auto-provisions (coord-keygen.sh
# --generate) if none exists yet for this identity. Returns nonzero if a key
# still doesn't exist after that attempt — callers must treat that as "cannot
# sign" and never post unsigned as a result.
ensure_signing_key() {
  local keygen_sh="$1" identity="$2" coord_dir="$3" abs_dir privkey
  abs_dir=$(resolve_abs_dir "$coord_dir") || return 1
  privkey=$(key_path_for "$abs_dir" "$identity") || return 1
  if [ ! -f "$privkey" ]; then
    "$keygen_sh" --generate --identity "$identity" --dir "$coord_dir" >/dev/null
  fi
  [ -f "$privkey" ] || return 1
  printf '%s' "$privkey"
  return 0
}

# sign_message_file <privkey-path> <identity> <msg-file>
# Signs the EXACT bytes already sitting in <msg-file> (the caller builds this
# file itself — header line + whatever body bytes it intends to append, in
# WHATEVER exact shape it already writes today; this function has no opinion
# on that shape and does not re-derive or reformat it) via `ssh-keygen -Y
# sign` (namespace samantha-coord), and prints the finished
# "<!-- SIG v1 ... -->" block to stdout on success. Deliberately file-based
# rather than string-based: coord-send.sh and heartbeat.sh build their
# messages with different internal formatting (heartbeat.sh's append has an
# extra blank line coord-send.sh's does not), and a caller passing the exact
# file it is about to append — rather than re-assembling header+body a SECOND
# time from string args — cannot drift between what got signed and what got
# posted, by construction (the safest signing correctness ceiling: caller
# never reconstructs the message twice; it composes it once, signs that file
# directly, and appends the SAME file plus this function's returned block).
# On ANY failure (bad key, ssh-keygen too old / missing -Y support, no .sig
# produced), prints nothing to stdout, prints the underlying error to stderr,
# and returns nonzero — every caller must treat that as "cannot sign" and
# decide its OWN skip-vs-fallback policy; this function never silently
# degrades to an unsigned block itself.
sign_message_file() {
  local privkey="$1" identity="$2" msg_file="$3"
  local sign_err msg_bytes sig_block

  [ -f "$msg_file" ] || { echo "sign_message_file: no such file: $msg_file" >&2; return 1; }

  # bytes: N is the exact byte length of the signed region (this file, as it
  # sits right now) — NOT a lint aid like the sha256 line it replaces
  # (2026-08-09: cut entirely, see README). coord-verify.sh reads exactly N
  # bytes starting at the message's header line, full stop, which is what
  # makes message-boundary detection exact instead of heuristic (see
  # coord-verify.sh's header comment).
  msg_bytes=$(wc -c < "$msg_file" | tr -d ' ')

  sign_err=$(mktemp "${TMPDIR:-/tmp}/coord-sign-err.XXXXXX") || return 1
  if ! ssh-keygen -Y sign -f "$privkey" -n samantha-coord "$msg_file" >"$sign_err" 2>&1; then
    cat "$sign_err" >&2
    rm -f "$sign_err"
    return 1
  fi
  rm -f "$sign_err"

  if [ ! -f "$msg_file.sig" ]; then
    echo "sign_message_file: ssh-keygen -Y sign reported success but produced no .sig file." >&2
    return 1
  fi

  sig_block=$(
    printf '<!-- SIG v1\n'
    printf 'namespace: samantha-coord\n'
    printf 'signer: %s\n' "$identity"
    printf 'bytes: %s\n' "$msg_bytes"
    cat "$msg_file.sig"
    printf -- '-->\n'
  )
  rm -f "$msg_file.sig"
  printf '%s' "$sig_block"
  return 0
}

# ── CLI (only runs when this file is executed directly, not sourced) ─────────

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then

MODE=""
IDENTITY=""
COORD_DIR=""
PUBKEY_LINE=""
ALLOW_ROTATE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --generate)     MODE="generate"; shift ;;
    --enroll)       [[ -z "$MODE" ]] && MODE="enroll"; shift ;;
    --rotate)       MODE="enroll"; ALLOW_ROTATE=1; shift ;;
    --fingerprint)  MODE="fingerprint"; shift ;;
    --identity)     IDENTITY="$2"; shift 2 ;;
    --dir)          COORD_DIR="$2"; shift 2 ;;
    --pubkey-line)  PUBKEY_LINE="$2"; shift 2 ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  coord-keygen.sh --generate --identity <id> --dir <coord-dir>
  coord-keygen.sh --enroll --identity <id> --pubkey-line "<line>" --dir <coord-dir> [--rotate]
  coord-keygen.sh --rotate  --identity <id> --pubkey-line "<line>" --dir <coord-dir>
  coord-keygen.sh --fingerprint --identity <id> --dir <coord-dir>

<line> is the RAW pubkey line — the verbatim stdout of --generate (i.e. the
contents of <key>.pub: "<type> <base64> <comment>"), NOT a full
allowed_signers line. --enroll/--rotate prepend "<id> namespaces=..." themselves.
USAGE
      exit 0
      ;;
    *) echo "ERROR [coord-keygen]: unknown argument: $1" >&2; exit 1 ;;
  esac
done

do_generate() {
  identity_charset_check "$IDENTITY" || exit 1
  if [[ -z "$COORD_DIR" ]]; then
    echo "ERROR [coord-keygen]: --generate requires --dir." >&2
    exit 1
  fi
  local abs_dir key
  abs_dir=$(resolve_abs_dir "$COORD_DIR") || exit 1
  key=$(key_path_for "$abs_dir" "$IDENTITY") || exit 1

  if [[ -f "$key" ]]; then
    if [[ ! -f "${key}.pub" ]]; then
      echo "FATAL [coord-keygen]: private key exists but ${key}.pub is missing — cannot recover pubkey. Manual intervention needed." >&2
      exit 1
    fi
    echo "[coord-keygen] Key already exists for $IDENTITY at $key — no-op." >&2
    cat "${key}.pub"
    exit 0
  fi

  mkdir -p "$(dirname "$key")"
  chmod 700 "$(dirname "$key")" 2>/dev/null || true

  if ! ssh-keygen -t ed25519 -N "" -C "${IDENTITY}@samantha-coord" -f "$key" >&2; then
    echo "FATAL [coord-keygen]: ssh-keygen key generation failed for $IDENTITY." >&2
    exit 1
  fi
  chmod 600 "$key" 2>/dev/null || true
  chmod 644 "${key}.pub" 2>/dev/null || true

  # M4: confirm the write persisted.
  if [[ ! -f "${key}.pub" ]]; then
    echo "FATAL [coord-keygen]: key generation reported success but ${key}.pub is missing." >&2
    exit 1
  fi

  {
    echo ""
    echo "[coord-keygen] Generated signing key for $IDENTITY: $key"
    echo "[coord-keygen] Passphrase-less by design — proportionate for a local automation"
    echo "[coord-keygen] key protected by filesystem perms (mode 0600), same trust tier as"
    echo "[coord-keygen] an unattended CI deploy key. NEVER commit this private key."
    echo "[coord-keygen] Enroll the pubkey line (printed on stdout) via:"
    echo "  coord-keygen.sh --enroll --identity $IDENTITY --pubkey-line \"\$LINE\" --dir $COORD_DIR"
  } >&2
  cat "${key}.pub"
}

do_enroll() {
  identity_charset_check "$IDENTITY" || exit 1
  if [[ -z "$COORD_DIR" || -z "$PUBKEY_LINE" ]]; then
    echo "ERROR [coord-keygen]: --enroll/--rotate require --identity, --pubkey-line, and --dir." >&2
    exit 1
  fi
  # Shape-validate PUBKEY_LINE before it gets spliced into allowed_signers
  # (item 15, 2026-08-09): this file is single-writer-append (M7) and the M4
  # readback below only confirms the INTENDED line landed — it never checked
  # that nothing EXTRA was also written. An embedded newline in --pubkey-line
  # would inject one or more additional, attacker-shaped rows into
  # allowed_signers (a forged entry for a different identity, or a bogus
  # second key for this one) that the readback never notices because it's
  # only looking for its own line. Reject any embedded newline outright, and
  # require the remainder to actually look like "<key-type> <base64> [comment]".
  case "$PUBKEY_LINE" in
    *$'\n'*)
      echo "ERROR [coord-keygen]: --pubkey-line contains an embedded newline — refusing (this could inject extra rows into allowed_signers)." >&2
      exit 1
      ;;
  esac
  if [[ ! "$PUBKEY_LINE" =~ ^(ssh-ed25519|ssh-rsa|ssh-dss|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]]; then
    echo "ERROR [coord-keygen]: --pubkey-line does not look like a single valid SSH public key line (<key-type> <base64> [comment])." >&2
    echo "  got: $PUBKEY_LINE" >&2
    exit 1
  fi
  mkdir -p "$COORD_DIR"
  local signers="$COORD_DIR/allowed_signers"
  touch "$signers" 2>/dev/null || true

  # item 16: lock the read-decide-write critical section below. Released via
  # an EXIT trap so every exit path in this function (no-op / refuse /
  # success) releases it, not just the happy path.
  _acquire_signers_lock "$signers" || exit 1
  trap '_release_signers_lock "'"$signers"'"' EXIT

  local new_line="${IDENTITY} namespaces=\"samantha-coord\" ${PUBKEY_LINE}"
  local existing
  existing=$(grep -E "^${IDENTITY}[[:space:]]" "$signers" 2>/dev/null | head -1 || true)

  if [[ -n "$existing" ]]; then
    if [[ "$existing" == "$new_line" ]]; then
      echo "[coord-keygen] $IDENTITY already enrolled with this exact key — no-op." >&2
      grep -E "^${IDENTITY}[[:space:]]" "$signers"
      exit 0
    fi
    if [[ "$ALLOW_ROTATE" != 1 ]]; then
      echo "ERROR [coord-keygen]: $IDENTITY already has a DIFFERENT key enrolled in $signers." >&2
      echo "  existing: $existing" >&2
      echo "  new:      $new_line" >&2
      echo "Refusing a silent key-swap (impersonation vector). Re-run with --rotate to confirm a deliberate re-key." >&2
      exit 1
    fi
    echo "[coord-keygen] ⚠️ ROTATING the trusted signing key for $IDENTITY — this replaces what every reader currently trusts for that identity. Confirm this was a deliberate, out-of-band-verified re-key before proceeding further." >&2
  fi

  local tmp
  tmp=$(mktemp "$signers.XXXXXX")
  if [[ -n "$existing" ]]; then
    grep -vE "^${IDENTITY}[[:space:]]" "$signers" > "$tmp" 2>/dev/null || true
  else
    cat "$signers" > "$tmp" 2>/dev/null || true
  fi
  printf '%s\n' "$new_line" >> "$tmp"
  mv "$tmp" "$signers"

  # M4: read back and confirm.
  if ! grep -qF "$new_line" "$signers"; then
    echo "FATAL [coord-keygen]: enrollment write did not persist for $IDENTITY in $signers." >&2
    exit 1
  fi
  echo "[coord-keygen] Enrolled $IDENTITY in $signers." >&2
  grep -E "^${IDENTITY}[[:space:]]" "$signers"
}

do_fingerprint() {
  identity_charset_check "$IDENTITY" || exit 1
  if [[ -z "$COORD_DIR" ]]; then
    echo "ERROR [coord-keygen]: --fingerprint requires --dir." >&2
    exit 1
  fi
  local abs_dir key
  abs_dir=$(resolve_abs_dir "$COORD_DIR") || exit 1
  key=$(key_path_for "$abs_dir" "$IDENTITY") || exit 1
  if [[ ! -f "${key}.pub" ]]; then
    echo "ERROR [coord-keygen]: no public key found for $IDENTITY at ${key}.pub (run --generate first)." >&2
    exit 1
  fi
  ssh-keygen -lf "${key}.pub"
}

case "$MODE" in
  generate)    do_generate ;;
  enroll)      do_enroll ;;
  fingerprint) do_fingerprint ;;
  "")
    echo "ERROR [coord-keygen]: mode required: --generate | --enroll | --rotate | --fingerprint" >&2
    exit 1
    ;;
  *) echo "ERROR [coord-keygen]: unknown mode: $MODE" >&2; exit 1 ;;
esac

fi  # end CLI guard
