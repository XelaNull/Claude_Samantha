#!/usr/bin/env bash
# Coordination protocol smoke tests (bash 3.2). Usage: ./tests/run.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../coord-address-filter.sh
. "$ROOT/coord-address-filter.sh"
# shellcheck source=../coord-receipt.sh
. "$ROOT/coord-receipt.sh"
# shellcheck source=../coord-presence.sh
. "$ROOT/coord-presence.sh"
# shellcheck source=../PROTOCOL-VERSION
. "$ROOT/PROTOCOL-VERSION"

PASS=0
FAIL=0
assert_eq() {
  local name="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    printf 'PASS %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf 'FAIL %s\n  got:  %s\n  want: %s\n' "$name" "$got" "$want"
    FAIL=$((FAIL + 1))
  fi
}
assert_contains() {
  local name="$1" hay="$2" needle="$3"
  case "$hay" in
    *"$needle"*) printf 'PASS %s\n' "$name"; PASS=$((PASS + 1)) ;;
    *) printf 'FAIL %s (missing %s)\n' "$name" "$needle"; FAIL=$((FAIL + 1)) ;;
  esac
}
assert_not_contains() {
  local name="$1" hay="$2" needle="$3"
  case "$hay" in
    *"$needle"*) printf 'FAIL %s (unexpected %s)\n' "$name" "$needle"; FAIL=$((FAIL + 1)) ;;
    *) printf 'PASS %s\n' "$name"; PASS=$((PASS + 1)) ;;
  esac
}

assert_eq "protocol-version-file" "$PROTOCOL_VERSION" "1.5.0"

# PROTOCOL 1.5.0 §3.5 Part C/D: shared Protocol Version Handshake helpers
# (coord-presence.sh) — direct unit coverage of the predicate + message
# composer both coord-monitor.sh's Part B alert and README's documented
# Part A wording depend on.
assert_eq "protocol-version-major-simple" "$(protocol_version_major 1.5.0)" "1"
assert_eq "protocol-version-major-double-digit" "$(protocol_version_major 12.3.4)" "12"
assert_eq "protocol-mismatch-severity-minor" "$(protocol_mismatch_severity 1.5.0 1.4.0)" "MINOR/PATCH"
assert_eq "protocol-mismatch-severity-major" "$(protocol_mismatch_severity 1.5.0 2.0.0)" "MAJOR"
assert_eq "protocol-mismatch-severity-equal" "$(protocol_mismatch_severity 1.5.0 1.5.0)" "MINOR/PATCH"
PMM_OUT=$(protocol_mismatch_message orchestrator 1.5.0 impl-alpha 1.4.0)
assert_contains "protocol-mismatch-message-names-both-versions" "$PMM_OUT" "impl-alpha is running 1.4.0; orchestrator is running 1.5.0"
assert_contains "protocol-mismatch-message-minor-severity" "$PMM_OUT" "MINOR/PATCH"
assert_contains "protocol-mismatch-message-local-remediation-default" "$PMM_OUT" "git pull the coordination-protocol"
assert_not_contains "protocol-mismatch-message-no-canonical-source-value-when-unset" "$PMM_OUT" "the canonical framework lives at:"
PMM_MAJOR_OUT=$(protocol_mismatch_message orchestrator 1.5.0 impl-alpha 2.0.0)
assert_contains "protocol-mismatch-message-major-severity" "$PMM_MAJOR_OUT" "MAJOR — wire/grammar-breaking"
PMM_CANON_OUT=$(COORD_CANONICAL_SOURCE="git@example.com:org/fw.git" protocol_mismatch_message orchestrator 1.5.0 impl-alpha 1.4.0)
assert_contains "protocol-mismatch-message-honors-canonical-source" "$PMM_CANON_OUT" "git@example.com:org/fw.git"
assert_contains "protocol-mismatch-message-never-a-payload" "$PMM_CANON_OUT" "not a payload"

assert_eq "project-of-impl-sectorwars" "$(protocol_project_of_identity impl-sectorwars)" "sectorwars"
assert_eq "project-of-impl-sectorwars-ui" "$(protocol_project_of_identity impl-sectorwars-ui)" "sectorwars"
assert_eq "project-of-impl-aiclient" "$(protocol_project_of_identity impl-aiclient)" "aiclient"

AICLIENT=$(cat <<'EOF'

### 2026-08-09T12:00:00Z — orchestrator → impl-aiclient — 🤝 HANDOFF

**WO for aiclient only**
EOF
)
SW_SIB=$(cat <<'EOF'

### 2026-08-09T12:00:01Z — orchestrator → impl-sectorwars-ui — 🤝 HANDOFF

**WO for sibling Sectorwars seat**
EOF
)
SW_ME=$(cat <<'EOF'

### 2026-08-09T12:00:02Z — orchestrator → impl-sectorwars — 🤝 HANDOFF

**WO for me**
EOF
)
ALL=$(cat <<'EOF'

### 2026-08-09T12:00:03Z — orchestrator → ALL — 🔧 DEPLOY-WINDOW OPEN

Global broadcast
EOF
)
HUB_SELF=$(cat <<'EOF'

### 2026-08-09T12:00:04Z — orchestrator → orchestrator — 💓 HEARTBEAT [self-nudge]

⚡ **IDLE-KICK** hub only
EOF
)
MIXED="${AICLIENT}${SW_SIB}${SW_ME}${ALL}${HUB_SELF}"

if filtered=$(spoke_filter_delta "impl-sectorwars" "sectorwars" "$AICLIENT"); then
  assert_eq "other-project-silent" "emitted" "silent"
else
  assert_eq "other-project-silent" "silent" "silent"
fi

if filtered=$(spoke_filter_delta "impl-sectorwars" "sectorwars" "$SW_SIB"); then
  assert_contains "same-project-sibling-handoff" "$filtered" "sibling Sectorwars"
else
  assert_eq "same-project-sibling-handoff" "silent" "emitted"
fi

if filtered=$(spoke_filter_delta "impl-sectorwars" "sectorwars" "$SW_ME"); then
  assert_contains "self-handoff" "$filtered" "WO for me"
else
  assert_eq "self-handoff" "silent" "emitted"
fi

if filtered=$(spoke_filter_delta "impl-sectorwars" "sectorwars" "$ALL"); then
  assert_contains "all-broadcast" "$filtered" "DEPLOY-WINDOW OPEN"
else
  assert_eq "all-broadcast" "silent" "emitted"
fi

if filtered=$(spoke_filter_delta "impl-sectorwars" "sectorwars" "$HUB_SELF"); then
  assert_eq "hub-self-nudge-silent" "emitted" "silent"
else
  assert_eq "hub-self-nudge-silent" "silent" "silent"
fi

if filtered=$(spoke_filter_delta "impl-sectorwars" "sectorwars" "$MIXED"); then
  assert_contains "mixed-keeps-sibling" "$filtered" "sibling Sectorwars"
  assert_contains "mixed-keeps-self" "$filtered" "WO for me"
  assert_contains "mixed-keeps-all" "$filtered" "DEPLOY-WINDOW OPEN"
  assert_not_contains "mixed-drops-aiclient" "$filtered" "aiclient only"
  assert_not_contains "mixed-drops-hub-nudge" "$filtered" "hub only"
else
  assert_eq "mixed" "silent" "emitted"
fi

# Watch-set simulation: same-project peers listed, other project not
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP"
touch "$TMP/orchestrator.md" "$TMP/impl-sectorwars.md" "$TMP/impl-sectorwars-ui.md" "$TMP/impl-aiclient.md"
PROJECT=sectorwars
IDENT=impl-sectorwars
DIR=$TMP
ROLE=implementer
# inline watched() copy of monitor logic
watched_sim() {
  local f b p
  f="$DIR/orchestrator.md"; [ -e "$f" ] && printf '%s\n' "$f"
  for f in "$DIR"/impl-*.md; do
    [ -e "$f" ] || continue
    b=$(basename "$f" .md)
    [ "$b" = "$IDENT" ] && continue
    p=$(protocol_project_of_identity "$b")
    [ "$p" = "$PROJECT" ] || continue
    printf '%s\n' "$f"
  done
}
WATCH_LIST=$(watched_sim | xargs -n1 basename | tr '\n' ' ')
assert_contains "watch-has-hub" "$WATCH_LIST" "orchestrator.md"
assert_contains "watch-has-sibling" "$WATCH_LIST" "impl-sectorwars-ui.md"
assert_not_contains "watch-excludes-self" "$WATCH_LIST" "impl-sectorwars.md"
assert_not_contains "watch-excludes-other-project" "$WATCH_LIST" "impl-aiclient.md"

# 0c evidence refresh
MB="$TMP/orch.md"
cat > "$MB" <<'EOF'
role: orchestrator
watcher_pid: 12
heartbeat_pid: 34
state: Active

---
EOF
before=$(wc -c < "$MB" | tr -d ' ')
sed -i.bak 's/watcher_pid: 12/watcher_pid: 123456/' "$MB"
after=$(wc -c < "$MB" | tr -d ' ')
delta=$((after - before))
{
  printf '# Offset evidence (Phase 0c)\n\n'
  printf 'Measured on %s · PROTOCOL %s\n\n' "$(date -u +%FT%TZ)" "$PROTOCOL_VERSION"
  printf 'Header PID widen: %s → %s (delta %+d). Presence-split (Phase 4) removes this class.\n' "$before" "$after" "$delta"
} > "$ROOT/tests/OFFSET-EVIDENCE.md"
assert_eq "0c-notes" "$(test -s "$ROOT/tests/OFFSET-EVIDENCE.md" && echo yes)" "yes"

# Presence sidecar smoke
PRES_DIR="$TMP/pres-coord"
mkdir -p "$PRES_DIR"
# shellcheck source=../coord-presence.sh
. "$ROOT/coord-presence.sh"
presence_set "$PRES_DIR" "impl-sectorwars" "watcher_pid" "99"
presence_set "$PRES_DIR" "impl-sectorwars" "project" "sectorwars"
assert_eq "presence-get-pid" "$(presence_get "$PRES_DIR" "impl-sectorwars" "watcher_pid")" "99"
assert_eq "presence-get-project" "$(presence_get "$PRES_DIR" "impl-sectorwars" "project")" "sectorwars"

# ── PROTOCOL 1.4.0: Message Authenticity (SSH signing) ───────────────────────
# Hermetic: keys land under a throwaway HOME so this never touches the real
# ~/.samantha/coord-keys or a real allowed_signers.
SIG_OK=1
if ! command -v ssh-keygen >/dev/null 2>&1; then
  echo "SKIP [sig] ssh-keygen not found — skipping all Message Authenticity tests."
  SIG_OK=0
fi

if [ "$SIG_OK" = 1 ]; then
  export HOME="$TMP/home"
  mkdir -p "$HOME"
  SIGD="$TMP/sig-coord"
  mkdir -p "$SIGD"

  # (1) two throwaway identities: orchestrator self-enrolls, implementer enrolls
  #     via the bootstrap flow (--provision/--adopt), sign+verify round-trips clean.
  OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$SIGD" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$OLINE" --dir "$SIGD" >/dev/null
  assert_contains "sig-orchestrator-self-enrolled" "$(cat "$SIGD/allowed_signers")" "orchestrator namespaces=\"samantha-coord\""

  # (1z) round-2 item 7: coord-verify.sh's one-time OpenSSH version probe —
  # a fake `ssh` ahead of the real one on PATH, reporting a pre-8.9 version,
  # must produce the distinct version-floor WARN (naming the real cause)
  # rather than silently proceeding to misclassify every message as
  # UNKNOWN-SIGNER with no hint why. Real `ssh-keygen` still resolves
  # normally (only `ssh` is faked), so this exercises the actual `ssh -V`
  # code path, not just the version-comparison arithmetic in isolation.
  VERFLOOR_FAKEBIN="$TMP/verfloor-fakebin"
  mkdir -p "$VERFLOOR_FAKEBIN"
  cat > "$VERFLOOR_FAKEBIN/ssh" <<'EOF'
#!/bin/sh
echo "OpenSSH_8.2p1 Ubuntu-4ubuntu0.9, OpenSSL 1.1.1f  31 Mar 2020" >&2
exit 1
EOF
  chmod +x "$VERFLOOR_FAKEBIN/ssh"
  VERFLOOR_FILE="$TMP/verfloor-scratch.md"
  : > "$VERFLOOR_FILE"
  VERFLOOR_OUT=$(PATH="$VERFLOOR_FAKEBIN:$PATH" "$ROOT/coord-verify.sh" --dir "$SIGD" --file "$VERFLOOR_FILE" 2>&1)
  assert_contains "coord-verify-warns-on-old-openssh" "$VERFLOOR_OUT" "needs OpenSSH 8.9+"
  # A modern OpenSSH (the real one on this box, or any post-8.9 fake) must
  # NOT print the warning — proves the check isn't unconditionally noisy.
  VERFLOOR_MODERN_OUT=$("$ROOT/coord-verify.sh" --dir "$SIGD" --file "$VERFLOOR_FILE" 2>&1)
  assert_not_contains "coord-verify-silent-on-modern-openssh" "$VERFLOOR_MODERN_OUT" "needs OpenSSH 8.9+"

  : > "$SIGD/orchestrator.md"
  PROV_ID=$("$ROOT/bootstrap-identity.sh" --provision --dir "$SIGD" --zone "$TMP" 2>/dev/null)
  PUBLINE=$(grep '^pubkey:' "$SIGD/$PROV_ID.md" | sed 's/^pubkey: //')
  assert_contains "sig-provision-embeds-pubkey" "$PUBLINE" "ssh-ed25519"
  # PROTOCOL 1.5.0 §3.5 Part A: the HEADS-UP announces the newborn's own
  # PROTOCOL-VERSION alongside the pubkey — same carrier, no new message
  # type. Announce-only (no comparison possible yet — the newborn can't
  # know the hub's version before first contact).
  assert_contains "sig-provision-embeds-protocol-version" "$(cat "$SIGD/$PROV_ID.md")" "PROTOCOL-VERSION: $PROTOCOL_VERSION"
  "$ROOT/coord-keygen.sh" --enroll --identity impl-sigtest --pubkey-line "$PUBLINE" --dir "$SIGD" >/dev/null

  # (0b) item 14, 2026-08-09: --adopt validates PROVISIONAL's charset too, not
  # just ASSIGNED — both feed the same mv/path-building.
  ADOPT_BADPROV_RC=0
  ADOPT_BADPROV_OUT=$("$ROOT/bootstrap-identity.sh" --adopt --provisional '../escape' --assigned impl-sigtest --dir "$SIGD" 2>&1) || ADOPT_BADPROV_RC=$?
  assert_eq "bootstrap-adopt-rejects-bad-provisional-charset" "$ADOPT_BADPROV_RC" "1"
  assert_contains "bootstrap-adopt-bad-provisional-message" "$ADOPT_BADPROV_OUT" "unsafe characters"

  # (0c) item 15, 2026-08-09: --enroll rejects a --pubkey-line with an
  # embedded newline (would otherwise inject extra rows into allowed_signers)
  # and rejects a line that doesn't look like a real SSH public key.
  ENROLL_NL_RC=0
  ENROLL_NL_OUT=$("$ROOT/coord-keygen.sh" --enroll --identity impl-newlinetest --pubkey-line "$(printf 'ssh-ed25519 AAAAvalidlooking\nimpl-injected namespaces=\"samantha-coord\" ssh-ed25519 AAAAforged')" --dir "$SIGD" 2>&1) || ENROLL_NL_RC=$?
  assert_eq "coord-keygen-enroll-rejects-embedded-newline" "$ENROLL_NL_RC" "1"
  assert_contains "coord-keygen-enroll-embedded-newline-message" "$ENROLL_NL_OUT" "embedded newline"
  assert_eq "coord-keygen-enroll-newline-not-injected" "$(grep -c 'impl-injected' "$SIGD/allowed_signers" 2>/dev/null || true)" "0"

  ENROLL_SHAPE_RC=0
  ENROLL_SHAPE_OUT=$("$ROOT/coord-keygen.sh" --enroll --identity impl-shapetest --pubkey-line "not a real key" --dir "$SIGD" 2>&1) || ENROLL_SHAPE_RC=$?
  assert_eq "coord-keygen-enroll-rejects-bad-shape" "$ENROLL_SHAPE_RC" "1"
  assert_contains "coord-keygen-enroll-bad-shape-message" "$ENROLL_SHAPE_OUT" "does not look like a single valid SSH public key line"

  "$ROOT/bootstrap-identity.sh" --adopt --provisional "$PROV_ID" --assigned impl-sigtest --dir "$SIGD" >/dev/null 2>&1
  assert_eq "sig-adopt-renamed-file" "$(test -f "$SIGD/impl-sigtest.md" && echo yes)" "yes"
  # Key namespace is keyed off <coord-dir>/.coord-id contents (item 7,
  # 2026-08-09), not the absolute coord-dir path — see coord-keygen.sh's
  # compute_dirhash for why.
  COORD_ID_SIGD=$(tr -d '[:space:]' < "$SIGD/.coord-id")
  HASH_SIGD=$(printf '%s' "$COORD_ID_SIGD" | shasum -a 256 2>/dev/null | awk '{print $1}' | cut -c1-12)
  [ -z "$HASH_SIGD" ] && HASH_SIGD=$(printf '%s' "$COORD_ID_SIGD" | sha256sum | awk '{print $1}' | cut -c1-12)
  assert_eq "sig-key-carried-over" "$(test -f "$HOME/.samantha/coord-keys/$HASH_SIGD/impl-sigtest_ed25519" && echo yes)" "yes"

  # (1b) item 7, 2026-08-09: the key namespace must survive a coord-dir
  # move/rename — a portable framework's checkout gets moved/renamed/re-
  # cloned routinely, and an absolute-path-derived namespace silently
  # orphaned every already-provisioned key when that happened.
  # Capture the pubkey BEFORE the move — `assert_contains ... "ssh-ed25519"`
  # alone (round-1) was vacuous: ANY ed25519 pubkey matches that substring,
  # including a freshly-generated DIFFERENT key from a namespace regression
  # (e.g. back to path-based derivation) silently minting a new keypair
  # instead of finding the carried-over one. Exact-match against the
  # PRE-move pubkey is the only thing that actually proves survival.
  PRE_MOVE_KEY=$("$ROOT/coord-keygen.sh" --generate --identity impl-sigtest --dir "$SIGD" 2>/dev/null)
  SIGD_MOVED="$TMP/sig-coord-moved"
  mv "$SIGD" "$SIGD_MOVED"
  MOVED_KEY=$("$ROOT/coord-keygen.sh" --generate --identity impl-sigtest --dir "$SIGD_MOVED" 2>/dev/null)
  assert_eq "sig-key-path-survives-dir-move" "$(test -f "$HOME/.samantha/coord-keys/$HASH_SIGD/impl-sigtest_ed25519" && echo yes)" "yes"
  assert_eq "sig-key-path-survives-dir-move-same-pubkey" "$MOVED_KEY" "$PRE_MOVE_KEY"
  mv "$SIGD_MOVED" "$SIGD"

  "$ROOT/coord-send.sh" --identity impl-sigtest --dir "$SIGD" --to orchestrator --tag STATUS --body "round trip after adopt" >/dev/null 2>&1
  RT_OUT=$("$ROOT/coord-verify.sh" --dir "$SIGD" --file "$SIGD/impl-sigtest.md" 2>&1)
  assert_contains "sig-round-trip-verified" "$RT_OUT" "✅ VERIFIED impl-sigtest"
  assert_contains "sig-round-trip-no-invalid" "$RT_OUT" "0 invalid"

  # (1c0) item 3, 2026-08-09: a legitimately signed message whose BODY quotes
  # a prior message's header on its own line must verify as ONE message, not
  # have its signed region truncated at the quoted line (the exact misparse
  # the old "scan forward for next header-shaped line" heuristic produced —
  # the quote would look like the start of a second message and orphan the
  # real trailing SIG block), and must not be counted as two messages.
  BEFORE_COUNT=$("$ROOT/coord-verify.sh" --dir "$SIGD" --file "$SIGD/impl-sigtest.md" 2>&1 | sed -n 's/.*(\([0-9]*\) total message(s) scanned).*/\1/p')
  QUOTED_HDR_TS="2026-08-09T23:00:00Z"
  QUOTE_BODY_FILE=$(mktemp "$TMP/quote-body.XXXXXX")
  printf 'Quoting a prior header for context:\n### %s — impl-sigtest → orchestrator — 📋 STATUS\nthat is the end of the quoted line.' "$QUOTED_HDR_TS" > "$QUOTE_BODY_FILE"
  "$ROOT/coord-send.sh" --identity impl-sigtest --dir "$SIGD" --to orchestrator --tag STATUS --body-file "$QUOTE_BODY_FILE" >/dev/null 2>&1
  QUOTE_OUT=$("$ROOT/coord-verify.sh" --dir "$SIGD" --file "$SIGD/impl-sigtest.md" 2>&1 || true)
  AFTER_COUNT=$(printf '%s' "$QUOTE_OUT" | sed -n 's/.*(\([0-9]*\) total message(s) scanned).*/\1/p')
  assert_contains "sig-quoted-header-in-body-still-verified" "$QUOTE_OUT" "✅ VERIFIED impl-sigtest"
  assert_eq "sig-quoted-header-in-body-exactly-one-message-added" "$((AFTER_COUNT - BEFORE_COUNT))" "1"

  # (1c0b) round-3, item 2 (Rook): neither of the two tests above covers the
  # actual intersection Cipher exploited — sig-tamper-detected-invalid (below)
  # tampers a body with NO quoted header; sig-quoted-header-in-body-still-
  # verified (above) quotes a header but is never tampered. Cipher live-signed
  # a real 🤝 ASSIGN-IDENTITY reply whose body legitimately quoted a prior
  # header, MITM-tampered the payload, and got ⚠️ UNVERIFIED [exempt] instead
  # of ❌ INVALID — a real SIGNED, tampered message silently downgraded to
  # "unsigned, exempt, ok" because find_span's old ambiguous-fallback declined
  # association (the quoted line broke "unambiguous") and the header's own
  # TAG/FROM/TO shape happened to match exemption (b). Reproduce exactly that
  # shape: FROM=orchestrator, file=orchestrator.md (satisfies the FROM==
  # basename(file) structural gate exemption (b) itself requires), TAG=🤝
  # ASSIGN-IDENTITY, TO=pending-* — then tamper the payload post-signing.
  ASSIGND="$TMP/assign-tamper-coord"
  mkdir -p "$ASSIGND"
  : > "$ASSIGND/orchestrator.md"
  ASSIGN_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$ASSIGND" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$ASSIGN_OLINE" --dir "$ASSIGND" >/dev/null
  ASSIGN_QUOTED_TS="2026-08-09T23:45:00Z"
  ASSIGN_BODY_FILE=$(mktemp "$TMP/assign-quote-body.XXXXXX")
  printf 'You are: impl-alpha\nQuoting the provisioning HEADS-UP for context:\n### %s — pending-abc123 → orchestrator — 🛰️ HEADS-UP\nthat is the end of the quoted line. Pubkey enrolled under impl-alpha.' \
    "$ASSIGN_QUOTED_TS" > "$ASSIGN_BODY_FILE"
  "$ROOT/coord-send.sh" --identity orchestrator --dir "$ASSIGND" --to pending-abc123 --tag "🤝 ASSIGN-IDENTITY" --body-file "$ASSIGN_BODY_FILE" >/dev/null 2>&1
  # Confirm it verifies cleanly BEFORE tampering (sanity — proves the fixture
  # itself is a genuinely well-formed signed message, not already broken).
  ASSIGN_PRE_OUT=$("$ROOT/coord-verify.sh" --dir "$ASSIGND" --file "$ASSIGND/orchestrator.md" 2>&1)
  assert_contains "sig-tampered-quoted-header-assign-identity-pre-tamper-verified" "$ASSIGN_PRE_OUT" "✅ VERIFIED orchestrator"
  sed -i.bak 's/Pubkey enrolled under impl-alpha\./Pubkey enrolled under impl-EVIL — attacker substituted identity./' "$ASSIGND/orchestrator.md"
  ASSIGN_TAMPER_OUT=$("$ROOT/coord-verify.sh" --dir "$ASSIGND" --file "$ASSIGND/orchestrator.md" 2>&1) || true
  assert_contains "sig-tampered-quoted-header-assign-identity-invalid" "$ASSIGN_TAMPER_OUT" "❌ INVALID"
  assert_not_contains "sig-tampered-quoted-header-assign-identity-not-exempt" "$ASSIGN_TAMPER_OUT" "[exempt]"

  # (1c1) round-2 item 1/Rook: --find-boundary's OWN anchor selection used to
  # scan header_idxs directly (every header-SHAPED line, including ones
  # quoted inside a message's own body) instead of the main verify loop's
  # consumed-range walk — reintroducing the exact misparse bytes: was built
  # to kill, in just this one code path. Isolated fixture: ONE real message
  # whose body quotes a header-shaped line; call --find-boundary with N
  # landing ON the quoted line's own byte offset (the old bug's exact
  # trigger — the quoted line WAS in header_idxs and offsets[quoted] <= N)
  # and assert it snaps to the REAL header's line, never the quoted one's.
  FB_D="$TMP/find-boundary-coord"
  mkdir -p "$FB_D"
  : > "$FB_D/orchestrator.md"
  FB_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$FB_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$FB_OLINE" --dir "$FB_D" >/dev/null
  FB_QUOTED_TS="2026-08-09T23:30:00Z"
  FB_BODY_FILE=$(mktemp "$TMP/fb-quote-body.XXXXXX")
  printf 'Quoting a prior header for context:\n### %s — orchestrator → impl-other — 📋 STATUS\nthat is the end of the quoted line.' "$FB_QUOTED_TS" > "$FB_BODY_FILE"
  "$ROOT/coord-send.sh" --identity orchestrator --dir "$FB_D" --to impl-other --tag STATUS --body-file "$FB_BODY_FILE" >/dev/null 2>&1
  REAL_HDR_LINE=$(grep -n '^### ' "$FB_D/orchestrator.md" | head -1 | cut -d: -f1)
  REAL_HDR_LINEIDX=$((REAL_HDR_LINE - 1))
  QUOTED_LINE_BYTE=$(grep -bo "^### ${FB_QUOTED_TS}" "$FB_D/orchestrator.md" | head -1 | cut -d: -f1)
  FB_ANCHOR=$("$ROOT/coord-verify.sh" --dir "$FB_D" --file "$FB_D/orchestrator.md" --find-boundary "$QUOTED_LINE_BYTE" 2>&1)
  assert_eq "find-boundary-skips-body-quoted-header" "$FB_ANCHOR" "$REAL_HDR_LINEIDX"

  # (1c2) item 8, 2026-08-09: coord-send.sh's readback must catch "signed but
  # not actually enrolled" — the prior checks only confirmed SIG-SHAPED BYTES
  # landed (header text, body text, a PEM marker), never that the identity
  # is trusted. No allowed_signers entry exists yet for impl-unenrolled, so
  # ensure_signing_key auto-provisions and signs successfully, but
  # coord-verify.sh must read it back as UNKNOWN-SIGNER, not ✅ VERIFIED.
  UNENROLLD="$TMP/unenroll-coord"
  mkdir -p "$UNENROLLD"
  : > "$UNENROLLD/impl-unenrolled.md"
  UNENROLL_RC=0
  UNENROLL_OUT=$("$ROOT/coord-send.sh" --identity impl-unenrolled --dir "$UNENROLLD" --to orchestrator --tag STATUS --body "never enrolled" 2>&1) || UNENROLL_RC=$?
  assert_eq "coord-send-catches-unenrolled-identity" "$UNENROLL_RC" "1"
  assert_contains "coord-send-catches-unenrolled-identity-message" "$UNENROLL_OUT" "enrollment readback-verify FAILED"
  # The message still lands on disk (an already-appended write can't be
  # un-posted) — the check's job is to flag it loudly, not hide the append.
  assert_eq "coord-send-unenrolled-message-still-on-disk" "$(grep -c '^### ' "$UNENROLLD/impl-unenrolled.md" 2>/dev/null || true)" "1"

  # (1d) item 16, 2026-08-09: concurrent --enroll for DIFFERENT identities on
  # the SAME allowed_signers must never lose an update to the read-decide-
  # write race (two enrolls both reading "no existing entry", both mv-ing a
  # tmp file built from the same stale snapshot, loser's row silently
  # dropped). Launch several in parallel; every single one must land.
  LOCKD="$TMP/lock-coord"
  mkdir -p "$LOCKD"
  LOCK_PIDS=""
  for i in 1 2 3 4 5 6 7 8; do
    (
      KLINE=$("$ROOT/coord-keygen.sh" --generate --identity "impl-lockrace$i" --dir "$LOCKD" 2>/dev/null)
      "$ROOT/coord-keygen.sh" --enroll --identity "impl-lockrace$i" --pubkey-line "$KLINE" --dir "$LOCKD" >/dev/null 2>&1
    ) &
    LOCK_PIDS="$LOCK_PIDS $!"
  done
  for pid in $LOCK_PIDS; do wait "$pid" 2>/dev/null || true; done
  LOCK_COUNT=$(grep -c '^impl-lockrace' "$LOCKD/allowed_signers" 2>/dev/null || true)
  assert_eq "coord-keygen-enroll-concurrent-no-lost-update" "$LOCK_COUNT" "8"

  # (1c) item 13, 2026-08-09: identity charset is validated inside
  # key_path_for itself now, so a caller reaching it INDIRECTLY (coord-
  # send.sh via ensure_signing_key) is protected too, not just
  # coord-keygen.sh's own CLI dispatch. A metachar identity with an
  # otherwise-existing outbox file must still be refused before ever
  # reaching ssh-keygen or a filesystem path built from it.
  CHARSETD="$TMP/charset-coord"
  mkdir -p "$CHARSETD"
  printf 'role: implementer\n---\n' > "$CHARSETD/impl[bad].md"
  CHARSET_RC=0
  CHARSET_OUT=$("$ROOT/coord-send.sh" --identity 'impl[bad]' --dir "$CHARSETD" --to orchestrator --tag STATUS --body "should never sign" 2>&1) || CHARSET_RC=$?
  assert_eq "sig-send-rejects-bad-charset-identity" "$CHARSET_RC" "1"
  assert_contains "sig-send-bad-charset-identity-message" "$CHARSET_OUT" "must be non-empty and match"
  assert_eq "sig-send-bad-charset-no-key-written" "$(find "$HOME/.samantha/coord-keys" -name '*bad*' 2>/dev/null | wc -l | tr -d ' ')" "0"

  # (2) corrupt one byte in a signed message body -> ❌ INVALID.
  "$ROOT/coord-send.sh" --identity impl-sigtest --dir "$SIGD" --to orchestrator --tag STATUS --body "tamper me please" >/dev/null 2>&1
  sed -i.bak 's/tamper me please/TAMPERED PAYLOAD!/' "$SIGD/impl-sigtest.md"
  TAMPER_OUT=$("$ROOT/coord-verify.sh" --dir "$SIGD" --file "$SIGD/impl-sigtest.md" 2>&1) || true
  assert_contains "sig-tamper-detected-invalid" "$TAMPER_OUT" "❌ INVALID"

  # (3) unsigned message + --strict -> fails, EXCEPT the exempt shapes (the two
  #     bootstrap ones here; WATCHER-DOWN and HOLD-WAKE-UNACKED, the two
  #     dead-man-alarm ones, are exercised in (5d) and (5g) below).
  UNSIGNED_FILE="$TMP/unsigned.md"
  cat > "$UNSIGNED_FILE" <<'EOF'
### 2026-08-09T20:00:00Z — impl-sigtest → orchestrator — 💓 HEARTBEAT
Alive.
EOF
  NONSTRICT_RC=0
  "$ROOT/coord-verify.sh" --dir "$SIGD" --file "$UNSIGNED_FILE" >/dev/null 2>&1 || NONSTRICT_RC=$?
  assert_eq "sig-unsigned-nonstrict-passes" "$NONSTRICT_RC" "0"
  UNSIGNED_STRICT_RC=0
  "$ROOT/coord-verify.sh" --dir "$SIGD" --file "$UNSIGNED_FILE" --strict >/dev/null 2>&1 || UNSIGNED_STRICT_RC=$?
  assert_eq "sig-unsigned-strict-fails" "$UNSIGNED_STRICT_RC" "1"

  # Exemption (a) requires FROM == basename(file) (2026-08-09 hardening) — a
  # legitimate HEADS-UP can only ever live in its own poster's
  # pending-<uuid>.md, so the test file must be named to match.
  EXEMPT_HEADSUP="$TMP/pending-testexempt.md"
  cat > "$EXEMPT_HEADSUP" <<'EOF'
### 2026-08-09T20:01:00Z — pending-testexempt → orchestrator — 🛰️ HEADS-UP
Newborn implementer requesting identity assignment.
EOF
  EXEMPT_HEADSUP_RC=0
  "$ROOT/coord-verify.sh" --dir "$SIGD" --file "$EXEMPT_HEADSUP" --strict >/dev/null 2>&1 || EXEMPT_HEADSUP_RC=$?
  assert_eq "sig-exempt-pending-headsup-strict-passes" "$EXEMPT_HEADSUP_RC" "0"

  # Same HEADS-UP shape, wrong file — must NOT be exempt (closes "forge a
  # fake HEADS-UP with an attacker pubkey in any file").
  EXEMPT_HEADSUP_WRONGFILE="$TMP/pending-someone-else.md"
  cp "$EXEMPT_HEADSUP" "$EXEMPT_HEADSUP_WRONGFILE"
  EXEMPT_HEADSUP_WRONGFILE_RC=0
  "$ROOT/coord-verify.sh" --dir "$SIGD" --file "$EXEMPT_HEADSUP_WRONGFILE" --strict >/dev/null 2>&1 || EXEMPT_HEADSUP_WRONGFILE_RC=$?
  assert_eq "sig-exempt-headsup-wrong-file-strict-fails" "$EXEMPT_HEADSUP_WRONGFILE_RC" "1"

  # FROM == basename(file) is required for exemption (b) same as (a)/(c)
  # (round-2 hardening, item 3 above) — a real ASSIGN-IDENTITY reply only
  # ever lives in orchestrator.md, so the fixture must too.
  mkdir -p "$TMP/exempt-assign-scratch"
  EXEMPT_ASSIGN="$TMP/exempt-assign-scratch/orchestrator.md"
  cat > "$EXEMPT_ASSIGN" <<'EOF'
### 2026-08-09T20:02:00Z — orchestrator → pending-testexempt — 🤝 ASSIGN-IDENTITY
You are: impl-sigtest2
EOF
  EXEMPT_ASSIGN_RC=0
  "$ROOT/coord-verify.sh" --dir "$SIGD" --file "$EXEMPT_ASSIGN" --strict >/dev/null 2>&1 || EXEMPT_ASSIGN_RC=$?
  assert_eq "sig-exempt-assign-identity-strict-passes" "$EXEMPT_ASSIGN_RC" "0"

  # Same tag/FROM, but TO is NOT pending-* — must NOT be exempt (closes what
  # was an unconditional, permanent unsigned channel for anything claiming
  # FROM=orchestrator with this tag).
  EXEMPT_ASSIGN_BADTO="$TMP/exempt-assign-badto.md"
  cat > "$EXEMPT_ASSIGN_BADTO" <<'EOF'
### 2026-08-09T20:02:30Z — orchestrator → impl-sigtest2 — 🤝 ASSIGN-IDENTITY
You are: impl-sigtest2
EOF
  EXEMPT_ASSIGN_BADTO_RC=0
  "$ROOT/coord-verify.sh" --dir "$SIGD" --file "$EXEMPT_ASSIGN_BADTO" --strict >/dev/null 2>&1 || EXEMPT_ASSIGN_BADTO_RC=$?
  assert_eq "sig-exempt-assign-identity-non-pending-to-strict-fails" "$EXEMPT_ASSIGN_BADTO_RC" "1"

  # Round-2 item 3 (Rook/Cipher): exemption (b) previously carried NO
  # file-binding of its own -- a correctly-shaped, correctly-addressed
  # ASSIGN-IDENTITY reply landing in the WRONG file used to still pass as
  # exempt. Same header/body as the passing case above, wrong filename.
  EXEMPT_ASSIGN_WRONGFILE="$TMP/exempt-assign-scratch/not-orchestrator.md"
  cp "$EXEMPT_ASSIGN" "$EXEMPT_ASSIGN_WRONGFILE"
  EXEMPT_ASSIGN_WRONGFILE_RC=0
  "$ROOT/coord-verify.sh" --dir "$SIGD" --file "$EXEMPT_ASSIGN_WRONGFILE" --strict >/dev/null 2>&1 || EXEMPT_ASSIGN_WRONGFILE_RC=$?
  assert_eq "sig-exempt-assign-identity-wrong-file-strict-fails" "$EXEMPT_ASSIGN_WRONGFILE_RC" "1"

  # Round-2 item 3 companion: a FROM/file mismatch on an UNSIGNED message
  # declines the exemption (closing the hole above) but must NOT escalate
  # to INVALID the way a cryptographically-verified-but-mismatched message
  # does -- exemption (a)'s own HEADS-UP message is a real, permanently
  # mismatched artifact once bootstrap-identity.sh --adopt renames
  # pending-<uuid>.md to the assigned identity's file (the rename never
  # rewrites the message's FROM field). Escalating that case to INVALID
  # would make coord-verify.sh --dir ... --file ... (no --strict) exit
  # nonzero forever for every successfully-adopted identity -- a real
  # regression caught by running this suite, not a hypothetical. Assert
  # non-strict exit 0 on exactly that shape.
  MISMATCH_NOSTRICT_RC=0
  "$ROOT/coord-verify.sh" --dir "$SIGD" --file "$EXEMPT_ASSIGN_WRONGFILE" >/dev/null 2>&1 || MISMATCH_NOSTRICT_RC=$?
  assert_eq "sig-exempt-assign-identity-wrong-file-non-strict-passes" "$MISMATCH_NOSTRICT_RC" "0"

  # (4) precommit hook: BLOCKS when newly-read mail has an INVALID entry;
  #     does NOT re-verify old history already covered by a git commit
  #     (round-2, 2026-08-09: check 1b anchors on `git show HEAD:<file>`, not
  #     the forgeable receipt -- see coordination-precommit-hook.sh's check
  #     1b comment. HOOKD is a real git repo here specifically so this
  #     property is tested against the ACTUAL trust anchor, not the retired
  #     receipt-offset one).
  HOOKD="$TMP/hook-coord"
  mkdir -p "$HOOKD/.watch-state/impl-hooktest"
  HOLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$HOOKD" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$HOLINE" --dir "$HOOKD" >/dev/null

  cat > "$HOOKD/orchestrator.md" <<'EOF'
role: orchestrator
---
## Message Log

### 2026-07-01T10:00:00Z — orchestrator → impl-hooktest — 🛰️ HEADS-UP
Old pre-amendment unsigned message. Must never be re-scanned.
EOF
  write_receipt "$HOOKD/.watch-state/impl-hooktest/orchestrator.md.size" \
    "$(wc -c < "$HOOKD/orchestrator.md" | tr -d ' ')" "$HOOKD/orchestrator.md"
  ( cd "$HOOKD" && git init -q && git add orchestrator.md allowed_signers .coord-id \
      && git -c user.email=test@test -c user.name=test commit -q -m "pre-amendment history" )

  # Addressed to a THIRD seat (not impl-hooktest, not ALL) so Rule 4's own
  # unread-addressed gate stays silent and this exercises sig-verify in
  # isolation — it still sits in impl-hooktest's newly-read region and must
  # pass sig-verify cleanly (a valid signature from an unrelated-recipient
  # message is still a valid signature). Left UNCOMMITTED so it is exactly
  # what check 1b's git-anchored floor treats as "new since HEAD".
  "$ROOT/coord-send.sh" --identity orchestrator --dir "$HOOKD" --to impl-other --tag STATUS --body "post-amendment valid message" >/dev/null 2>&1

  HOOK_PASS_RC=0
  HOOK_PASS_OUT=$(cd "$HOOKD" && "$ROOT/coordination-precommit-hook.sh" "$HOOKD" "impl-hooktest" < /dev/null 2>&1) || HOOK_PASS_RC=$?
  assert_eq "sig-hook-passes-on-valid-new-mail" "$HOOK_PASS_RC" "0"
  assert_not_contains "sig-hook-no-old-history-flagged" "$HOOK_PASS_OUT" "pre-amendment"

  write_receipt "$HOOKD/.watch-state/impl-hooktest/orchestrator.md.size" \
    "$(wc -c < "$HOOKD/orchestrator.md" | tr -d ' ')" "$HOOKD/orchestrator.md"
  "$ROOT/coord-send.sh" --identity orchestrator --dir "$HOOKD" --to impl-hooktest --tag STATUS --body "this one gets tampered" >/dev/null 2>&1
  sed -i.bak 's/this one gets tampered/TAMPERED IN HOOK TEST/' "$HOOKD/orchestrator.md"

  HOOK_BLOCK_RC=0
  HOOK_BLOCK_OUT=$(cd "$HOOKD" && "$ROOT/coordination-precommit-hook.sh" "$HOOKD" "impl-hooktest" < /dev/null 2>&1) || HOOK_BLOCK_RC=$?
  assert_eq "sig-hook-blocks-on-invalid" "$HOOK_BLOCK_RC" "2"
  assert_contains "sig-hook-blocks-shows-invalid-verdict" "$HOOK_BLOCK_OUT" "❌ INVALID"

  # (4a1) round-2 item 1 (Cipher HIGH, live-demonstrated): the receipt-forged
  # bypass from round 1 must no longer work against --strict sig-verify at
  # all. Git-committed clean history (as HOOKD above), then a genuinely bad
  # (unsigned, non-exempt) message appended UNCOMMITTED, PLUS a forged
  # receipt claiming "fully read, verified" past that bad message with a
  # hash write_receipt never actually computed. Under the OLD (round-1)
  # design this receipt would have been rejected too (coord-receipt.sh's own
  # hash-binding still catches an outright hash mismatch) — the REAL round-1
  # hole was subtler: an attacker who can compute a matching hash (trivial —
  # sha256 isn't a keyed MAC) could write a SELF-CONSISTENT forged receipt
  # and it WOULD have been trusted. This fixture does exactly that: the
  # receipt's hash is freshly, correctly computed over the bad message's own
  # prefix via write_receipt itself (the same helper an honest watcher
  # uses) — i.e. NOT malformed, NOT hash-mismatched, a fully "valid-shaped"
  # forged receipt claiming everything is read and clean. Round-1 code would
  # have trusted it and skipped sig-verify entirely (full bypass). The hook
  # must still block, because check 1b no longer reads this receipt at all.
  FORGE2_D="$TMP/hook-coord-forge2"
  mkdir -p "$FORGE2_D/.watch-state/impl-forge2test"
  FORGE2_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$FORGE2_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$FORGE2_OLINE" --dir "$FORGE2_D" >/dev/null
  cat > "$FORGE2_D/orchestrator.md" <<'EOF'
role: orchestrator
---
## Message Log
EOF
  ( cd "$FORGE2_D" && git init -q && git add orchestrator.md allowed_signers .coord-id \
      && git -c user.email=test@test -c user.name=test commit -q -m "clean start" )
  cat >> "$FORGE2_D/orchestrator.md" <<'EOF'

### 2026-08-09T22:15:00Z — orchestrator → impl-forge2test — 📋 STATUS
Unsigned message the forged receipt below claims is already read and clean.
EOF
  # A "valid-shaped" forged receipt: hash IS correctly computed via the real
  # helper (self-consistent, would have passed round-1's own forgery check)
  # but was never actually written by an honest watcher that read this far.
  write_receipt "$FORGE2_D/.watch-state/impl-forge2test/orchestrator.md.size" \
    "$(wc -c < "$FORGE2_D/orchestrator.md" | tr -d ' ')" "$FORGE2_D/orchestrator.md"
  FORGE2_RC=0
  FORGE2_OUT=$(cd "$FORGE2_D" && "$ROOT/coordination-precommit-hook.sh" "$FORGE2_D" "impl-forge2test" < /dev/null 2>&1) || FORGE2_RC=$?
  assert_eq "sig-hook-valid-shaped-forged-receipt-still-blocks" "$FORGE2_RC" "2"
  assert_contains "sig-hook-valid-shaped-forged-receipt-shows-unverified" "$FORGE2_OUT" "UNVERIFIED"

  # (4a2) round-2 item 1: a brand-new/never-committed mailbox file (empty
  # HEAD state — `git show HEAD:<file>` fails because the file was never
  # committed, not because it doesn't exist) must fall back to verifying the
  # WHOLE file, not silently treat any of it as already-covered. FORGE2_D's
  # OWN fixture above already proves this incidentally (nothing in it is
  # committed except the clean prefix) — this uses a completely fresh
  # (never git-init'd at all) coord-dir to isolate the "not a git repo, or
  # file untracked" path on its own, with a bad message as the ENTIRE file
  # content (no clean prefix to speak of).
  UNTRACKED_D="$TMP/hook-coord-untracked"
  mkdir -p "$UNTRACKED_D/.watch-state/impl-untrackedtest"
  UNTRACKED_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$UNTRACKED_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$UNTRACKED_OLINE" --dir "$UNTRACKED_D" >/dev/null
  cat > "$UNTRACKED_D/orchestrator.md" <<'EOF'
role: orchestrator
---
## Message Log

### 2026-08-09T22:16:00Z — orchestrator → impl-untrackedtest — 📋 STATUS
Unsigned message in a coord-dir that was never git-init'd at all.
EOF
  UNTRACKED_RC=0
  UNTRACKED_OUT=$("$ROOT/coordination-precommit-hook.sh" "$UNTRACKED_D" "impl-untrackedtest" < /dev/null 2>&1) || UNTRACKED_RC=$?
  assert_eq "sig-hook-untracked-file-verifies-whole-file" "$UNTRACKED_RC" "2"
  assert_contains "sig-hook-untracked-file-shows-unverified" "$UNTRACKED_OUT" "UNVERIFIED"

  # (4a2) item 9, 2026-08-09: a spoke's inbox set must include same-project
  # peer outboxes (PROTOCOL 1.3.0 sibling awareness), not just
  # orchestrator.md — this hook's INBOX_FILES used to be 1.2.x-shaped and
  # would silently never even LOOK at a sibling's unread, addressed-to-me
  # message. impl-projx-b posts to impl-projx-a; impl-projx-a has never read
  # it (no receipt at all for impl-projx-b.md) — the hook must block.
  HOOKD4="$TMP/hook-coord-project"
  mkdir -p "$HOOKD4/.watch-state/impl-projx-a"
  P4LINE=$("$ROOT/coord-keygen.sh" --generate --identity impl-projx-b --dir "$HOOKD4" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity impl-projx-b --pubkey-line "$P4LINE" --dir "$HOOKD4" >/dev/null
  : > "$HOOKD4/orchestrator.md"
  write_receipt "$HOOKD4/.watch-state/impl-projx-a/orchestrator.md.size" 0 "$HOOKD4/orchestrator.md"
  : > "$HOOKD4/impl-projx-b.md"
  # Establish an explicit 0-byte baseline receipt for the sibling's outbox
  # BEFORE it posts — otherwise the hook's own first-run auto-init (treat
  # pre-existing content as already read, so a fresh implementer never gets
  # blocked on sibling history that predates them) would swallow the very
  # message this test needs to prove gets caught.
  write_receipt "$HOOKD4/.watch-state/impl-projx-a/impl-projx-b.md.size" 0 "$HOOKD4/impl-projx-b.md"
  "$ROOT/coord-send.sh" --identity impl-projx-b --dir "$HOOKD4" --to impl-projx-a --tag STATUS --body "sibling status update" >/dev/null 2>&1

  PROJECT_RC=0
  PROJECT_OUT=$("$ROOT/coordination-precommit-hook.sh" "$HOOKD4" "impl-projx-a" < /dev/null 2>&1) || PROJECT_RC=$?
  assert_eq "hook-inbox-includes-same-project-peer" "$PROJECT_RC" "2"
  assert_contains "hook-inbox-peer-unread-shown" "$PROJECT_OUT" "impl-projx-b.md"

  # Same fixture, but impl-projx-a has ALREADY acknowledged the sibling's
  # outbox — must pass cleanly (proves the new watch isn't just permanently
  # noisy, it actually tracks a real per-file receipt like orchestrator.md).
  write_receipt "$HOOKD4/.watch-state/impl-projx-a/impl-projx-b.md.size" \
    "$(wc -c < "$HOOKD4/impl-projx-b.md" | tr -d ' ')" "$HOOKD4/impl-projx-b.md"
  PROJECT_READ_RC=0
  "$ROOT/coordination-precommit-hook.sh" "$HOOKD4" "impl-projx-a" < /dev/null >/dev/null 2>&1 || PROJECT_READ_RC=$?
  assert_eq "hook-inbox-peer-clean-after-read" "$PROJECT_READ_RC" "0"

  # (4b) receipt-forgery hardening (item 1, 2026-08-09) — scope narrowed
  # round-2: coord-receipt.sh's hash-binding is now used ONLY by check 1a,
  # the Rule-4 "have you read your mail" nudge (check 1b / --strict
  # sig-verify no longer reads this receipt at all — see FORGE2_D above for
  # that). This still proves check 1a itself: a hand-forged/bumped receipt
  # claiming "fully read up to EOF" with a verified_sha256 that was never
  # actually computed by write_receipt must NOT be trusted by the nudge — it
  # falls back to offset=0. (The hook's overall FAIL/exit-2 here is now
  # doubly-caused — check 1a's own unread-addressed gate never even fires
  # since this message isn't addressed to impl-forgetest, but check 1b
  # independently flags the same message too, since it is genuinely
  # unsigned and this coord-dir has no git history to anchor on — see the
  # "hash mismatch" assertion below, which is check 1a's own diagnostic and
  # is what this test is actually about.)
  HOOKD3="$TMP/hook-coord-forge"
  mkdir -p "$HOOKD3/.watch-state/impl-forgetest"
  F3LINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$HOOKD3" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$F3LINE" --dir "$HOOKD3" >/dev/null
  cat > "$HOOKD3/orchestrator.md" <<'EOF'
role: orchestrator
---
## Message Log

### 2026-08-09T22:00:00Z — orchestrator → impl-forgetest — 📋 STATUS
Unsigned message that must be caught unless the receipt is blindly trusted.
EOF
  FORGE_N=$(wc -c < "$HOOKD3/orchestrator.md" | tr -d ' ')
  FORGE_BADHASH=$(printf 'a%.0s' $(seq 1 64))
  printf 'offset=%s\nverified_sha256=%s\n' "$FORGE_N" "$FORGE_BADHASH" \
    > "$HOOKD3/.watch-state/impl-forgetest/orchestrator.md.size"
  FORGE_RC=0
  FORGE_OUT=$("$ROOT/coordination-precommit-hook.sh" "$HOOKD3" "impl-forgetest" < /dev/null 2>&1) || FORGE_RC=$?
  assert_eq "sig-receipt-forged-hash-not-trusted" "$FORGE_RC" "2"
  assert_contains "sig-receipt-forged-hash-warns" "$FORGE_OUT" "hash mismatch"

  # (4c) receipt-forgery hardening, retroactive-tamper case — scope narrowed
  # round-2, same as (4b) above: this now proves check 1a's own nudge is
  # still correctly bound to actual bytes (a receipt that WAS legitimately
  # written by write_receipt still must not be trusted by the nudge once the
  # content it covers has since been mutated), not that it protects
  # check-1b's sig-verify (which never reads this receipt at all now).
  HOOKD3B="$TMP/hook-coord-tamperhist"
  mkdir -p "$HOOKD3B/.watch-state/impl-tamperhisttest"
  F3BLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$HOOKD3B" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$F3BLINE" --dir "$HOOKD3B" >/dev/null
  cat > "$HOOKD3B/orchestrator.md" <<'EOF'
role: orchestrator
---
## Message Log

### 2026-08-09T22:01:00Z — orchestrator → impl-tamperhisttest — 🛰️ HEADS-UP
Original acknowledged history, never meant to be re-scanned.
EOF
  write_receipt "$HOOKD3B/.watch-state/impl-tamperhisttest/orchestrator.md.size" \
    "$(wc -c < "$HOOKD3B/orchestrator.md" | tr -d ' ')" "$HOOKD3B/orchestrator.md"
  # Mutate the ALREADY-ACKNOWLEDGED region after the receipt was written —
  # the stored verified_sha256 no longer matches this file's real prefix.
  sed -i.bak 's/never meant to be re-scanned/REWRITTEN AFTER RECEIPT/' "$HOOKD3B/orchestrator.md"
  "$ROOT/coord-send.sh" --identity orchestrator --dir "$HOOKD3B" --to impl-other --tag STATUS --body "new mail after the tamper" >/dev/null 2>&1
  # The new mail above is validly signed; the FAIL this test asserts on comes
  # from the stale receipt being rejected and the ORIGINAL (never-signed)
  # message being re-scanned as non-exempt UNVERIFIED — proving the tamper
  # actually forces re-verification instead of being silently honored.
  TAMPERHIST_RC=0
  TAMPERHIST_OUT=$("$ROOT/coordination-precommit-hook.sh" "$HOOKD3B" "impl-tamperhisttest" < /dev/null 2>&1) || TAMPERHIST_RC=$?
  assert_eq "sig-receipt-tampered-history-not-trusted" "$TAMPERHIST_RC" "2"
  assert_contains "sig-receipt-tampered-history-warns" "$TAMPERHIST_OUT" "hash mismatch"

  # (4d) boundary-snap, historical fixture — scope narrowed round-2: this
  # dates from when check 1b's floor came from the RECEIPT's own offset (a
  # mid-message receipt offset had to be snapped via --find-boundary so
  # verification didn't start after the header and silently miss a tampered
  # signature). That specific mechanism is retired — check 1b no longer
  # reads the receipt at all (see FORGE2_D above), so MID_BYTE below has no
  # effect on check 1b's own floor anymore. Kept as a regression test
  # because it still exercises a REAL path: this coord-dir has no git
  # history, so check 1b's git-anchor is 0 and it verifies the whole file
  # regardless of MID_BYTE — the tampered message is still caught, just via
  # "verify everything" rather than a snap. The boundary-snap mechanism
  # ITSELF is now covered directly by find-boundary-skips-body-quoted-header
  # above (Rook's actual round-2 finding: --find-boundary's own anchor
  # selection, not this receipt-offset scenario).
  HOOKD5="$TMP/hook-coord-boundary"
  mkdir -p "$HOOKD5/.watch-state/impl-boundarytest"
  H5LINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$HOOKD5" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$H5LINE" --dir "$HOOKD5" >/dev/null
  : > "$HOOKD5/orchestrator.md"
  "$ROOT/coord-send.sh" --identity orchestrator --dir "$HOOKD5" --to impl-other --tag STATUS --body "AAAA BBBB CCCC DDDD EEEE" >/dev/null 2>&1
  HDR_BYTE=$(grep -bo '^### ' "$HOOKD5/orchestrator.md" | head -1 | cut -d: -f1)
  SIG_BYTE=$(grep -bo '<!-- SIG' "$HOOKD5/orchestrator.md" | head -1 | cut -d: -f1)
  MID_BYTE=$(( (HDR_BYTE + SIG_BYTE) / 2 ))
  write_receipt "$HOOKD5/.watch-state/impl-boundarytest/orchestrator.md.size" "$MID_BYTE" "$HOOKD5/orchestrator.md"
  sed -i.bak 's/DDDD EEEE/ZZZZ TAMPERED/' "$HOOKD5/orchestrator.md"
  BOUNDARY_RC=0
  BOUNDARY_OUT=$("$ROOT/coordination-precommit-hook.sh" "$HOOKD5" "impl-boundarytest" < /dev/null 2>&1) || BOUNDARY_RC=$?
  assert_eq "sig-hook-boundary-snap-catches-tamper-after-mid-message-receipt" "$BOUNDARY_RC" "2"
  assert_contains "sig-hook-boundary-snap-invalid-verdict-shown" "$BOUNDARY_OUT" "❌ INVALID"

  # (4e) item 2, human-approved 2026-08-09: any commit touching allowed_signers
  # is BLOCKED unless an authorization reference is present — unconditional,
  # not gated behind COORD_GATED_PATH_PATTERN. This exercises the REAL
  # Claude-Code-hook stdin-JSON path (not standalone mode) since the auth
  # marker must be read from the actual command text, which standalone
  # mode's placeholder cmd_field never carries.
  if command -v git >/dev/null 2>&1; then
    GATE_REPO="$TMP/gate-repo"
    mkdir -p "$GATE_REPO"
    (cd "$GATE_REPO" && git init -q && git config user.email test@test.com && git config user.name test)
    printf 'orchestrator namespaces="samantha-coord" ssh-ed25519 AAAAfakekeymaterial orchestrator@x\n' > "$GATE_REPO/allowed_signers"
    (cd "$GATE_REPO" && git add allowed_signers)

    GATE_NOAUTH_RC=0
    GATE_NOAUTH_OUT=$(cd "$GATE_REPO" && printf '%s' '{"tool_input":{"command":"git commit -m \"rotate signer\""}}' | "$ROOT/coordination-precommit-hook.sh" "$TMP/gate-coord-unused" "test-id" 2>&1) || GATE_NOAUTH_RC=$?
    assert_eq "hook-allowed-signers-gate-blocks-without-auth" "$GATE_NOAUTH_RC" "2"
    assert_contains "hook-allowed-signers-gate-blocks-message" "$GATE_NOAUTH_OUT" "FAIL [allowed_signers-gate]"

    GATE_AUTH_RC=0
    GATE_AUTH_OUT=$(cd "$GATE_REPO" && printf '%s' '{"tool_input":{"command":"git commit -m \"rotate signer AUTH: DECISION-42\""}}' | "$ROOT/coordination-precommit-hook.sh" "$TMP/gate-coord-unused" "test-id" 2>&1) || GATE_AUTH_RC=$?
    assert_eq "hook-allowed-signers-gate-passes-with-auth" "$GATE_AUTH_RC" "0"
    assert_contains "hook-allowed-signers-gate-passes-message" "$GATE_AUTH_OUT" "OK [allowed_signers-gate]"

    # A commit that does NOT touch allowed_signers must never trip this gate
    # (unstage it first — the prior two sub-tests never actually committed,
    # so it would otherwise still be sitting in the staged diff).
    (cd "$GATE_REPO" && git reset -q allowed_signers)
    printf 'unrelated content\n' > "$GATE_REPO/README.md"
    (cd "$GATE_REPO" && git add README.md)
    GATE_UNRELATED_RC=0
    GATE_UNRELATED_OUT=$(cd "$GATE_REPO" && printf '%s' '{"tool_input":{"command":"git commit -m \"docs\""}}' | "$ROOT/coordination-precommit-hook.sh" "$TMP/gate-coord-unused" "test-id" 2>&1) || GATE_UNRELATED_RC=$?
    assert_eq "hook-allowed-signers-gate-silent-on-unrelated-commit" "$GATE_UNRELATED_RC" "0"
    assert_not_contains "hook-allowed-signers-gate-silent-on-unrelated-commit-msg" "$GATE_UNRELATED_OUT" "allowed_signers-gate"

    # Round-2 item 5, gap 1: `git commit -am`/`-a` stages tracked
    # modifications AT COMMIT TIME -- must be caught even though nothing is
    # staged in the index yet when this hook runs. Mutate the ALREADY
    # TRACKED (committed-once via check 5's earlier flow having reset it —
    # actually still only added, never committed; commit it now for a clean
    # tracked baseline) allowed_signers via direct edit, leave unstaged.
    (cd "$GATE_REPO" && git add allowed_signers && git commit -q -m "baseline")
    printf 'orchestrator namespaces="samantha-coord" ssh-ed25519 AAAAdifferentkeymaterial orchestrator@x\n' > "$GATE_REPO/allowed_signers"
    GATE_DASHA_RC=0
    GATE_DASHA_OUT=$(cd "$GATE_REPO" && printf '%s' '{"tool_input":{"command":"git commit -am \"rotate signer\""}}' | "$ROOT/coordination-precommit-hook.sh" "$TMP/gate-coord-unused" "test-id" 2>&1) || GATE_DASHA_RC=$?
    assert_eq "hook-allowed-signers-gate-catches-commit-dash-a" "$GATE_DASHA_RC" "2"
    assert_contains "hook-allowed-signers-gate-catches-commit-dash-a-msg" "$GATE_DASHA_OUT" "FAIL [allowed_signers-gate]"
    (cd "$GATE_REPO" && git checkout -q -- allowed_signers)

    # Round-2 item 5, gap 2: an unparseable/ambiguous command must still run
    # this gate (fail-closed, matching check 1's own posture), not silently
    # skip it because the "(command unknown...)" placeholder text used to
    # not literally contain "git commit"/"git push". Genuinely malformed
    # (non-JSON) stdin triggers the same extract-failed path a real hook
    # invocation would hit if Claude Code's payload shape ever changed
    # unexpectedly. allowed_signers still staged (from the noauth sub-test,
    # never committed at that point... it IS committed now from the -am
    # sub-test above, so re-stage a fresh unstaged edit for this one too).
    printf 'orchestrator namespaces="samantha-coord" ssh-ed25519 AAAAyetanotherkey orchestrator@x\n' > "$GATE_REPO/allowed_signers"
    (cd "$GATE_REPO" && git add allowed_signers)
    GATE_AMBIG_RC=0
    GATE_AMBIG_OUT=$(cd "$GATE_REPO" && printf 'not json at all' | "$ROOT/coordination-precommit-hook.sh" "$TMP/gate-coord-unused" "test-id" 2>&1) || GATE_AMBIG_RC=$?
    assert_eq "hook-allowed-signers-gate-fires-on-ambiguous-command" "$GATE_AMBIG_RC" "2"
    assert_contains "hook-allowed-signers-gate-fires-on-ambiguous-command-msg" "$GATE_AMBIG_OUT" "FAIL [allowed_signers-gate]"
    (cd "$GATE_REPO" && git reset -q allowed_signers && git checkout -q -- allowed_signers)

    # Round-2 item 5, gap 3: DECISION-[A-Z0-9-]+ under -i matched generic
    # English prose containing "decision-" (decision-tree, decision-making)
    # and this protocol's OWN unrelated DECISION-NEEDED vocabulary -- must
    # NOT satisfy the gate; only a DECISION ref ending in a digit does.
    printf 'orchestrator namespaces="samantha-coord" ssh-ed25519 AAAAonemorekey orchestrator@x\n' > "$GATE_REPO/allowed_signers"
    (cd "$GATE_REPO" && git add allowed_signers)
    GATE_FAKEDEC_RC=0
    GATE_FAKEDEC_OUT=$(cd "$GATE_REPO" && printf '%s' '{"tool_input":{"command":"git commit -m \"rotate signer per decision-tree analysis, DECISION-NEEDED review\""}}' | "$ROOT/coordination-precommit-hook.sh" "$TMP/gate-coord-unused" "test-id" 2>&1) || GATE_FAKEDEC_RC=$?
    assert_eq "hook-allowed-signers-gate-rejects-fake-decision-ref" "$GATE_FAKEDEC_RC" "2"
    assert_contains "hook-allowed-signers-gate-rejects-fake-decision-ref-msg" "$GATE_FAKEDEC_OUT" "FAIL [allowed_signers-gate]"
    (cd "$GATE_REPO" && git reset -q allowed_signers && git checkout -q -- allowed_signers)

    printf 'orchestrator namespaces="samantha-coord" ssh-ed25519 AAAArealdeckey orchestrator@x\n' > "$GATE_REPO/allowed_signers"
    GATE_REALDEC_RC=0
    GATE_REALDEC_OUT=$(cd "$GATE_REPO" && printf '%s' '{"tool_input":{"command":"git commit -am \"rotate signer per DECISION-17\""}}' | "$ROOT/coordination-precommit-hook.sh" "$TMP/gate-coord-unused" "test-id" 2>&1) || GATE_REALDEC_RC=$?
    assert_eq "hook-allowed-signers-gate-accepts-real-decision-ref" "$GATE_REALDEC_RC" "0"
    (cd "$GATE_REPO" && git checkout -q -- allowed_signers)

    # (4f) round-3, item 1 (Cipher CRITICAL): the self-filter used to gate on a
    # literal "git commit"/"git push" substring, so `git merge`, `git
    # cherry-pick`, `git rebase --continue`, and `git am` all bypassed EVERY
    # check (including this allowed_signers gate) with zero output — full
    # bypass, no --no-verify needed. Re-stage the same untouched-with-auth
    # allowed_signers content each sub-test needs by re-writing it fresh
    # (git add stages it; each hook invocation only READS the diff, never
    # commits, so the staged state persists sub-test to sub-test until reset).
    printf 'orchestrator namespaces="samantha-coord" ssh-ed25519 AAAAmergeverbkey orchestrator@x\n' > "$GATE_REPO/allowed_signers"
    (cd "$GATE_REPO" && git add allowed_signers)
    GATE_MERGE_RC=0
    GATE_MERGE_OUT=$(cd "$GATE_REPO" && printf '%s' '{"tool_input":{"command":"git merge --no-edit feature-branch"}}' | "$ROOT/coordination-precommit-hook.sh" "$TMP/gate-coord-unused" "test-id" 2>&1) || GATE_MERGE_RC=$?
    assert_eq "hook-verb-coverage-merge-blocks-without-auth" "$GATE_MERGE_RC" "2"
    assert_contains "hook-verb-coverage-merge-blocks-message" "$GATE_MERGE_OUT" "FAIL [allowed_signers-gate]"

    GATE_CHERRY_RC=0
    GATE_CHERRY_OUT=$(cd "$GATE_REPO" && printf '%s' '{"tool_input":{"command":"git cherry-pick abc1234"}}' | "$ROOT/coordination-precommit-hook.sh" "$TMP/gate-coord-unused" "test-id" 2>&1) || GATE_CHERRY_RC=$?
    assert_eq "hook-verb-coverage-cherry-pick-blocks-without-auth" "$GATE_CHERRY_RC" "2"
    assert_contains "hook-verb-coverage-cherry-pick-blocks-message" "$GATE_CHERRY_OUT" "FAIL [allowed_signers-gate]"

    GATE_REBASE_RC=0
    GATE_REBASE_OUT=$(cd "$GATE_REPO" && printf '%s' '{"tool_input":{"command":"git rebase --continue"}}' | "$ROOT/coordination-precommit-hook.sh" "$TMP/gate-coord-unused" "test-id" 2>&1) || GATE_REBASE_RC=$?
    assert_eq "hook-verb-coverage-rebase-continue-blocks-without-auth" "$GATE_REBASE_RC" "2"
    assert_contains "hook-verb-coverage-rebase-continue-blocks-message" "$GATE_REBASE_OUT" "FAIL [allowed_signers-gate]"

    GATE_AM_RC=0
    GATE_AM_OUT=$(cd "$GATE_REPO" && printf '%s' '{"tool_input":{"command":"git am /tmp/some.mbox"}}' | "$ROOT/coordination-precommit-hook.sh" "$TMP/gate-coord-unused" "test-id" 2>&1) || GATE_AM_RC=$?
    assert_eq "hook-verb-coverage-am-blocks-without-auth" "$GATE_AM_RC" "2"
    assert_contains "hook-verb-coverage-am-blocks-message" "$GATE_AM_OUT" "FAIL [allowed_signers-gate]"

    GATE_MERGE_AUTH_RC=0
    GATE_MERGE_AUTH_OUT=$(cd "$GATE_REPO" && printf '%s' '{"tool_input":{"command":"git merge --no-edit -m \"merge AUTH: DECISION-42\" feature-branch"}}' | "$ROOT/coordination-precommit-hook.sh" "$TMP/gate-coord-unused" "test-id" 2>&1) || GATE_MERGE_AUTH_RC=$?
    assert_eq "hook-verb-coverage-merge-passes-with-auth" "$GATE_MERGE_AUTH_RC" "0"
    assert_contains "hook-verb-coverage-merge-passes-message" "$GATE_MERGE_AUTH_OUT" "OK [allowed_signers-gate]"

    # A commit-landing verb that does NOT touch allowed_signers must still not
    # trip this gate (over-detection would be a false positive, not the bug
    # being tested here — confirms the verb widening didn't turn into a
    # blanket block on every merge/cherry-pick/rebase/am regardless of paths).
    (cd "$GATE_REPO" && git reset -q allowed_signers && git checkout -q -- allowed_signers)
    printf 'unrelated content 2\n' > "$GATE_REPO/README2.md"
    (cd "$GATE_REPO" && git add README2.md)
    GATE_MERGE_UNRELATED_RC=0
    GATE_MERGE_UNRELATED_OUT=$(cd "$GATE_REPO" && printf '%s' '{"tool_input":{"command":"git merge --no-edit feature-branch"}}' | "$ROOT/coordination-precommit-hook.sh" "$TMP/gate-coord-unused" "test-id" 2>&1) || GATE_MERGE_UNRELATED_RC=$?
    assert_eq "hook-verb-coverage-merge-silent-on-unrelated" "$GATE_MERGE_UNRELATED_RC" "0"
    assert_not_contains "hook-verb-coverage-merge-silent-on-unrelated-msg" "$GATE_MERGE_UNRELATED_OUT" "allowed_signers-gate"
    (cd "$GATE_REPO" && git reset -q README2.md)

    # A verb NOT in the expanded list (e.g. `git status`, `git log`) must still
    # be positively identified as not-a-commit-landing/push verb and allowed
    # immediately, with no checks run — the widening must not become "run
    # checks on every git invocation".
    GATE_STATUS_RC=0
    GATE_STATUS_OUT=$(cd "$GATE_REPO" && printf '%s' '{"tool_input":{"command":"git status"}}' | "$ROOT/coordination-precommit-hook.sh" "$TMP/gate-coord-unused" "test-id" 2>&1) || GATE_STATUS_RC=$?
    assert_eq "hook-verb-coverage-status-not-gated-rc" "$GATE_STATUS_RC" "0"
    assert_not_contains "hook-verb-coverage-status-not-gated-msg" "$GATE_STATUS_OUT" "Checking coordination hygiene"
  else
    echo "SKIP [allowed_signers-gate] git not found."
  fi

  # (5) heartbeat.sh's own three append sites (append_heartbeat / append_hold_check /
  #     trip_watcher_down_alarm) — the follow-up gap fix. heartbeat.sh never routes
  #     through coord-send.sh (it appends directly on a timer), so this exercises its
  #     own signing wiring, not just coord-verify.sh's exemption logic.
  #
  # wait_for_grep polls instead of a fixed sleep — auto-provisioning a key
  # (ssh-keygen -Y sign's first invocation) is slow enough under load that a
  # fixed 2s window flaked; polling up to 5s is both faster on a fast machine
  # and more reliable on a loaded one.
  wait_for_grep() {
    local f="$1" needle="$2" max_iters="${3:-25}" i=0
    while [ "$i" -lt "$max_iters" ]; do
      if [ -f "$f" ] && grep -qF "$needle" "$f" 2>/dev/null; then
        return 0
      fi
      sleep 0.2
      i=$((i + 1))
    done
    return 1
  }

  HBD="$TMP/hb-coord"
  mkdir -p "$HBD/.watch-state/impl-hbrt"
  : > "$HBD/impl-hbrt.md"
  # A live, currently-running PID (this test's own background sleep) so
  # heartbeat.sh's watcher-alive check (kill -0) succeeds for the test's
  # duration — a stand-in for a real armed coord-monitor.sh.
  sleep 30 & FAKE_WATCHER_PID=$!
  echo "$FAKE_WATCHER_PID" > "$HBD/.watch-state/impl-hbrt/watcher.pid"

  # (a) HEARTBEAT/IDLE-KICK round-trips through --strict cleanly.
  "$ROOT/heartbeat.sh" --identity impl-hbrt --role implementer --dir "$HBD" \
    --idle-threshold 0 --cadence 1 --idle-policy "test policy" \
    > "$TMP/hb-a.out" 2>&1 &
  HB_A_PID=$!
  wait_for_grep "$TMP/hb-a.out" "signed." 25 || true
  kill "$HB_A_PID" 2>/dev/null || true
  wait "$HB_A_PID" 2>/dev/null || true

  # Key namespace is keyed off <coord-dir>/.coord-id contents (item 7,
  # 2026-08-09), not the absolute coord-dir path — see coord-keygen.sh's
  # compute_dirhash for why.
  COORD_ID_HBD=$(tr -d '[:space:]' < "$HBD/.coord-id")
  HASH_HBD=$(printf '%s' "$COORD_ID_HBD" | shasum -a 256 2>/dev/null | awk '{print $1}' | cut -c1-12)
  [ -z "$HASH_HBD" ] && HASH_HBD=$(printf '%s' "$COORD_ID_HBD" | sha256sum | awk '{print $1}' | cut -c1-12)
  HB_PUB="$HOME/.samantha/coord-keys/$HASH_HBD/impl-hbrt_ed25519.pub"
  assert_eq "hb-a-key-auto-provisioned" "$(test -f "$HB_PUB" && echo yes)" "yes"
  "$ROOT/coord-keygen.sh" --enroll --identity impl-hbrt --pubkey-line "$(cat "$HB_PUB")" --dir "$HBD" >/dev/null 2>&1

  assert_not_contains "hb-a-no-warn" "$(cat "$TMP/hb-a.out")" "WARN"
  HB_A_VERIFY=$("$ROOT/coord-verify.sh" --dir "$HBD" --file "$HBD/impl-hbrt.md" --strict 2>&1)
  assert_contains "hb-a-heartbeat-verified" "$HB_A_VERIFY" "✅ VERIFIED impl-hbrt"
  assert_contains "hb-a-heartbeat-strict-clean" "$HB_A_VERIFY" "0 unverified, 0 unknown-signer, 0 invalid"

  # (b) HOLD-CHECK likewise. Inject a HOLD marker heartbeat.sh's own
  #     detect_hold_marker() will find, then let two ticks pass (the first
  #     just starts the liveness clock; --hold-check-interval 0 makes the
  #     second post immediately).
  printf '\n### %s — orchestrator → impl-hbrt — 🛑 PACE-DOWN [HOLD:test-hold]\n\nHolding for test purposes.\n' "$(date -u +%FT%TZ)" >> "$HBD/impl-hbrt.md"
  BEFORE_B_LINES=$(wc -l < "$HBD/impl-hbrt.md" | tr -d ' ')
  "$ROOT/heartbeat.sh" --identity impl-hbrt --role implementer --dir "$HBD" \
    --idle-threshold 0 --cadence 1 --hold-check-interval 0 --idle-policy "test policy" \
    > "$TMP/hb-b.out" 2>&1 &
  HB_B_PID=$!
  wait_for_grep "$TMP/hb-b.out" "HOLD-CHECK posted" 30 || true
  kill "$HB_B_PID" 2>/dev/null || true
  wait "$HB_B_PID" 2>/dev/null || true

  assert_contains "hb-b-hold-check-posted" "$(cat "$TMP/hb-b.out")" "HOLD-CHECK posted"
  HB_B_VERIFY_RC=0
  HB_B_VERIFY=$("$ROOT/coord-verify.sh" --dir "$HBD" --file "$HBD/impl-hbrt.md" --strict --since-line "$BEFORE_B_LINES" 2>&1) || HB_B_VERIFY_RC=$?
  assert_contains "hb-b-hold-check-verified" "$HB_B_VERIFY" "✅ VERIFIED impl-hbrt"
  assert_eq "hb-b-hold-check-strict-clean-rc" "$HB_B_VERIFY_RC" "0"

  kill "$FAKE_WATCHER_PID" 2>/dev/null || true

  # (c) WATCHER-DOWN carrying a valid SIG block is fully verified like any
  #     other message — and a tampered one still comes back INVALID, never
  #     exempt. (Built via coord-send.sh, which shares heartbeat.sh's exact
  #     signing helpers, rather than driving heartbeat's real 3-tick dead-man
  #     trip — deterministic, and coord-verify.sh judges by message shape
  #     alone regardless of which script produced it.)
  BEFORE_C_LINES=$(wc -l < "$HBD/impl-hbrt.md" | tr -d ' ')
  "$ROOT/coord-send.sh" --identity impl-hbrt --dir "$HBD" --to orchestrator --tag "⚠️ WATCHER-DOWN [channel: local]" --body "Watcher PID 99999 is dead." >/dev/null 2>&1
  WD_SIGNED_VERIFY=$("$ROOT/coord-verify.sh" --dir "$HBD" --file "$HBD/impl-hbrt.md" --strict --since-line "$BEFORE_C_LINES" 2>&1)
  assert_contains "hb-c-watcher-down-signed-verified" "$WD_SIGNED_VERIFY" "✅ VERIFIED impl-hbrt"
  assert_contains "hb-c-watcher-down-signed-strict-clean" "$WD_SIGNED_VERIFY" "0 unverified, 0 unknown-signer, 0 invalid"

  sed -i.bak 's/Watcher PID 99999 is dead\./TAMPERED WATCHER DOWN BODY/' "$HBD/impl-hbrt.md"
  WD_TAMPER_VERIFY=$("$ROOT/coord-verify.sh" --dir "$HBD" --file "$HBD/impl-hbrt.md" --since-line "$BEFORE_C_LINES" 2>&1) || true
  assert_contains "hb-c-watcher-down-tamper-still-invalid" "$WD_TAMPER_VERIFY" "❌ INVALID"

  # (d) WATCHER-DOWN with NO SIG block (heartbeat.sh's best-effort-sign-else-
  #     flag fallback) passes --strict via the narrow exemption, while a
  #     non-WATCHER-DOWN unsigned message in the same position still fails —
  #     proving the exemption didn't leak broader than the one tag it names.
  # Exemption (c) requires FROM == basename(file) (2026-08-09 hardening) — a
  # legitimate fallback alert can only ever live in its own poster's outbox,
  # so these scratch fixtures must literally be named impl-hbrt.md.
  mkdir -p "$TMP/wd-fixture"
  UNSIGNED_WD="$TMP/wd-fixture/impl-hbrt.md"
  cat > "$UNSIGNED_WD" <<'EOF'
### 2026-08-09T21:00:00Z — impl-hbrt → orchestrator — ⚠️ WATCHER-DOWN [channel: local]

[SIGNING-FAILED — unauthenticated, verify liveness by other means]

Watcher PID 99999 (channel: local) is dead.
EOF
  UNSIGNED_WD_RC=0
  "$ROOT/coord-verify.sh" --dir "$HBD" --file "$UNSIGNED_WD" --strict >/dev/null 2>&1 || UNSIGNED_WD_RC=$?
  assert_eq "hb-d-unsigned-watcher-down-strict-passes" "$UNSIGNED_WD_RC" "0"

  # Same shape, wrong file — must NOT be exempt (closes "forge a WATCHER-DOWN
  # in someone else's mailbox").
  mkdir -p "$TMP/wd-wrongfile"
  UNSIGNED_WD_WRONGFILE="$TMP/wd-wrongfile/impl-someone-else.md"
  cp "$UNSIGNED_WD" "$UNSIGNED_WD_WRONGFILE"
  UNSIGNED_WD_WRONGFILE_RC=0
  "$ROOT/coord-verify.sh" --dir "$HBD" --file "$UNSIGNED_WD_WRONGFILE" --strict >/dev/null 2>&1 || UNSIGNED_WD_WRONGFILE_RC=$?
  assert_eq "hb-d-unsigned-watcher-down-wrong-file-strict-fails" "$UNSIGNED_WD_WRONGFILE_RC" "1"

  # Own subdirectory (still literally impl-hbrt.md, so file-binding matches)
  # — isolates "non-exempt TAG" as the sole reason this fails, not a
  # filename mismatch also contributing.
  mkdir -p "$TMP/nonwd-fixture"
  UNSIGNED_NON_WD="$TMP/nonwd-fixture/impl-hbrt.md"
  cat > "$UNSIGNED_NON_WD" <<'EOF'
### 2026-08-09T21:01:00Z — impl-hbrt → orchestrator — 📋 STATUS

Some unrelated unsigned status, same position, not a WATCHER-DOWN.
EOF
  UNSIGNED_NON_WD_RC=0
  "$ROOT/coord-verify.sh" --dir "$HBD" --file "$UNSIGNED_NON_WD" --strict >/dev/null 2>&1 || UNSIGNED_NON_WD_RC=$?
  assert_eq "hb-d-unsigned-non-watcher-down-strict-fails" "$UNSIGNED_NON_WD_RC" "1"

  # (f) HOLD-WAKE-UNACKED carrying a valid SIG block is fully verified like
  #     any other message, and a tampered one still comes back INVALID —
  #     mirrors (c), since HOLD-WAKE-UNACKED gets identical treatment to
  #     WATCHER-DOWN (2026-08-09 ratified: same dead-man-alarm shape).
  BEFORE_F_LINES=$(wc -l < "$HBD/impl-hbrt.md" | tr -d ' ')
  "$ROOT/coord-send.sh" --identity impl-hbrt --dir "$HBD" --to orchestrator --tag "⚠️ HOLD-WAKE-UNACKED [HOLD:test-hold · HOLD-CHECK:2026-08-09T21:02:00Z]" --body "HOLD-CHECK went unACKed." >/dev/null 2>&1
  HW_SIGNED_VERIFY=$("$ROOT/coord-verify.sh" --dir "$HBD" --file "$HBD/impl-hbrt.md" --strict --since-line "$BEFORE_F_LINES" 2>&1)
  assert_contains "hb-f-hold-wake-unacked-signed-verified" "$HW_SIGNED_VERIFY" "✅ VERIFIED impl-hbrt"
  assert_contains "hb-f-hold-wake-unacked-signed-strict-clean" "$HW_SIGNED_VERIFY" "0 unverified, 0 unknown-signer, 0 invalid"

  sed -i.bak 's/HOLD-CHECK went unACKed\./TAMPERED HOLD-WAKE BODY/' "$HBD/impl-hbrt.md"
  HW_TAMPER_VERIFY=$("$ROOT/coord-verify.sh" --dir "$HBD" --file "$HBD/impl-hbrt.md" --since-line "$BEFORE_F_LINES" 2>&1) || true
  assert_contains "hb-f-hold-wake-unacked-tamper-still-invalid" "$HW_TAMPER_VERIFY" "❌ INVALID"

  # (g) HOLD-WAKE-UNACKED with NO SIG block passes --strict via the narrow
  #     exemption, while a non-HOLD-WAKE-UNACKED unsigned message in the same
  #     position still fails — mirrors (d).
  mkdir -p "$TMP/hw-fixture"
  UNSIGNED_HW="$TMP/hw-fixture/impl-hbrt.md"
  cat > "$UNSIGNED_HW" <<'EOF'
### 2026-08-09T21:03:00Z — impl-hbrt → orchestrator — ⚠️ HOLD-WAKE-UNACKED [HOLD:test-hold · HOLD-CHECK:2026-08-09T21:02:00Z]

[SIGNING-FAILED — unauthenticated, verify liveness by other means]

HOLD-CHECK went unACKed.
EOF
  UNSIGNED_HW_RC=0
  "$ROOT/coord-verify.sh" --dir "$HBD" --file "$UNSIGNED_HW" --strict >/dev/null 2>&1 || UNSIGNED_HW_RC=$?
  assert_eq "hb-g-unsigned-hold-wake-unacked-strict-passes" "$UNSIGNED_HW_RC" "0"

  mkdir -p "$TMP/hw-wrongfile"
  UNSIGNED_HW_WRONGFILE="$TMP/hw-wrongfile/impl-someone-else.md"
  cp "$UNSIGNED_HW" "$UNSIGNED_HW_WRONGFILE"
  UNSIGNED_HW_WRONGFILE_RC=0
  "$ROOT/coord-verify.sh" --dir "$HBD" --file "$UNSIGNED_HW_WRONGFILE" --strict >/dev/null 2>&1 || UNSIGNED_HW_WRONGFILE_RC=$?
  assert_eq "hb-g-unsigned-hold-wake-unacked-wrong-file-strict-fails" "$UNSIGNED_HW_WRONGFILE_RC" "1"

  mkdir -p "$TMP/nonhw-fixture"
  UNSIGNED_NON_HW="$TMP/nonhw-fixture/impl-hbrt.md"
  cat > "$UNSIGNED_NON_HW" <<'EOF'
### 2026-08-09T21:04:00Z — impl-hbrt → orchestrator — 📋 STATUS

Some unrelated unsigned status, same position, not a HOLD-WAKE-UNACKED.
EOF
  UNSIGNED_NON_HW_RC=0
  "$ROOT/coord-verify.sh" --dir "$HBD" --file "$UNSIGNED_NON_HW" --strict >/dev/null 2>&1 || UNSIGNED_NON_HW_RC=$?
  assert_eq "hb-g-unsigned-non-hold-wake-unacked-strict-fails" "$UNSIGNED_NON_HW_RC" "1"

  # (e) the precommit hook does not block a commit after a routine heartbeat
  #     cycle — i.e. the (a)-style fix actually closes the gap end-to-end.
  HOOKD2="$TMP/hook-coord-hb"
  mkdir -p "$HOOKD2/.watch-state/impl-hooktest2" "$HOOKD2/.watch-state/orchestrator"
  : > "$HOOKD2/orchestrator.md"
  H2LINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$HOOKD2" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$H2LINE" --dir "$HOOKD2" >/dev/null
  write_receipt "$HOOKD2/.watch-state/impl-hooktest2/orchestrator.md.size" \
    "$(wc -c < "$HOOKD2/orchestrator.md" | tr -d ' ')" "$HOOKD2/orchestrator.md"

  sleep 30 & FAKE_WATCHER_PID2=$!
  echo "$FAKE_WATCHER_PID2" > "$HOOKD2/.watch-state/orchestrator/watcher.pid"

  "$ROOT/heartbeat.sh" --identity orchestrator --role orchestrator --dir "$HOOKD2" \
    --idle-threshold 0 --cadence 1 --idle-policy "test policy" \
    > "$TMP/hb-e.out" 2>&1 &
  HB_E_PID=$!
  wait_for_grep "$TMP/hb-e.out" "signed." 25 || true
  kill "$HB_E_PID" 2>/dev/null || true
  wait "$HB_E_PID" 2>/dev/null || true
  kill "$FAKE_WATCHER_PID2" 2>/dev/null || true

  HOOK_HB_RC=0
  HOOK_HB_OUT=$("$ROOT/coordination-precommit-hook.sh" "$HOOKD2" "impl-hooktest2" < /dev/null 2>&1) || HOOK_HB_RC=$?
  assert_eq "hb-e-hook-passes-after-routine-heartbeat" "$HOOK_HB_RC" "0"
  assert_contains "hb-e-hook-sig-verify-ran-clean" "$HOOK_HB_OUT" "OK [sig-verify]"

  # (6) PROTOCOL 1.4.0 remote-seat extension (2026-08-09): REMOTE-SEATS.md
  # previously documented remote-channel signature verification as an
  # explicit out-of-scope gap. No real ssh server is reachable in this test
  # environment (confirmed: `ssh -o BatchMode=yes localhost true` ->
  # "Connection refused", no sshd listening) — so remote_emit_new's actual
  # `ssh ...` calls are exercised via a FAKE `ssh` binary ahead of the real
  # one on PATH (same established technique as the OpenSSH-version-floor
  # tests above), translating "ssh <host> '<cmd>'" into a LOCAL `sh -c
  # '<cmd>'` — this is a genuinely different exercise than a pure unit test
  # of verify_remote_buffer alone: it proves the REAL wiring inside
  # coord-monitor.sh's remote channel (remote_sweep_sizes -> remote_emit_new
  # -> verify_remote_buffer -> coord-verify.sh) actually fires end to end,
  # not just that the helper function works in isolation.
  if command -v ssh >/dev/null 2>&1; then
    REMOTE_HUBD="$TMP/remote-hub-coord"
    mkdir -p "$REMOTE_HUBD"
    : > "$REMOTE_HUBD/orchestrator.md"
    RHUB_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$REMOTE_HUBD" 2>/dev/null)
    "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$RHUB_OLINE" --dir "$REMOTE_HUBD" >/dev/null

    # The "remote bus dir" is just an ordinary local directory in this test
    # (the fake ssh below executes against it directly) — but the SIGNING
    # side is exercised for real: a genuine coord-send.sh invocation with
    # --dir pointed at this directory, exactly as a real remote seat would
    # run it against its OWN local filesystem on the far side of the ssh hop.
    REMOTE_BUS_D="$TMP/remote-bus-dir"
    mkdir -p "$REMOTE_BUS_D"
    : > "$REMOTE_BUS_D/impl-remote1.md"
    RSEAT_LINE=$("$ROOT/coord-keygen.sh" --generate --identity impl-remote1 --dir "$REMOTE_BUS_D" 2>/dev/null)
    # Single canonical trust root (design decision, see REMOTE-SEATS.md):
    # enrolled into the HUB's OWN local allowed_signers, not a remote one.
    "$ROOT/coord-keygen.sh" --enroll --identity impl-remote1 --pubkey-line "$RSEAT_LINE" --dir "$REMOTE_HUBD" >/dev/null

    # --remote-seat must be EXPLICIT (MANDATORY-EXPLICIT, same posture as
    # --weak-seat): without it, coord-send.sh's own item-8 enrollment
    # readback-verify still FAILS LOUD against this bus dir's (nonexistent)
    # local allowed_signers — proves the fix didn't quietly defeat the
    # existing unenrolled-identity check (coord-send-catches-unenrolled-
    # identity below) for the ordinary local case by inferring from
    # file-absence alone. WITH the flag, the exact same missing-local-
    # allowed_signers condition is expected and non-fatal.
    RS_NOFLAG_RC=0
    RS_NOFLAG_OUT=$("$ROOT/coord-send.sh" --identity impl-remote1 --dir "$REMOTE_BUS_D" --to orchestrator --tag STATUS --body "no flag, should warn+fail" 2>&1) || RS_NOFLAG_RC=$?
    assert_eq "coord-send-remote-seat-required-explicitly-rc" "$RS_NOFLAG_RC" "1"
    assert_contains "coord-send-remote-seat-required-explicitly-msg" "$RS_NOFLAG_OUT" "enrollment readback-verify FAILED"

    RS_FLAG_RC=0
    RS_FLAG_OUT=$("$ROOT/coord-send.sh" --identity impl-remote1 --dir "$REMOTE_BUS_D" --remote-seat --to orchestrator --tag STATUS --body "with flag, should pass" 2>&1) || RS_FLAG_RC=$?
    assert_eq "coord-send-remote-seat-flag-passes-rc" "$RS_FLAG_RC" "0"
    assert_contains "coord-send-remote-seat-flag-passes-msg" "$RS_FLAG_OUT" "skipping the local enrollment readback-verify"

    "$ROOT/coord-send.sh" --identity impl-remote1 --dir "$REMOTE_BUS_D" --remote-seat --to orchestrator --tag STATUS --body "remote hello from the bus" >/dev/null 2>&1

    RFAKEBIN="$TMP/remote-fakebin"
    mkdir -p "$RFAKEBIN"
    cat > "$RFAKEBIN/ssh" <<'EOF'
#!/bin/sh
# Fake ssh for tests: strip "-o key=val" pairs and a bare "-n", take the next
# arg as the (ignored) host, and run the FINAL arg as a local shell command —
# this is the same shape remote_sweep_script/remote_emit_new invoke a real
# ssh with ("ssh -n -o ... -o ... <host> '<single-command-string>'"), so this
# exercises the real coord-monitor.sh remote-channel code path without a
# real ssh hop. -n (round-5, 2026-08-09) must be stripped as a BARE flag,
# not an "-o key=val" pair, or it gets mistaken for the host argument.
while :; do
  case "$1" in
    -o) shift 2 ;;
    -n) shift ;;
    *) break ;;
  esac
done
shift  # drop the host arg
sh -c "$1"
EOF
    chmod +x "$RFAKEBIN/ssh"

    REMOTE_MON_OUT="$TMP/remote-monitor.out"
    : > "$REMOTE_MON_OUT"
    PATH="$RFAKEBIN:$PATH" "$ROOT/coord-monitor.sh" --identity orchestrator --dir "$REMOTE_HUBD" \
      --remote-host fake-remote-host --remote-bus-dir "$REMOTE_BUS_D" --poll 1 \
      > "$REMOTE_MON_OUT" 2>&1 &
    REMOTE_MON_PID=$!
    wait_for_grep "$REMOTE_MON_OUT" "ARMED for orchestrator (REMOTE channel" 25 || true

    # Post AFTER arm (arm baselines at current EOF — see coord-monitor.sh's own
    # "never replays history" comment) so this is a genuinely NEW message the
    # remote channel must detect, fetch, and verify on its next poll sweep.
    "$ROOT/coord-send.sh" --identity impl-remote1 --dir "$REMOTE_BUS_D" --remote-seat --to orchestrator --tag STATUS --body "second remote message, post-arm" >/dev/null 2>&1
    wait_for_grep "$REMOTE_MON_OUT" "COORD SIG" 25 || true

    kill "$REMOTE_MON_PID" 2>/dev/null || true
    wait "$REMOTE_MON_PID" 2>/dev/null || true

    REMOTE_MON_TEXT=$(cat "$REMOTE_MON_OUT" 2>/dev/null || true)
    assert_contains "remote-channel-verifies-fetched-message" "$REMOTE_MON_TEXT" "┃ COORD SIG ✅ VERIFIED impl-remote1"
    assert_contains "remote-channel-annotation-after-message-text" "$REMOTE_MON_TEXT" "second remote message, post-arm"

    # Direct unit coverage of the shared helper itself (isolated from the
    # coord-monitor.sh wiring above) — INVALID-on-tamper and the structural
    # FROM==basename(file) mismatch, both via the exact stdin-buffer contract
    # coordination-precommit-hook.sh (gap 2) will also call it through.
    . "$ROOT/coord-remote-verify.sh"
    RV_TAMPERED=$(sed 's/remote hello from the bus/TAMPERED PAYLOAD/' "$REMOTE_BUS_D/impl-remote1.md")
    RV_TAMPER_OUT=$(printf '%s' "$RV_TAMPERED" | verify_remote_buffer "$REMOTE_HUBD" "impl-remote1.md" "$ROOT/coord-verify.sh" 2>&1) || true
    assert_contains "remote-verify-buffer-detects-tamper" "$RV_TAMPER_OUT" "❌ INVALID"

    RV_WRONGNAME_OUT=$(verify_remote_buffer "$REMOTE_HUBD" "impl-wrongname.md" "$ROOT/coord-verify.sh" --strict < "$REMOTE_BUS_D/impl-remote1.md" 2>&1) || true
    assert_contains "remote-verify-buffer-structural-mismatch-invalid" "$RV_WRONGNAME_OUT" "FROM/file mismatch"

    # (7) real gap 2, PROTOCOL 1.4.0 remote-seat extension: coordination-
    # precommit-hook.sh's check 1c reads .remote-channels and ssh-verifies
    # each configured remote seat's outbox IN FULL before allowing a hub
    # commit. Fresh, dedicated fixture (separate from REMOTE_HUBD/REMOTE_BUS_D
    # above, which by this point carry several unrelated test messages) —
    # .remote-channels is hand-written here rather than via a live
    # coord-monitor.sh arm, to isolate "does the HOOK correctly consume this
    # config" from "does coord-monitor.sh correctly WRITE it" (already
    # covered separately below, test (8)).
    RCHOOK_HUBD="$TMP/rchook-hub-coord"
    mkdir -p "$RCHOOK_HUBD"
    : > "$RCHOOK_HUBD/orchestrator.md"
    RCHOOK_HLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$RCHOOK_HUBD" 2>/dev/null)
    "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$RCHOOK_HLINE" --dir "$RCHOOK_HUBD" >/dev/null

    RCHOOK_BUSD="$TMP/rchook-remote-bus"
    mkdir -p "$RCHOOK_BUSD"
    : > "$RCHOOK_BUSD/impl-rchook.md"
    RCHOOK_RLINE=$("$ROOT/coord-keygen.sh" --generate --identity impl-rchook --dir "$RCHOOK_BUSD" 2>/dev/null)
    "$ROOT/coord-keygen.sh" --enroll --identity impl-rchook --pubkey-line "$RCHOOK_RLINE" --dir "$RCHOOK_HUBD" >/dev/null
    "$ROOT/coord-send.sh" --identity impl-rchook --dir "$RCHOOK_BUSD" --remote-seat --to orchestrator --tag STATUS --body "remote hook test message" >/dev/null 2>&1

    printf 'fake-remote-host %s\n' "$RCHOOK_BUSD" > "$RCHOOK_HUBD/.remote-channels"

    RCHOOK_FAKEBIN="$TMP/rchook-fakebin"
    mkdir -p "$RCHOOK_FAKEBIN"
    cat > "$RCHOOK_FAKEBIN/ssh" <<'EOF'
#!/bin/sh
# See RFAKEBIN/ssh above for why -n must be stripped as a bare flag.
while :; do
  case "$1" in
    -o) shift 2 ;;
    -n) shift ;;
    *) break ;;
  esac
done
shift
sh -c "$1"
EOF
    chmod +x "$RCHOOK_FAKEBIN/ssh"

    RCHOOK_CLEAN_RC=0
    RCHOOK_CLEAN_OUT=$(PATH="$RCHOOK_FAKEBIN:$PATH" "$ROOT/coordination-precommit-hook.sh" "$RCHOOK_HUBD" "test-id" < /dev/null 2>&1) || RCHOOK_CLEAN_RC=$?
    assert_eq "hook-remote-channel-clean-passes" "$RCHOOK_CLEAN_RC" "0"
    assert_contains "hook-remote-channel-clean-shows-ok" "$RCHOOK_CLEAN_OUT" "OK [remote-sig-verify]"

    cp "$RCHOOK_BUSD/impl-rchook.md" "$RCHOOK_BUSD/impl-rchook.md.clean-bak"
    sed -i.bak 's/remote hook test message/TAMPERED/' "$RCHOOK_BUSD/impl-rchook.md"
    RCHOOK_TAMPER_RC=0
    RCHOOK_TAMPER_OUT=$(PATH="$RCHOOK_FAKEBIN:$PATH" "$ROOT/coordination-precommit-hook.sh" "$RCHOOK_HUBD" "test-id" < /dev/null 2>&1) || RCHOOK_TAMPER_RC=$?
    assert_eq "hook-remote-channel-tamper-blocks" "$RCHOOK_TAMPER_RC" "2"
    assert_contains "hook-remote-channel-tamper-shows-fail" "$RCHOOK_TAMPER_OUT" "FAIL [remote-sig-verify]"
    cp "$RCHOOK_BUSD/impl-rchook.md.clean-bak" "$RCHOOK_BUSD/impl-rchook.md"

    RCHOOK_UNREACH_FAKEBIN="$TMP/rchook-unreach-fakebin"
    mkdir -p "$RCHOOK_UNREACH_FAKEBIN"
    cat > "$RCHOOK_UNREACH_FAKEBIN/ssh" <<'EOF'
#!/bin/sh
exit 255
EOF
    chmod +x "$RCHOOK_UNREACH_FAKEBIN/ssh"
    RCHOOK_UNREACH_RC=0
    RCHOOK_UNREACH_OUT=$(PATH="$RCHOOK_UNREACH_FAKEBIN:$PATH" "$ROOT/coordination-precommit-hook.sh" "$RCHOOK_HUBD" "test-id" < /dev/null 2>&1) || RCHOOK_UNREACH_RC=$?
    assert_eq "hook-remote-channel-unreachable-fails-closed-rc" "$RCHOOK_UNREACH_RC" "2"
    assert_contains "hook-remote-channel-unreachable-fails-closed-msg" "$RCHOOK_UNREACH_OUT" "could not reach remote channel fake-remote-host to verify — treating as UNVERIFIED, not skipping"

    # (8) .remote-channels AUTO-WRITE: coord-monitor.sh's remote channel must
    # register itself without a manual step. Reuses REMOTE_HUBD/REMOTE_BUS_D's
    # already-armed background monitor from test (6) above rather than
    # spinning up a third one.
    assert_contains "remote-channel-auto-writes-dot-remote-channels" \
      "$(cat "$REMOTE_HUBD/.remote-channels" 2>/dev/null || true)" \
      "fake-remote-host $REMOTE_BUS_D"

    # (9) ROUND-5 CRITICAL (2026-08-09, Cipher — live-demonstrated RCE): a
    # file named with embedded shell metacharacters in the REMOTE bus dir
    # must NEVER execute code when coordination-precommit-hook.sh's check 1c
    # lists/fetches it. RCHOOK_FAKEBIN's fake ssh actually EXECUTES whatever
    # command string this hook constructs (via `sh -c`) — if the injection
    # were still live, the marker file below would be created for real, not
    # hypothetically. This is Cipher's exact exploit shape reproduced as a
    # permanent regression test.
    RCHOOK_PWN_MARKER="$TMP/rchook-pwn-marker"
    rm -f "$RCHOOK_PWN_MARKER"
    export RCHOOK_PWN_MARKER
    # NOTE: the marker path is referenced via "$RCHOOK_PWN_MARKER" (a shell
    # variable expansion), NOT inlined as a literal absolute path — a literal
    # "/" cannot appear inside a single filename component (the OS always
    # treats it as a path separator, quoting or not), so a malicious filename
    # embedding one would just fail to even get CREATED on disk, proving
    # nothing about command injection. Referencing the marker via env var
    # keeps this a pure filename (no "/") while still resolving to a real
    # absolute path ONLY if the injected shell fragment actually executes.
    RCHOOK_MAL_NAME='x'"'"'; touch "$RCHOOK_PWN_MARKER"; echo '"'"'.md'
    printf '### %s — impl-rchook -> orchestrator -- STATUS [malicious-filename regression, deliberately unsigned]\nthe point of this file is that it must never be EXECUTED, verified or not\n' \
      "$(date -u +%FT%TZ)" > "$RCHOOK_BUSD/$RCHOOK_MAL_NAME"
    RCHOOK_PWN_RC=0
    RCHOOK_PWN_OUT=$(PATH="$RCHOOK_FAKEBIN:$PATH" "$ROOT/coordination-precommit-hook.sh" "$RCHOOK_HUBD" "test-id" < /dev/null 2>&1) || RCHOOK_PWN_RC=$?
    assert_eq "hook-remote-channel-malicious-filename-no-rce" "$([ -e "$RCHOOK_PWN_MARKER" ] && echo EXISTS || echo ABSENT)" "ABSENT"
    # The hook must still FAIL this commit (an unsigned/unverifiable message
    # is correctly rejected) — proving the fix isn't "silently drop the file",
    # it's "handle it safely and still verify/reject it on its merits".
    assert_eq "hook-remote-channel-malicious-filename-still-blocks-rc" "$RCHOOK_PWN_RC" "2"
    rm -f "$RCHOOK_BUSD/$RCHOOK_MAL_NAME"

    # (10) ROUND-5 CRITICAL: same malicious-filename repro through
    # coord-monitor.sh's remote channel (remote_emit_new) — a SEPARATE code
    # path with the identical bug. Fresh, short-lived monitor instance
    # (REMOTE_MON_PID from test 6 was already killed above).
    MON_PWN_MARKER="$TMP/monitor-pwn-marker"
    rm -f "$MON_PWN_MARKER"
    export MON_PWN_MARKER
    # See RCHOOK_MAL_NAME above for why the marker is referenced via env var,
    # not inlined as a literal path containing "/". NO SPACES here (unlike
    # RCHOOK_MAL_NAME): coord-monitor.sh's remote sweep packs "MSG <name>
    # <size>" onto ONE space-delimited line (a separate, pre-existing wire-
    # format limitation of that protocol, not a round-5 finding) — a name
    # containing a space breaks that parse regardless of quoting and would
    # falsely conflate "sweep-protocol robustness" with "injection safety" in
    # this specific test. Metacharacters alone (no spaces needed) are still
    # sufficient to prove command injection is blocked.
    MON_MAL_NAME='x'"'"';>$MON_PWN_MARKER;echo'"'"'.md'
    printf 'line one\n' > "$REMOTE_BUS_D/$MON_MAL_NAME"
    MON_PWN_OUT="$TMP/monitor-pwn.out"
    : > "$MON_PWN_OUT"
    PATH="$RFAKEBIN:$PATH" "$ROOT/coord-monitor.sh" --identity orchestrator --dir "$REMOTE_HUBD" \
      --remote-host fake-remote-host --remote-bus-dir "$REMOTE_BUS_D" --poll 1 \
      > "$MON_PWN_OUT" 2>&1 &
    MON_PWN_PID=$!
    wait_for_grep "$MON_PWN_OUT" "ARMED for orchestrator (REMOTE channel" 25 || true
    # Grow it AFTER arm so remote_emit_new's fetch path (the vulnerable line)
    # actually fires — arm only baselines existing size, never fetches.
    printf 'line two — appended after arm, must trigger a fetch\n' >> "$REMOTE_BUS_D/$MON_MAL_NAME"
    wait_for_grep "$MON_PWN_OUT" "(remote) ·" 25 || true
    kill "$MON_PWN_PID" 2>/dev/null || true
    wait "$MON_PWN_PID" 2>/dev/null || true
    assert_eq "remote-channel-malicious-filename-no-rce" "$([ -e "$MON_PWN_MARKER" ] && echo EXISTS || echo ABSENT)" "ABSENT"
    assert_contains "remote-channel-malicious-filename-fetch-attempted" "$(cat "$MON_PWN_OUT" 2>/dev/null || true)" "(remote) ·"
    rm -f "$REMOTE_BUS_D/$MON_MAL_NAME"

    # (10b) ROUND-6 CRITICAL (2026-08-09, Cipher — live-demonstrated, distinct
    # from the round-5 command-injection RCE above): coord-monitor.sh's
    # remote_sweep_script emits one "MSG <name> <size>" record per line — a
    # remote-listed filename containing an EMBEDDED NEWLINE lets an attacker
    # inject a FABRICATED extra record into that wire stream. A single crafted
    # filename (itself ending in ".md", so the remote `for f in *.md` glob
    # still picks it up) whose bytes are "zzz-evil.md\nMSG impl-victim1.md
    # 999999999\nzzz-tail.md" prints as THREE lines — the middle one reads
    # exactly like a genuine record for a DIFFERENT real peer (impl-victim1)
    # with a huge fake size. Landed before that peer's real growth, it poisons
    # remote_emit_new's offset baseline for impl-victim1.md so the peer's
    # real, much-smaller, validly signed message then hits the "rewritten/
    # archived, baseline reset" branch and is silently discarded — never
    # fetched, never verified, no error. This is Cipher's exact scenario:
    # proves the fix (remote_sweep_script now refuses to even LIST any name
    # containing an embedded newline/CR) by showing the real victim message
    # DOES arrive after the poison attempt, and that the poison payload
    # ("999999999") never appears anywhere in the monitor's output at all —
    # not delivered-and-ignored, never emitted onto the wire in the first
    # place. Fresh, dedicated fixture (a genuinely different peer identity
    # than any used above) so this isn't riding on state test (10) left behind.
    NLINJ_HUBD="$TMP/nlinj-hub-coord"
    mkdir -p "$NLINJ_HUBD"
    : > "$NLINJ_HUBD/orchestrator.md"
    NLINJ_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$NLINJ_HUBD" 2>/dev/null)
    "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$NLINJ_OLINE" --dir "$NLINJ_HUBD" >/dev/null

    NLINJ_BUSD="$TMP/nlinj-remote-bus"
    mkdir -p "$NLINJ_BUSD"
    : > "$NLINJ_BUSD/impl-victim1.md"
    NLINJ_VLINE=$("$ROOT/coord-keygen.sh" --generate --identity impl-victim1 --dir "$NLINJ_BUSD" 2>/dev/null)
    "$ROOT/coord-keygen.sh" --enroll --identity impl-victim1 --pubkey-line "$NLINJ_VLINE" --dir "$NLINJ_HUBD" >/dev/null

    NLINJ_MON_OUT="$TMP/nlinj-monitor.out"
    : > "$NLINJ_MON_OUT"
    PATH="$RFAKEBIN:$PATH" "$ROOT/coord-monitor.sh" --identity orchestrator --dir "$NLINJ_HUBD" \
      --remote-host fake-remote-host --remote-bus-dir "$NLINJ_BUSD" --poll 1 \
      > "$NLINJ_MON_OUT" 2>&1 &
    NLINJ_MON_PID=$!
    wait_for_grep "$NLINJ_MON_OUT" "ARMED for orchestrator (REMOTE channel" 25 || true

    # Plant the poison BEFORE the real message is posted — the live exploit
    # depends on this ordering (poison the baseline first, then the real
    # growth is what gets silently discarded second).
    NLINJ_POISON_NAME=$(printf 'zzz-evil.md\nMSG impl-victim1.md 999999999\nzzz-tail.md')
    printf 'irrelevant payload, must never be parsed as a real record\n' > "$NLINJ_BUSD/$NLINJ_POISON_NAME"
    sleep 3

    "$ROOT/coord-send.sh" --identity impl-victim1 --dir "$NLINJ_BUSD" --remote-seat --to orchestrator --tag STATUS --body "real victim1 message must not be silently discarded" >/dev/null 2>&1
    wait_for_grep "$NLINJ_MON_OUT" "real victim1 message" 25 || true

    kill "$NLINJ_MON_PID" 2>/dev/null || true
    wait "$NLINJ_MON_PID" 2>/dev/null || true
    rm -f "$NLINJ_BUSD/$NLINJ_POISON_NAME"

    NLINJ_MON_TEXT=$(cat "$NLINJ_MON_OUT" 2>/dev/null || true)
    assert_contains "remote-channel-newline-injection-real-message-not-discarded" "$NLINJ_MON_TEXT" "real victim1 message must not be silently discarded"
    assert_not_contains "remote-channel-newline-injection-no-poison-record-emitted" "$NLINJ_MON_TEXT" "999999999"

    # (11) ROUND-5 BLOCKER (Rook): a remote QUEUE.md (an ORDINARY
    # infrastructure file, not a per-seat outbox — not a crafted attack) must
    # never trigger the structural FROM==basename(file) check, which
    # legitimately expects QUEUE.md's own entries to carry a DIFFERENT
    # identity's FROM than "QUEUE". Direct unit coverage of the shared
    # predicate first (proves the fix in isolation), then an end-to-end check
    # that the hook actually calls it (proves the fix is wired in, not just
    # correct on paper).
    assert_eq "seat-outbox-predicate-excludes-queue" "$(coord_is_seat_outbox_basename QUEUE.md && echo yes || echo no)" "no"
    assert_eq "seat-outbox-predicate-excludes-projects" "$(coord_is_seat_outbox_basename PROJECTS.md && echo yes || echo no)" "no"
    assert_eq "seat-outbox-predicate-excludes-queue-lane" "$(coord_is_seat_outbox_basename queue-alpha.md && echo yes || echo no)" "no"
    assert_eq "seat-outbox-predicate-excludes-archive" "$(coord_is_seat_outbox_basename impl-remote1.archive.md && echo yes || echo no)" "no"
    assert_eq "seat-outbox-predicate-includes-normal-seat" "$(coord_is_seat_outbox_basename impl-remote1.md && echo yes || echo no)" "yes"

    printf '### %s — impl-rchook -> orchestrator -- QUEUE-STATUS [unsigned queue entry, FROM deliberately != QUEUE]\nsome queue content\n' "$(date -u +%FT%TZ)" > "$RCHOOK_BUSD/QUEUE.md"
    RCHOOK_QUEUE_RC=0
    RCHOOK_QUEUE_OUT=$(PATH="$RCHOOK_FAKEBIN:$PATH" "$ROOT/coordination-precommit-hook.sh" "$RCHOOK_HUBD" "test-id" < /dev/null 2>&1) || RCHOOK_QUEUE_RC=$?
    assert_eq "hook-remote-channel-excludes-queue-md-rc" "$RCHOOK_QUEUE_RC" "0"
    assert_not_contains "hook-remote-channel-excludes-queue-md-no-fail" "$RCHOOK_QUEUE_OUT" "QUEUE.md contains an INVALID"
    rm -f "$RCHOOK_BUSD/QUEUE.md"

    # (11b) ROUND-7 (2026-08-09, Rook): test (11) above only ever exercised
    # check 1c (REMOTE channel, spoke identity "test-id") — it never touched
    # check 1b's ORCHESTRATOR-side INBOX_FILES enumeration, which is what
    # round-6 item 2 actually fixed (coordination-precommit-hook.sh:356's
    # coord_is_seat_outbox_basename call). Dedicated LOCAL fixture: run the
    # hook AS orchestrator against a coord-dir containing a populated
    # queue-alpha.md AND PROJECTS.md, each with a FROM that deliberately
    # differs from the file's own basename (queue/roster files always carry
    # a different author's FROM — exactly the shape that used to trip the
    # structural FROM==basename(file) check before round-6's fix) — proves
    # both are excluded from INBOX_FILES entirely (never even handed to
    # coord-verify.sh), not merely tolerated by it. A real signed peer
    # message is included alongside them so this also proves the exclusion
    # doesn't degrade into "skip everything" — the real peer is still
    # verified normally.
    GAP1_D="$TMP/gap1-orch-inbox"
    mkdir -p "$GAP1_D"
    : > "$GAP1_D/orchestrator.md"
    GAP1_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$GAP1_D" 2>/dev/null)
    "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$GAP1_OLINE" --dir "$GAP1_D" >/dev/null
    GAP1_NLINE=$("$ROOT/coord-keygen.sh" --generate --identity impl-normal --dir "$GAP1_D" 2>/dev/null)
    "$ROOT/coord-keygen.sh" --enroll --identity impl-normal --pubkey-line "$GAP1_NLINE" --dir "$GAP1_D" >/dev/null
    : > "$GAP1_D/impl-normal.md"
    "$ROOT/coord-send.sh" --identity impl-normal --dir "$GAP1_D" --to orchestrator --tag STATUS --body "legit peer message, must still verify normally" >/dev/null 2>&1

    printf '### %s — impl-someone -> orchestrator -- QUEUE-STATUS [gap-1 regression fixture, deliberately unsigned, FROM != basename(file)]\nqueue content\n' \
      "$(date -u +%FT%TZ)" > "$GAP1_D/queue-alpha.md"
    printf '### %s — impl-other -> ALL -- STATUS [gap-1 regression fixture, deliberately unsigned, FROM != basename(file)]\nprojects roster content\n' \
      "$(date -u +%FT%TZ)" > "$GAP1_D/PROJECTS.md"

    GAP1_RC=0
    GAP1_OUT=$("$ROOT/coordination-precommit-hook.sh" "$GAP1_D" "orchestrator" < /dev/null 2>&1) || GAP1_RC=$?
    assert_eq "hook-orchestrator-inbox-excludes-queue-and-projects-rc" "$GAP1_RC" "0"
    assert_not_contains "hook-orchestrator-inbox-excludes-queue-md-no-fail" "$GAP1_OUT" "FAIL [sig-verify]: mail in $GAP1_D/queue-alpha.md"
    assert_not_contains "hook-orchestrator-inbox-excludes-projects-md-no-fail" "$GAP1_OUT" "FAIL [sig-verify]: mail in $GAP1_D/PROJECTS.md"
    assert_contains "hook-orchestrator-inbox-still-verifies-normal-peer" "$GAP1_OUT" "OK [sig-verify]: $GAP1_D/impl-normal.md since the last commit"

    # (11c)/(11d) ROUND-7 (2026-08-09, Rook): no test exercised item 3b's
    # fail-closed `else` branch at all (helpers genuinely missing). Build a
    # DEDICATED copy of the hook + its siblings, minus coord-address-
    # filter.sh — the missing-helper condition can only be forced by
    # controlling _HOOK_HOME's own directory contents (it's derived from
    # BASH_SOURCE, not overridable by env/argv).
    GAP2_HOOKDIR="$TMP/gap2-hookcopy-no-address-filter"
    mkdir -p "$GAP2_HOOKDIR"
    cp "$ROOT/coordination-precommit-hook.sh" "$ROOT/coord-verify.sh" "$ROOT/coord-remote-verify.sh" "$ROOT/coord-receipt.sh" "$GAP2_HOOKDIR/"
    # coord-address-filter.sh intentionally NOT copied — this is the missing helper.

    # (11c) missing helper + .remote-channels POPULATED — must fail closed
    # (item 3b: coord_is_seat_outbox_basename never resolves, so the check-1c
    # guard's `command -v coord_is_seat_outbox_basename` fails and this must
    # land in the else branch's FAIL=1, not the old INFO-only no-op).
    GAP2B_D="$TMP/gap2-hub-populated-channel"
    mkdir -p "$GAP2B_D"
    : > "$GAP2B_D/orchestrator.md"
    GAP2B_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$GAP2B_D" 2>/dev/null)
    "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$GAP2B_OLINE" --dir "$GAP2B_D" >/dev/null
    printf 'fake-remote-host %s\n' "$TMP/gap2-nonexistent-bus" > "$GAP2B_D/.remote-channels"
    GAP2B_RC=0
    GAP2B_OUT=$("$GAP2_HOOKDIR/coordination-precommit-hook.sh" "$GAP2B_D" "orchestrator" < /dev/null 2>&1) || GAP2B_RC=$?
    assert_eq "hook-missing-helper-with-remote-channels-fails-closed-rc" "$GAP2B_RC" "2"
    assert_contains "hook-missing-helper-with-remote-channels-fails-closed-msg" "$GAP2B_OUT" "FAIL [remote-sig-verify]: coord-remote-verify.sh/coord-verify.sh/coord-address-filter.sh not found"

    # (11d) SAME missing helper, but .remote-channels absent/empty — nothing
    # is configured to verify, so this must stay a clean pass (proves the
    # fail-closed fix in (11c) didn't regress the "genuinely nothing to
    # check" case into a false block).
    GAP2C_D="$TMP/gap2-hub-no-channel"
    mkdir -p "$GAP2C_D"
    : > "$GAP2C_D/orchestrator.md"
    GAP2C_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$GAP2C_D" 2>/dev/null)
    "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$GAP2C_OLINE" --dir "$GAP2C_D" >/dev/null
    GAP2C_RC=0
    GAP2C_OUT=$("$GAP2_HOOKDIR/coordination-precommit-hook.sh" "$GAP2C_D" "orchestrator" < /dev/null 2>&1) || GAP2C_RC=$?
    assert_eq "hook-missing-helper-without-remote-channels-still-passes-rc" "$GAP2C_RC" "0"
    assert_not_contains "hook-missing-helper-without-remote-channels-no-fail" "$GAP2C_OUT" "FAIL [remote-sig-verify]"

    # (12) ROUND-5 (Rook, item 4): a remote filename containing a SPACE must
    # survive as ONE entry, not word-split into multiple local loop
    # iterations (and, unquoted, be subject to local pathname expansion) —
    # proves the `while IFS= read -r` fix independent of the injection angle
    # covered by tests (9)/(10) above.
    RCHOOK_SPACE_NAME="impl remote two words.md"
    printf 'irrelevant\n' > "$RCHOOK_BUSD/$RCHOOK_SPACE_NAME"
    RCHOOK_SPACE_OUT=$(PATH="$RCHOOK_FAKEBIN:$PATH" "$ROOT/coordination-precommit-hook.sh" "$RCHOOK_HUBD" "test-id" < /dev/null 2>&1) || true
    assert_contains "hook-remote-channel-space-in-filename-handled-whole" "$RCHOOK_SPACE_OUT" "fake-remote-host:$RCHOOK_BUSD/$RCHOOK_SPACE_NAME"
    rm -f "$RCHOOK_BUSD/$RCHOOK_SPACE_NAME"

    # (13) ROUND-5 BLOCKER (Cipher+Rook): check 1c must ALWAYS state exactly
    # which channel(s) were checked, even zero — a missing/empty/redirected
    # .remote-channels used to produce ZERO output, indistinguishable from
    # "no remote channel exists".
    ZEROCH_D="$TMP/zero-channel-coord"
    mkdir -p "$ZEROCH_D"
    : > "$ZEROCH_D/orchestrator.md"
    ZEROCH_LINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$ZEROCH_D" 2>/dev/null)
    "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$ZEROCH_LINE" --dir "$ZEROCH_D" >/dev/null
    ZEROCH_RC=0
    ZEROCH_OUT=$("$ROOT/coordination-precommit-hook.sh" "$ZEROCH_D" "test-id" < /dev/null 2>&1) || ZEROCH_RC=$?
    assert_eq "hook-remote-channel-zero-configured-rc" "$ZEROCH_RC" "0"
    assert_contains "hook-remote-channel-zero-configured-shows-count" "$ZEROCH_OUT" "checked 0 remote channel(s)"

    # (14) ROUND-5 BLOCKER (Cipher+Rook): a LIVE watcher-remote.pid but
    # missing/empty .remote-channels must FAIL CLOSED, not silently pass —
    # Cipher's decoy-directory scenario reduces to this same shape (a channel
    # this host believes is armed is not actually being verified).
    #
    # Round-6 (2026-08-09, doc/test hygiene): the relative pidfile path below
    # used to be hand-typed (".watch-state/orchestrator/watcher-remote.pid"),
    # a guess at coord-monitor.sh's own internal WATCHER_PID_FILE naming
    # scheme that would silently stop testing anything real if that scheme
    # ever changed. Derived here instead from REMOTE_HUBD — a coord-dir a
    # REAL coord-monitor.sh --remote-host instance actually armed against
    # earlier in this suite (test 6) and genuinely wrote its own pidfile
    # into — so this test's fixture always matches whatever path the real
    # code actually uses, not a maintained-by-hand duplicate of it.
    ZEROCH_REAL_WPID_FILE=$(find "$REMOTE_HUBD/.watch-state" -name watcher-remote.pid 2>/dev/null | head -1)
    if [ -z "$ZEROCH_REAL_WPID_FILE" ]; then
      echo "ERROR: could not find a real watcher-remote.pid under $REMOTE_HUBD/.watch-state — test (14)'s fixture derivation depends on test (6) having armed a real remote monitor there." >&2
      exit 1
    fi
    ZEROCH_WPID_REL="${ZEROCH_REAL_WPID_FILE#"$REMOTE_HUBD"/}"
    ZEROCH_WPID_FILE="$ZEROCH_D/$ZEROCH_WPID_REL"
    mkdir -p "$(dirname "$ZEROCH_WPID_FILE")"
    sleep 60 &
    ZEROCH_FAKE_WATCHER_PID=$!
    printf '%s' "$ZEROCH_FAKE_WATCHER_PID" > "$ZEROCH_WPID_FILE"
    ZEROCH_LIVE_RC=0
    ZEROCH_LIVE_OUT=$("$ROOT/coordination-precommit-hook.sh" "$ZEROCH_D" "test-id" < /dev/null 2>&1) || ZEROCH_LIVE_RC=$?
    kill "$ZEROCH_FAKE_WATCHER_PID" 2>/dev/null || true
    wait "$ZEROCH_FAKE_WATCHER_PID" 2>/dev/null || true
    assert_eq "hook-remote-channel-live-watcher-empty-channels-fails-closed-rc" "$ZEROCH_LIVE_RC" "2"
    assert_contains "hook-remote-channel-live-watcher-empty-channels-fails-closed-msg" "$ZEROCH_LIVE_OUT" "a remote-channel watcher is running"

    # (15) ROUND-5 (item 5, Rook): a remote seat running this SAME hook
    # against its own bus-dir-as-coord-dir must not be permanently blocked by
    # check 1b's local sig-verify (no local allowed_signers there by design)
    # — COORD_REMOTE_SEAT_HOOK=1 is the explicit, documented escape. A real
    # signed message (not an empty file) is required so check 1b actually
    # has something to attempt verification on and fail — mirrors the shape
    # of a hub's orchestrator.md mirrored into a remote seat's own bus dir.
    : > "$RCHOOK_BUSD/orchestrator.md"
    "$ROOT/coord-send.sh" --identity orchestrator --dir "$RCHOOK_BUSD" --remote-seat --to impl-rchook --tag STATUS --body "mirrored hub message" >/dev/null 2>&1
    RSH_NOFLAG_RC=0
    RSH_NOFLAG_OUT=$("$ROOT/coordination-precommit-hook.sh" "$RCHOOK_BUSD" "impl-rchook" < /dev/null 2>&1) || RSH_NOFLAG_RC=$?
    assert_eq "hook-remote-seat-without-escape-blocks-rc" "$RSH_NOFLAG_RC" "2"
    RSH_FLAG_RC=0
    RSH_FLAG_OUT=$(COORD_REMOTE_SEAT_HOOK=1 "$ROOT/coordination-precommit-hook.sh" "$RCHOOK_BUSD" "impl-rchook" < /dev/null 2>&1) || RSH_FLAG_RC=$?
    assert_eq "hook-remote-seat-hook-escape-passes-rc" "$RSH_FLAG_RC" "0"
    assert_contains "hook-remote-seat-hook-escape-skips-local-sig-verify" "$RSH_FLAG_OUT" "COORD_REMOTE_SEAT_HOOK=1"
    rm -f "$RCHOOK_BUSD/orchestrator.md"
  else
    echo "SKIP [remote-seat sig] ssh not found."
  fi

  # ── PROTOCOL 1.5.0 §3.5: Protocol Version Handshake ─────────────────────────
  # These need ssh-keygen (real coord-send.sh signing) but NOT the `ssh` binary
  # — Part B's alert is a LOCAL-channel post, Part D's gate is a pure local
  # presence read. Deliberately outside the inner "ssh found" gate above.

  # (16) PROTOCOL 1.5.0 Part B: coord-monitor.sh's re-arm-time staleness
  # check. Fresh hub + one peer whose presence already claims an OLDER
  # version than this seat's own — proves the mismatch is detected on arm
  # and a signed, addressed alert lands in the detecting seat's OWN outbox
  # (STAR addressing — the peer's own monitor watches that file), not just
  # local stdout.
  PV_D="$TMP/pv-hub"
  mkdir -p "$PV_D"
  : > "$PV_D/orchestrator.md"
  : > "$PV_D/impl-alpha.md"
  PV_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$PV_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$PV_OLINE" --dir "$PV_D" >/dev/null
  PV_ALINE=$("$ROOT/coord-keygen.sh" --generate --identity impl-alpha --dir "$PV_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity impl-alpha --pubkey-line "$PV_ALINE" --dir "$PV_D" >/dev/null
  mkdir -p "$PV_D/.presence"
  printf 'identity=impl-alpha\nprotocol_version=1.3.0\n' > "$PV_D/.presence/impl-alpha"

  PV_MON_OUT="$TMP/pv-monitor.out"
  : > "$PV_MON_OUT"
  "$ROOT/coord-monitor.sh" --identity orchestrator --dir "$PV_D" --poll 1 > "$PV_MON_OUT" 2>&1 &
  PV_MON_PID=$!
  wait_for_grep "$PV_MON_OUT" "ARMED for orchestrator" 25 || true
  sleep 1
  kill "$PV_MON_PID" 2>/dev/null || true
  wait "$PV_MON_PID" 2>/dev/null || true

  PV_OUTBOX=$(cat "$PV_D/orchestrator.md" 2>/dev/null || true)
  assert_contains "protocol-version-mismatch-alert-posted-header" "$PV_OUTBOX" "orchestrator → impl-alpha — ⚠️ PROTOCOL-VERSION-MISMATCH"
  assert_contains "protocol-version-mismatch-alert-names-versions" "$PV_OUTBOX" "impl-alpha is running 1.3.0; orchestrator is running $PROTOCOL_VERSION"
  assert_contains "protocol-version-mismatch-alert-is-signed" "$PV_OUTBOX" "BEGIN SSH SIGNATURE"

  # (16b) Dedup: re-arming while the SAME mismatch persists must NOT re-post
  # — one state file per peer gates it, same shape as SEAT STALE's wasstale.
  PV_MON_OUT2="$TMP/pv-monitor2.out"
  : > "$PV_MON_OUT2"
  "$ROOT/coord-monitor.sh" --identity orchestrator --dir "$PV_D" --poll 1 > "$PV_MON_OUT2" 2>&1 &
  PV_MON_PID2=$!
  wait_for_grep "$PV_MON_OUT2" "ARMED for orchestrator" 25 || true
  sleep 1
  kill "$PV_MON_PID2" 2>/dev/null || true
  wait "$PV_MON_PID2" 2>/dev/null || true
  PV_ALERT_COUNT=$(grep -c "PROTOCOL-VERSION-MISMATCH" "$PV_D/orchestrator.md" 2>/dev/null || echo 0)
  assert_eq "protocol-version-mismatch-dedup-no-repeat-alert" "$PV_ALERT_COUNT" "1"

  # (16c) Resolve (peer catches up to this seat's version), re-arm — state
  # clears; THEN a genuinely NEW mismatch (peer moves past this seat) must
  # alert again, proving dedup doesn't permanently latch.
  printf 'identity=impl-alpha\nprotocol_version=%s\n' "$PROTOCOL_VERSION" > "$PV_D/.presence/impl-alpha"
  PV_MON_OUT3="$TMP/pv-monitor3.out"
  : > "$PV_MON_OUT3"
  "$ROOT/coord-monitor.sh" --identity orchestrator --dir "$PV_D" --poll 1 > "$PV_MON_OUT3" 2>&1 &
  PV_MON_PID3=$!
  wait_for_grep "$PV_MON_OUT3" "ARMED for orchestrator" 25 || true
  sleep 1
  kill "$PV_MON_PID3" 2>/dev/null || true
  wait "$PV_MON_PID3" 2>/dev/null || true
  PV_STATE_COUNT=$(find "$PV_D/.watch-state" -name "protocol-version.*" 2>/dev/null | wc -l | tr -d ' ')
  assert_eq "protocol-version-mismatch-clears-on-resolve" "$PV_STATE_COUNT" "0"

  printf 'identity=impl-alpha\nprotocol_version=9.9.9\n' > "$PV_D/.presence/impl-alpha"
  PV_MON_OUT4="$TMP/pv-monitor4.out"
  : > "$PV_MON_OUT4"
  "$ROOT/coord-monitor.sh" --identity orchestrator --dir "$PV_D" --poll 1 > "$PV_MON_OUT4" 2>&1 &
  PV_MON_PID4=$!
  wait_for_grep "$PV_MON_OUT4" "ARMED for orchestrator" 25 || true
  sleep 1
  kill "$PV_MON_PID4" 2>/dev/null || true
  wait "$PV_MON_PID4" 2>/dev/null || true
  PV_ALERT_COUNT2=$(grep -c "PROTOCOL-VERSION-MISMATCH" "$PV_D/orchestrator.md" 2>/dev/null || echo 0)
  assert_eq "protocol-version-mismatch-new-mismatch-alerts-again" "$PV_ALERT_COUNT2" "2"

  # (17) PROTOCOL 1.5.0 Part D: coordination-precommit-hook.sh's MAJOR
  # mismatch gate. ROUND-9 (2026-08-10, Cipher HIGH): rewritten from a
  # presence-sourced fixture to a REAL SIGNED HEARTBEAT fixture — check 1d no
  # longer reads .presence at all (see coordination-precommit-hook.sh's check
  # 1d header comment), so a presence-only fixture would no longer exercise
  # the real code path. pvd_arm_signed_heartbeat below stands up a real
  # heartbeat.sh run under an overridden PROTOCOL-VERSION so the resulting
  # HEARTBEAT append is genuinely signed+verifiable at a chosen version.
  pvd_arm_signed_heartbeat() {
    # <coord-dir> <identity> <protocol-version>
    local d="$1" ident="$2" ver="$3" home
    home="$TMP/pvd-hb-home-$ident-$ver"
    mkdir -p "$home"
    cp "$ROOT/heartbeat.sh" "$ROOT/coord-keygen.sh" "$ROOT/coord-presence.sh" "$home/"
    printf 'PROTOCOL_VERSION=%s\n' "$ver" > "$home/PROTOCOL-VERSION"
    mkdir -p "$d/.watch-state/$ident"
    ( sleep 30 & echo $! > "$d/.watch-state/$ident/watcher.pid" ) &
    wait
    local hb_out="$TMP/pvd-hb-$ident-$ver.out"
    "$home/heartbeat.sh" --identity "$ident" --role implementer --dir "$d" \
      --idle-threshold 0 --cadence 1 --idle-policy "test policy" \
      > "$hb_out" 2>&1 &
    local hb_pid=$!
    wait_for_grep "$hb_out" "signed." 25 || true
    kill "$hb_pid" 2>/dev/null || true
    wait "$hb_pid" 2>/dev/null || true
  }

  PVD_D="$TMP/pvd-hub"
  mkdir -p "$PVD_D"
  : > "$PVD_D/orchestrator.md"
  : > "$PVD_D/impl-alpha.md"
  PVD_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$PVD_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$PVD_OLINE" --dir "$PVD_D" >/dev/null
  PVD_ALINE=$("$ROOT/coord-keygen.sh" --generate --identity impl-alpha --dir "$PVD_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity impl-alpha --pubkey-line "$PVD_ALINE" --dir "$PVD_D" >/dev/null
  pvd_arm_signed_heartbeat "$PVD_D" impl-alpha "2.0.0"
  PVD_MAJOR_RC=0
  PVD_MAJOR_OUT=$("$ROOT/coordination-precommit-hook.sh" "$PVD_D" "orchestrator" < /dev/null 2>&1) || PVD_MAJOR_RC=$?
  assert_eq "hook-protocol-version-major-mismatch-blocks-rc" "$PVD_MAJOR_RC" "2"
  assert_contains "hook-protocol-version-major-mismatch-message" "$PVD_MAJOR_OUT" "FAIL [protocol-version]: impl-alpha has 1 signed+verified PROTOCOL-VERSION claim(s) incompatible with this seat's own PROTOCOL $PROTOCOL_VERSION (MAJOR ${PROTOCOL_VERSION%%.*})"
  assert_contains "hook-protocol-version-major-mismatch-lists-claim" "$PVD_MAJOR_OUT" "2.0.0 (MAJOR 2) at"

  # (17b) A MINOR/PATCH-only difference must never block — advisory only,
  # surfaced by Parts A/B instead. Fresh peer file (a real HEARTBEAT-based
  # candidate replaces the prior one; check 1d always scans newest-first).
  : > "$PVD_D/impl-alpha.md"
  pvd_arm_signed_heartbeat "$PVD_D" impl-alpha "${PROTOCOL_VERSION%.*}.9"
  PVD_MINOR_RC=0
  PVD_MINOR_OUT=$("$ROOT/coordination-precommit-hook.sh" "$PVD_D" "orchestrator" < /dev/null 2>&1) || PVD_MINOR_RC=$?
  assert_eq "hook-protocol-version-minor-mismatch-does-not-block-rc" "$PVD_MINOR_RC" "0"
  assert_not_contains "hook-protocol-version-minor-mismatch-no-fail" "$PVD_MINOR_OUT" "FAIL [protocol-version]"

  # (17c) Non-vacuous proof (same standard as every prior round): patch a
  # scratch copy of the hook to DROP check 1d entirely and confirm the exact
  # same MAJOR-mismatch fixture from (17) sails through with exit 0 — proves
  # this test would actually have caught the check's absence, not merely
  # that it now happens to pass.
  # Copy ALL siblings (not just the hook itself) — _HOOK_HOME is derived
  # from BASH_SOURCE, so a copy missing coord-receipt.sh/coord-verify.sh/etc
  # would break unrelated code paths (e.g. check 1b's read_receipt call) and
  # produce a false failure unrelated to check 1d.
  PVD_VULN_DIR="$TMP/pvd-vuln-hookdir"
  mkdir -p "$PVD_VULN_DIR"
  cp "$ROOT/coord-verify.sh" "$ROOT/coord-remote-verify.sh" "$ROOT/coord-address-filter.sh" "$ROOT/coord-receipt.sh" "$ROOT/coord-presence.sh" "$ROOT/PROTOCOL-VERSION" "$PVD_VULN_DIR/"
  PVD_VULN_HOOK="$PVD_VULN_DIR/coordination-precommit-hook.sh"
  python3 - "$ROOT/coordination-precommit-hook.sh" "$PVD_VULN_HOOK" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
start = s.index("# ── check 1d:")
end = s.index("# ── check 2:")
assert start != -1 and end != -1 and end > start, "check 1d markers not found"
patched = s[:start] + s[end:]
open(dst, "w").write(patched)
PY
  chmod +x "$PVD_VULN_HOOK"
  bash -n "$PVD_VULN_HOOK"
  # Restore fixture to the MAJOR-mismatch state (17b above left it MINOR).
  : > "$PVD_D/impl-alpha.md"
  pvd_arm_signed_heartbeat "$PVD_D" impl-alpha "2.0.0"
  PVD_VULN_RC=0
  PVD_VULN_OUT=$("$PVD_VULN_HOOK" "$PVD_D" "orchestrator" < /dev/null 2>&1) || PVD_VULN_RC=$?
  echo "$PVD_VULN_OUT" | grep -q "FAIL \[protocol-version\]" && echo "PROVE-NONVACUOUS-FAILED: vulnerable copy still caught the mismatch" >&2
  assert_eq "hook-protocol-version-check-1d-proven-nonvacuous-rc" "$PVD_VULN_RC" "0"
  assert_not_contains "hook-protocol-version-check-1d-proven-nonvacuous-no-fail" "$PVD_VULN_OUT" "FAIL [protocol-version]"

  # (17d)/(17e) ROUND-9 Cipher HIGH — re-attempt Cipher's exact two exploits
  # against the FIXED hook and confirm both now have zero effect (the actual
  # closing bar for this finding, not just that new tests pass).
  PVDX_D="$TMP/pvdx-hub"
  mkdir -p "$PVDX_D"
  : > "$PVDX_D/orchestrator.md"
  : > "$PVDX_D/impl-beta.md"
  PVDX_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$PVDX_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$PVDX_OLINE" --dir "$PVDX_D" >/dev/null
  PVDX_BLINE=$("$ROOT/coord-keygen.sh" --generate --identity impl-beta --dir "$PVDX_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity impl-beta --pubkey-line "$PVDX_BLINE" --dir "$PVDX_D" >/dev/null

  # Exploit 1: forge impl-beta's presence to a bogus MAJOR version with NO
  # real signed claim posted anywhere — must have zero effect (no block).
  mkdir -p "$PVDX_D/.presence"
  printf 'identity=impl-beta\nprotocol_version=99.0.0\n' > "$PVDX_D/.presence/impl-beta"
  PVDX_E1_RC=0
  PVDX_E1_OUT=$("$ROOT/coordination-precommit-hook.sh" "$PVDX_D" "orchestrator" < /dev/null 2>&1) || PVDX_E1_RC=$?
  assert_eq "hook-protocol-version-cipher-exploit1-forged-presence-no-effect-rc" "$PVDX_E1_RC" "0"
  assert_contains "hook-protocol-version-cipher-exploit1-no-verified-claim-info" "$PVDX_E1_OUT" "no verified PROTOCOL-VERSION claim found for 'impl-beta'"

  # Exploit 2: a REAL signed MAJOR mismatch exists; forge presence to MASK it
  # by claiming a matching version — the real signed mismatch must still be
  # caught, presence forgery must have zero effect either way.
  pvd_arm_signed_heartbeat "$PVDX_D" impl-beta "2.0.0"
  printf 'identity=impl-beta\nprotocol_version=%s\n' "$PROTOCOL_VERSION" > "$PVDX_D/.presence/impl-beta"
  PVDX_E2_RC=0
  PVDX_E2_OUT=$("$ROOT/coordination-precommit-hook.sh" "$PVDX_D" "orchestrator" < /dev/null 2>&1) || PVDX_E2_RC=$?
  assert_eq "hook-protocol-version-cipher-exploit2-masking-presence-no-effect-rc" "$PVDX_E2_RC" "2"
  assert_contains "hook-protocol-version-cipher-exploit2-real-mismatch-still-caught" "$PVDX_E2_OUT" "FAIL [protocol-version]: impl-beta has 1 signed+verified PROTOCOL-VERSION claim(s) incompatible"

  # (17e2)/(17e3) ROUND-10 (2026-08-10, Cipher HIGH — round-9's fix moved this
  # hole, did not close it). Round-9's candidate extraction was a SECOND,
  # INDEPENDENT raw-file awk scan that only checked the candidate's TIMESTAMP
  # against a coord-verify.sh VERIFIED line — never that the specific
  # PROTOCOL-VERSION line sat inside the actually-signed bytes. Reproduce
  # Cipher's exact two exploits (unsigned text appended straight after a
  # real message's own SIG block, no new '### ' header) against the fixed
  # code and confirm both now have zero effect.
  PVDG_D="$TMP/pvdg-hub"
  mkdir -p "$PVDG_D"
  : > "$PVDG_D/orchestrator.md"
  : > "$PVDG_D/impl-gamma.md"
  PVDG_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$PVDG_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$PVDG_OLINE" --dir "$PVDG_D" >/dev/null
  PVDG_GLINE=$("$ROOT/coord-keygen.sh" --generate --identity impl-gamma --dir "$PVDG_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity impl-gamma --pubkey-line "$PVDG_GLINE" --dir "$PVDG_D" >/dev/null

  # Exploit 1 (DoS): real signed claim legitimately matches the hub's own
  # MAJOR (clean baseline) — appending UNSIGNED text after the SIG block
  # claiming an incompatible MAJOR must NOT fabricate a mismatch.
  pvd_arm_signed_heartbeat "$PVDG_D" impl-gamma "$PROTOCOL_VERSION"
  PVDG_BASE_RC=0
  PVDG_BASE_OUT=$("$ROOT/coordination-precommit-hook.sh" "$PVDG_D" "orchestrator" < /dev/null 2>&1) || PVDG_BASE_RC=$?
  assert_eq "hook-protocol-version-round10-injection-baseline-clean-rc" "$PVDG_BASE_RC" "0"
  printf '\nPROTOCOL-VERSION: 9.9.9\n' >> "$PVDG_D/impl-gamma.md"
  PVDG_E1_RC=0
  PVDG_E1_OUT=$("$ROOT/coordination-precommit-hook.sh" "$PVDG_D" "orchestrator" < /dev/null 2>&1) || PVDG_E1_RC=$?
  assert_eq "hook-protocol-version-round10-injection-fake-mismatch-no-effect-rc" "$PVDG_E1_RC" "0"
  assert_not_contains "hook-protocol-version-round10-injection-fake-mismatch-no-fail" "$PVDG_E1_OUT" "FAIL [protocol-version]"

  # Exploit 2 (masking): real signed claim genuinely mismatches (2.0.0) —
  # appending UNSIGNED text after the SIG block claiming a MATCHING version
  # must NOT mask the real mismatch.
  : > "$PVDG_D/impl-gamma.md"
  pvd_arm_signed_heartbeat "$PVDG_D" impl-gamma "2.0.0"
  PVDG_E2_BASE_RC=0
  PVDG_E2_BASE_OUT=$("$ROOT/coordination-precommit-hook.sh" "$PVDG_D" "orchestrator" < /dev/null 2>&1) || PVDG_E2_BASE_RC=$?
  assert_eq "hook-protocol-version-round10-injection-mask-baseline-fails-rc" "$PVDG_E2_BASE_RC" "2"
  printf '\nPROTOCOL-VERSION: %s\n' "$PROTOCOL_VERSION" >> "$PVDG_D/impl-gamma.md"
  PVDG_E2_RC=0
  PVDG_E2_OUT=$("$ROOT/coordination-precommit-hook.sh" "$PVDG_D" "orchestrator" < /dev/null 2>&1) || PVDG_E2_RC=$?
  assert_eq "hook-protocol-version-round10-injection-masking-no-effect-rc" "$PVDG_E2_RC" "2"
  assert_contains "hook-protocol-version-round10-injection-masking-real-mismatch-still-caught" "$PVDG_E2_OUT" "FAIL [protocol-version]: impl-gamma has 1 signed+verified PROTOCOL-VERSION claim(s) incompatible"

  # (17e4) Non-vacuous proof: a scratch coord-verify.sh copy whose
  # --extract-field scan targets the WHOLE raw file instead of signed_region
  # (reverting the round-10 fix) must let exploit 1 fabricate a mismatch —
  # proving this test suite would actually have caught the vulnerability,
  # not merely that it now happens to pass.
  PVDG_VULN_DIR="$TMP/pvdg-vuln-hookdir"
  mkdir -p "$PVDG_VULN_DIR"
  cp "$ROOT/coordination-precommit-hook.sh" "$ROOT/coord-remote-verify.sh" "$ROOT/coord-address-filter.sh" "$ROOT/coord-receipt.sh" "$ROOT/coord-presence.sh" "$ROOT/PROTOCOL-VERSION" "$PVDG_VULN_DIR/"
  python3 - "$ROOT/coord-verify.sh" "$PVDG_VULN_DIR/coord-verify.sh" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
needle = '''            for line in signed_region.decode("utf-8", errors="replace").split("\\n"):
                fm = extract_field_re.match(line.rstrip("\\r"))
                if fm:
                    print(f"FIELD-VERIFIED {frm} {ts} {fm.group(1)}")
                    break'''
# Vulnerable shape: scan the WHOLE raw file (not signed_region), and take
# the LAST match rather than the first — this is what reproduces round-9's
# original vulnerability, where injected trailing content (appearing AFTER
# the real signed body in file order) silently overrode the real claim.
replacement = '''            _last = None
            for line in raw.decode("utf-8", errors="replace").split("\\n"):
                fm = extract_field_re.match(line.rstrip("\\r"))
                if fm:
                    _last = fm.group(1)
            if _last is not None:
                print(f"FIELD-VERIFIED {frm} {ts} {_last}")'''
assert needle in s, "extract-field scan-target block not found"
s = s.replace(needle, replacement)
open(dst, "w").write(s)
PY
  chmod +x "$PVDG_VULN_DIR/coord-verify.sh" "$PVDG_VULN_DIR/coordination-precommit-hook.sh"
  bash -n "$PVDG_VULN_DIR/coord-verify.sh"
  # Fixture is already at the exploit-1-injected state (clean 1.5.0 claim +
  # unsigned trailing 9.9.9) from above — reset to that shape explicitly.
  : > "$PVDG_D/impl-gamma.md"
  pvd_arm_signed_heartbeat "$PVDG_D" impl-gamma "$PROTOCOL_VERSION"
  printf '\nPROTOCOL-VERSION: 9.9.9\n' >> "$PVDG_D/impl-gamma.md"
  PVDG_VULN_RC=0
  PVDG_VULN_OUT=$("$PVDG_VULN_DIR/coordination-precommit-hook.sh" "$PVDG_D" "orchestrator" < /dev/null 2>&1) || PVDG_VULN_RC=$?
  echo "$PVDG_VULN_OUT" | grep -q "FAIL \[protocol-version\]" || echo "PROVE-NONVACUOUS-FAILED: vulnerable coord-verify.sh copy did NOT reproduce the fake-mismatch exploit" >&2
  assert_eq "hook-protocol-version-round10-proven-nonvacuous-rc" "$PVDG_VULN_RC" "2"
  assert_contains "hook-protocol-version-round10-proven-nonvacuous-fail" "$PVDG_VULN_OUT" "FAIL [protocol-version]: impl-gamma has 1 signed+verified PROTOCOL-VERSION claim(s) incompatible"
  assert_contains "hook-protocol-version-round10-proven-nonvacuous-fail-lists-9990" "$PVDG_VULN_OUT" "9.9.9 (MAJOR 9) at"

  # (17e5)-(17e7) ROUND-11 (2026-08-10, Cipher HIGH — the third distinct way
  # "which claim is authoritative" was gamed). coord-verify.sh emits
  # FIELD-VERIFIED lines in physical file-byte-offset order, never by the
  # message's own timestamp — a coord-dir-write attacker with ZERO signing
  # key can physically reorder two of a peer's own, genuinely, honestly
  # signed historical HEARTBEATs (no forgery, both still independently
  # verify) and flip which one a "most recent wins" rule would have treated
  # as current. Round-11 eliminates that arbitration: blocks on ANY verified
  # incompatible-MAJOR claim in the tail window, so reordering has no effect
  # in either direction.
  pv_reorder_two_blocks() {
    # <file> — physically swaps the two "### " message blocks in <file>,
    # byte-for-byte, no content touched (Cipher's exact reorder mechanism).
    python3 - "$1" <<'PY'
import sys
path = sys.argv[1]
raw = open(path, "rb").read()
lines = raw.splitlines(keepends=True)
starts = [i for i, l in enumerate(lines) if l.startswith(b"### ")]
assert len(starts) == 2, f"expected exactly 2 message headers, got {len(starts)}"
blocks = []
for idx, s in enumerate(starts):
    e = starts[idx + 1] if idx + 1 < len(starts) else len(lines)
    b = b"".join(lines[s:e])
    if not b.endswith(b"\n"):
        b += b"\n"
    blocks.append(b)
open(path, "wb").write(blocks[1] + blocks[0])
PY
  }

  # (17e5) Mask direction: peer genuinely upgrades from a real mismatch
  # (2.0.0) to a real match ($PROTOCOL_VERSION) — baseline correctly FAILs
  # while the incompatible claim is still in the tail window (the accepted
  # ceiling itself, not a bug — see README's Part D tradeoff note).
  # Reordering must NOT change the verdict.
  PVDO_D="$TMP/pvdo-hub"
  mkdir -p "$PVDO_D"
  : > "$PVDO_D/orchestrator.md"
  : > "$PVDO_D/impl-delta.md"
  PVDO_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$PVDO_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$PVDO_OLINE" --dir "$PVDO_D" >/dev/null
  PVDO_DLINE=$("$ROOT/coord-keygen.sh" --generate --identity impl-delta --dir "$PVDO_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity impl-delta --pubkey-line "$PVDO_DLINE" --dir "$PVDO_D" >/dev/null
  pvd_arm_signed_heartbeat "$PVDO_D" impl-delta "2.0.0"
  sleep 1.2
  pvd_arm_signed_heartbeat "$PVDO_D" impl-delta "$PROTOCOL_VERSION"
  PVDO_BASE_RC=0
  PVDO_BASE_OUT=$("$ROOT/coordination-precommit-hook.sh" "$PVDO_D" "orchestrator" < /dev/null 2>&1) || PVDO_BASE_RC=$?
  assert_eq "hook-protocol-version-round11-mask-baseline-fails-in-window-rc" "$PVDO_BASE_RC" "2"
  pv_reorder_two_blocks "$PVDO_D/impl-delta.md"
  PVDO_VERIFY_OUT=$(bash "$ROOT/coord-verify.sh" --dir "$PVDO_D" --file "$PVDO_D/impl-delta.md" --strict 2>&1)
  assert_not_contains "hook-protocol-version-round11-mask-reorder-still-both-verify" "$PVDO_VERIFY_OUT" "INVALID"
  PVDO_ATTACK_RC=0
  PVDO_ATTACK_OUT=$("$ROOT/coordination-precommit-hook.sh" "$PVDO_D" "orchestrator" < /dev/null 2>&1) || PVDO_ATTACK_RC=$?
  assert_eq "hook-protocol-version-round11-mask-reorder-no-effect-rc" "$PVDO_ATTACK_RC" "$PVDO_BASE_RC"
  assert_contains "hook-protocol-version-round11-mask-reorder-still-caught" "$PVDO_ATTACK_OUT" "FAIL [protocol-version]: impl-delta has 1 signed+verified PROTOCOL-VERSION claim(s)"

  # (17e6) Fabricate direction: peer genuinely rolls back from a real
  # mismatch (2.0.0) to a real match — reordering so the OLD incompatible
  # claim sits last must NOT change the verdict from the honest-order one
  # (both are the same accepted-ceiling FAIL, not a reorder-triggered flip).
  PVDP_D="$TMP/pvdp-hub"
  mkdir -p "$PVDP_D"
  : > "$PVDP_D/orchestrator.md"
  : > "$PVDP_D/impl-epsilon.md"
  PVDP_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$PVDP_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$PVDP_OLINE" --dir "$PVDP_D" >/dev/null
  PVDP_ELINE=$("$ROOT/coord-keygen.sh" --generate --identity impl-epsilon --dir "$PVDP_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity impl-epsilon --pubkey-line "$PVDP_ELINE" --dir "$PVDP_D" >/dev/null
  pvd_arm_signed_heartbeat "$PVDP_D" impl-epsilon "2.0.0"
  sleep 1.2
  pvd_arm_signed_heartbeat "$PVDP_D" impl-epsilon "$PROTOCOL_VERSION"
  PVDP_BASE_RC=0
  PVDP_BASE_OUT=$("$ROOT/coordination-precommit-hook.sh" "$PVDP_D" "orchestrator" < /dev/null 2>&1) || PVDP_BASE_RC=$?
  pv_reorder_two_blocks "$PVDP_D/impl-epsilon.md"
  PVDP_ATTACK_RC=0
  PVDP_ATTACK_OUT=$("$ROOT/coordination-precommit-hook.sh" "$PVDP_D" "orchestrator" < /dev/null 2>&1) || PVDP_ATTACK_RC=$?
  assert_eq "hook-protocol-version-round11-fabricate-reorder-no-effect-rc" "$PVDP_ATTACK_RC" "$PVDP_BASE_RC"

  # (17e7) Non-vacuous proof: a scratch hook copy reverted to "last
  # FIELD-VERIFIED wins" (round-10's shape) must let the mask-direction
  # reorder actually flip the verdict — proving this suite would have
  # caught round-11's vulnerability, not merely that it now happens to pass.
  PVDO_VULN_DIR="$TMP/pvdo-vuln-hookdir"
  mkdir -p "$PVDO_VULN_DIR"
  cp "$ROOT/coord-verify.sh" "$ROOT/coord-remote-verify.sh" "$ROOT/coord-address-filter.sh" "$ROOT/coord-receipt.sh" "$ROOT/coord-presence.sh" "$ROOT/PROTOCOL-VERSION" "$PVDO_VULN_DIR/"
  python3 - "$ROOT/coordination-precommit-hook.sh" "$PVDO_VULN_DIR/coordination-precommit-hook.sh" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
# Pass A: only the extraction line changes shape (collect-every-claim ->
# last-claim-wins). Left as its own needle/replace so unrelated code
# sitting immediately after this line in current source (untouched — not
# what this proof is about) never needs to appear in either string.
needle_a = '''          _pv_claims=$(printf '%s\\n' "$_pv_verify_out" | awk -v peer="$_pv_peer" '$1=="FIELD-VERIFIED" && $2==peer { v=$4; for (i=5;i<=NF;i++) v=v" "$i; print $3"|"v }')'''
assert needle_a in s, "round-11 claims-extraction line not found"
replacement_a = '''          _pv_peer_ver=$(printf '%s\\n' "$_pv_verify_out" | awk -v peer="$_pv_peer" '$1=="FIELD-VERIFIED" && $2==peer { v=$4; for (i=5;i<=NF;i++) v=v" "$i; last=v } END { if (last != "") print last }')'''
s = s.replace(needle_a, replacement_a)
# Pass B: the arbitration logic itself (collect-every-incompatible-claim ->
# single-claim MAJOR check).
needle_b = '''        if [[ -z "$_pv_claims" ]]; then
          echo "INFO [protocol-version]: no verified PROTOCOL-VERSION claim found for '$_pv_peer' within the last $_PV_TAIL_VERIFIED_N verified message(s) of $_pv_peer_file — skipping (new peer, archived/rotated seat, pre-1.5.0 history, or nothing verified yet). Never hard-blocking on absent data."
          continue
        fi
        _PV_KNOWN=$((_PV_KNOWN + 1))
        _pv_incompatible=()
        while IFS= read -r _pv_claim; do
          _pv_cts="${_pv_claim%%|*}"
          _pv_cver="${_pv_claim#*|}"
          _pv_cmajor="${_pv_cver%%.*}"
          [[ -n "$_pv_cmajor" && "$_pv_cmajor" != "$MY_PV_MAJOR" ]] && _pv_incompatible+=("$_pv_cver (MAJOR $_pv_cmajor) at $_pv_cts")
        done <<< "$_pv_claims"
        if [[ ${#_pv_incompatible[@]} -gt 0 ]]; then
          echo ""
          echo "FAIL [protocol-version]: $_pv_peer has ${#_pv_incompatible[@]} signed+verified PROTOCOL-VERSION claim(s) incompatible with this seat's own PROTOCOL $PROTOCOL_VERSION (MAJOR $MY_PV_MAJOR):"
          for _pv_inc in "${_pv_incompatible[@]}"; do
            echo "  - $_pv_inc"
          done'''
assert needle_b in s, "round-11 block-on-any-incompatible logic not found"
replacement_b = '''        if [[ -z "$_pv_peer_ver" ]]; then
          echo "INFO [protocol-version]: no verified PROTOCOL-VERSION claim found for '$_pv_peer' within the last $_PV_TAIL_VERIFIED_N verified message(s) of $_pv_peer_file — skipping (new peer, archived/rotated seat, pre-1.5.0 history, or nothing verified yet). Never hard-blocking on absent data."
          continue
        fi
        _PV_KNOWN=$((_PV_KNOWN + 1))
        _pv_peer_major="${_pv_peer_ver%%.*}"
        if [[ -n "$_pv_peer_major" && "$_pv_peer_major" != "$MY_PV_MAJOR" ]]; then
          echo ""
          echo "FAIL [protocol-version]: $_pv_peer is running PROTOCOL $_pv_peer_ver (MAJOR $_pv_peer_major, signed+verified) — this seat is on PROTOCOL $PROTOCOL_VERSION (MAJOR $MY_PV_MAJOR)."'''
s = s.replace(needle_b, replacement_b)
open(dst, "w").write(s)
PY
  chmod +x "$PVDO_VULN_DIR/coordination-precommit-hook.sh"
  bash -n "$PVDO_VULN_DIR/coordination-precommit-hook.sh"
  # Fresh mask-direction fixture: real 2.0.0 mismatch, then real match.
  # Under "last wins," honest chronological order (2.0.0 first, compatible
  # last) correctly PASSes (rc=0) — the reverted hook's baseline. Reordering
  # so the OLD 2.0.0 claim is now last flips "last wins" to FAIL (rc=2) —
  # the exploit, masking is really fabrication-by-reorder here since baseline
  # was already clean; the mirror of repro3.sh's mask direction.
  PVDO_VULN_D="$TMP/pvdo-vuln-hub"
  mkdir -p "$PVDO_VULN_D"
  : > "$PVDO_VULN_D/orchestrator.md"
  : > "$PVDO_VULN_D/impl-delta.md"
  PVDO_VULN_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$PVDO_VULN_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$PVDO_VULN_OLINE" --dir "$PVDO_VULN_D" >/dev/null
  PVDO_VULN_DLINE=$("$ROOT/coord-keygen.sh" --generate --identity impl-delta --dir "$PVDO_VULN_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity impl-delta --pubkey-line "$PVDO_VULN_DLINE" --dir "$PVDO_VULN_D" >/dev/null
  pvd_arm_signed_heartbeat "$PVDO_VULN_D" impl-delta "2.0.0"
  sleep 1.2
  pvd_arm_signed_heartbeat "$PVDO_VULN_D" impl-delta "$PROTOCOL_VERSION"
  PVDO_VULN_BASE_RC=0
  PVDO_VULN_BASE_OUT=$("$PVDO_VULN_DIR/coordination-precommit-hook.sh" "$PVDO_VULN_D" "orchestrator" < /dev/null 2>&1) || PVDO_VULN_BASE_RC=$?
  pv_reorder_two_blocks "$PVDO_VULN_D/impl-delta.md"
  PVDO_VULN_ATTACK_RC=0
  PVDO_VULN_ATTACK_OUT=$("$PVDO_VULN_DIR/coordination-precommit-hook.sh" "$PVDO_VULN_D" "orchestrator" < /dev/null 2>&1) || PVDO_VULN_ATTACK_RC=$?
  # Honest chronological order under "last wins" = [old 2.0.0, new compatible]
  # -> the LAST claim (compatible) wins -> baseline PASSes (rc=0). Reorder
  # swaps so the OLD 2.0.0 claim is now last -> "last wins" flips to FAIL
  # (rc=2) -> the exploit (masking a real mismatch by controlling which
  # claim sits last) reproduces as base_rc=0, attack_rc=2.
  [[ "$PVDO_VULN_BASE_RC" -eq 0 && "$PVDO_VULN_ATTACK_RC" -ne 0 ]] || echo "PROVE-NONVACUOUS-FAILED: reverted 'last wins' copy did NOT reproduce the reorder exploit (base_rc=$PVDO_VULN_BASE_RC attack_rc=$PVDO_VULN_ATTACK_RC)" >&2
  assert_eq "hook-protocol-version-round11-proven-nonvacuous-base-rc" "$PVDO_VULN_BASE_RC" "0"
  assert_eq "hook-protocol-version-round11-proven-nonvacuous-attack-rc" "$PVDO_VULN_ATTACK_RC" "2"

  # (17e8)-(17e10) ROUND-12 (2026-08-10, Cipher HIGH — a fourth distinct way
  # this gate's window was gamed): the underlying `coord-verify.sh --tail N`
  # window round-11's fix reads from is itself a RAW LINE COUNT, computed
  # before any signature classification. A coord-dir-write-level attacker
  # with ZERO signing key can append messages SHAPED to match the dead-man
  # alarm's own documented --strict exemption (c) — tag starting "⚠️ ", body's
  # first line the exact "[SIGNING-FAILED — ...]" sentinel; that exemption
  # checks SHAPE only, never that heartbeat.sh itself produced it. Each one
  # is legitimately non-fatal under --strict while ALSO counting as a raw
  # line toward --tail's eviction boundary — enough of them pushes a peer's
  # real, currently-true, genuinely signed+verified incompatible
  # PROTOCOL-VERSION claim out of the window entirely. Fix: coord-verify.sh's
  # new --tail-verified N computes its window from CLASSIFIED content — the
  # last N spans that actually VERIFIED — so unsigned padding of any shape
  # cannot consume any of that budget.
  pv_append_exempt_padding() {
    # <file> <from> <to> <count>
    local f="$1" frm="$2" to="$3" n="$4" i=0
    {
      while [ "$i" -lt "$n" ]; do
        printf '\n### 2026-08-10T00:%02d:00Z — %s → %s — \xe2\x9a\xa0\xef\xb8\x8f ATTACKER-PAD-%d\n\n[SIGNING-FAILED — heartbeat.sh could not sign this alarm; posting unsigned per documented dead-man-alarm exemption]\n' \
          "$((i % 60))" "$frm" "$to" "$i"
        i=$((i + 1))
      done
    } >> "$f"
  }

  PVDQ_D="$TMP/pvdq-hub"
  mkdir -p "$PVDQ_D"
  : > "$PVDQ_D/orchestrator.md"
  : > "$PVDQ_D/impl-alpha2.md"
  PVDQ_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$PVDQ_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$PVDQ_OLINE" --dir "$PVDQ_D" >/dev/null
  PVDQ_ALINE=$("$ROOT/coord-keygen.sh" --generate --identity impl-alpha2 --dir "$PVDQ_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity impl-alpha2 --pubkey-line "$PVDQ_ALINE" --dir "$PVDQ_D" >/dev/null
  # Real, genuine, currently-true MAJOR-incompatible claim.
  pvd_arm_signed_heartbeat "$PVDQ_D" impl-alpha2 "2.0.0"
  PVDQ_BASE_RC=0
  PVDQ_BASE_OUT=$("$ROOT/coordination-precommit-hook.sh" "$PVDQ_D" "orchestrator" < /dev/null 2>&1) || PVDQ_BASE_RC=$?
  assert_eq "hook-protocol-version-round12-baseline-blocks-rc" "$PVDQ_BASE_RC" "2"

  # 150 unsigned, zero-signing-key, exemption-(c)-shaped padding messages —
  # more than enough to have evicted the real claim from a 400-raw-line
  # --tail window under round-11's code.
  pv_append_exempt_padding "$PVDQ_D/impl-alpha2.md" impl-alpha2 orchestrator 150
  # coord-verify.sh --strict on the padded file must still pass clean — the
  # padding is legitimately exempt, working exactly as exemption (c) is
  # meant to (this is not the bug; the bug is that it ALSO evicted the real
  # claim under raw-line --tail).
  PVDQ_STRICT_RC=0
  bash "$ROOT/coord-verify.sh" --dir "$PVDQ_D" --file "$PVDQ_D/impl-alpha2.md" --strict >/dev/null 2>&1 || PVDQ_STRICT_RC=$?
  assert_eq "hook-protocol-version-round12-padding-still-strict-clean-rc" "$PVDQ_STRICT_RC" "0"

  # Simulate the hub's own mailbox-read tracking having advanced past the
  # padding (automatic on any armed watcher's normal wake cycle — no special
  # action needed) so check 1c's OWN gate cannot incidentally mask whether
  # check 1d's window logic itself is exploitable, isolating exactly what
  # round-12 is about.
  mkdir -p "$PVDQ_D/.watch-state/orchestrator"
  write_receipt "$PVDQ_D/.watch-state/orchestrator/impl-alpha2.md.size" \
    "$(wc -c < "$PVDQ_D/impl-alpha2.md" | tr -d ' ')" "$PVDQ_D/impl-alpha2.md"
  PVDQ_ATTACK_RC=0
  PVDQ_ATTACK_OUT=$("$ROOT/coordination-precommit-hook.sh" "$PVDQ_D" "orchestrator" < /dev/null 2>&1) || PVDQ_ATTACK_RC=$?
  # (17e8) The real MAJOR mismatch must still block after padding — not be
  # evicted from the window ("0 with a verified claim" was round-12's bug).
  assert_eq "hook-protocol-version-round12-padding-no-effect-rc" "$PVDQ_ATTACK_RC" "2"
  assert_contains "hook-protocol-version-round12-padding-claim-still-listed" "$PVDQ_ATTACK_OUT" "2.0.0 (MAJOR 2) at"
  assert_contains "hook-protocol-version-round12-padding-checked-count" "$PVDQ_ATTACK_OUT" "1 with a verified PROTOCOL-VERSION claim"

  # (17e9) Non-vacuous proof: a scratch coord-verify.sh copy with
  # --tail-verified's classify-then-slice window reverted to the OLD
  # raw-line --tail semantics (i.e. --tail-verified silently behaves like
  # plain --tail) must let the SAME padding attack actually evict the real
  # claim — proving this suite would have caught round-12's vulnerability,
  # not merely that it now happens to pass.
  PVDQ_VULN_DIR="$TMP/pvdq-vuln-verifydir"
  mkdir -p "$PVDQ_VULN_DIR"
  cp "$ROOT/coordination-precommit-hook.sh" "$ROOT/coord-remote-verify.sh" "$ROOT/coord-address-filter.sh" "$ROOT/coord-receipt.sh" "$ROOT/coord-presence.sh" "$ROOT/heartbeat.sh" "$ROOT/coord-keygen.sh" "$ROOT/PROTOCOL-VERSION" "$PVDQ_VULN_DIR/"
  python3 - "$ROOT/coord-verify.sh" "$PVDQ_VULN_DIR/coord-verify.sh" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
needle = '''if tail_verified_n > 0:
    _tv_boundary = 0
    _tv_seen = 0
    for _tv_idx in range(len(results) - 1, -1, -1):
        if results[_tv_idx][0] == "VERIFIED":
            _tv_seen += 1
            if _tv_seen >= tail_verified_n:
                _tv_boundary = _tv_idx
                break
    results = results[_tv_boundary:]'''
assert needle in s, "round-12 tail-verified classify-then-slice logic not found"
# Reverts round-12's fix back to the original vulnerable shape: a raw
# entry-count cut (counts every entry toward the budget, not just VERIFIED
# ones) — the exact round-12 bug, where unsigned padding of any exempt
# shape can spend a raw --tail-style budget it should never be able to
# touch, evicting the real verified claim from the window.
replacement = '''if tail_verified_n > 0:
    _tv_boundary = max(0, len(results) - tail_verified_n)
    results = results[_tv_boundary:]'''
s = s.replace(needle, replacement)
open(dst, "w").write(s)
PY
  chmod +x "$PVDQ_VULN_DIR/coord-verify.sh"
  bash -n "$PVDQ_VULN_DIR/coord-verify.sh"
  PVDQ_VULN_D="$TMP/pvdq-vuln-hub"
  mkdir -p "$PVDQ_VULN_D"
  : > "$PVDQ_VULN_D/orchestrator.md"
  : > "$PVDQ_VULN_D/impl-alpha3.md"
  PVDQ_VULN_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$PVDQ_VULN_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$PVDQ_VULN_OLINE" --dir "$PVDQ_VULN_D" >/dev/null
  PVDQ_VULN_ALINE=$("$ROOT/coord-keygen.sh" --generate --identity impl-alpha3 --dir "$PVDQ_VULN_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity impl-alpha3 --pubkey-line "$PVDQ_VULN_ALINE" --dir "$PVDQ_VULN_D" >/dev/null
  PVDQ_VULN_HOME="$TMP/pvdq-vuln-hb-home"
  mkdir -p "$PVDQ_VULN_HOME"
  cp "$PVDQ_VULN_DIR/heartbeat.sh" "$PVDQ_VULN_DIR/coord-keygen.sh" "$PVDQ_VULN_DIR/coord-presence.sh" "$PVDQ_VULN_HOME/"
  printf 'PROTOCOL_VERSION=%s\n' "2.0.0" > "$PVDQ_VULN_HOME/PROTOCOL-VERSION"
  mkdir -p "$PVDQ_VULN_D/.watch-state/impl-alpha3"
  ( sleep 30 & echo $! > "$PVDQ_VULN_D/.watch-state/impl-alpha3/watcher.pid" ) &
  wait
  PVDQ_VULN_HB_OUT="$TMP/pvdq-vuln-hb.out"
  "$PVDQ_VULN_HOME/heartbeat.sh" --identity impl-alpha3 --role implementer --dir "$PVDQ_VULN_D" \
    --idle-threshold 0 --cadence 1 --idle-policy "test policy" \
    > "$PVDQ_VULN_HB_OUT" 2>&1 &
  PVDQ_VULN_HB_PID=$!
  wait_for_grep "$PVDQ_VULN_HB_OUT" "signed." 25 || true
  kill "$PVDQ_VULN_HB_PID" 2>/dev/null || true
  wait "$PVDQ_VULN_HB_PID" 2>/dev/null || true
  pv_append_exempt_padding "$PVDQ_VULN_D/impl-alpha3.md" impl-alpha3 orchestrator 150
  mkdir -p "$PVDQ_VULN_D/.watch-state/orchestrator"
  write_receipt "$PVDQ_VULN_D/.watch-state/orchestrator/impl-alpha3.md.size" \
    "$(wc -c < "$PVDQ_VULN_D/impl-alpha3.md" | tr -d ' ')" "$PVDQ_VULN_D/impl-alpha3.md"
  PVDQ_VULN_ATTACK_RC=0
  PVDQ_VULN_ATTACK_OUT=$("$PVDQ_VULN_DIR/coordination-precommit-hook.sh" "$PVDQ_VULN_D" "orchestrator" < /dev/null 2>&1) || PVDQ_VULN_ATTACK_RC=$?
  [[ "$PVDQ_VULN_ATTACK_RC" -eq 0 ]] || echo "PROVE-NONVACUOUS-FAILED: reverted raw-tail copy did NOT reproduce the padding-eviction exploit (attack_rc=$PVDQ_VULN_ATTACK_RC)" >&2
  # (17e9) The reverted (pre-round-12) copy must be FOOLED (rc=0, "0 with a
  # verified claim") — proving the fix, not just the fixture, is what closes
  # this.
  assert_eq "hook-protocol-version-round12-proven-nonvacuous-attack-rc" "$PVDQ_VULN_ATTACK_RC" "0"
  assert_contains "hook-protocol-version-round12-proven-nonvacuous-evicted" "$PVDQ_VULN_ATTACK_OUT" "0 with a verified PROTOCOL-VERSION claim"

  # (17e10) Direct coverage of coord-verify.sh's own --tail-verified flag
  # (not only through the hook): a single VERIFIED message followed by 150
  # unsigned exempt padding messages — --tail-verified 1 must still surface
  # the FIELD-VERIFIED line for the original message; plain --tail 5 (a
  # small raw-line window that easily fits inside the padding alone) must
  # NOT, demonstrating the concrete difference in behavior the fix depends
  # on.
  PVDS_D="$TMP/pvds-hub"
  mkdir -p "$PVDS_D"
  : > "$PVDS_D/orchestrator.md"
  : > "$PVDS_D/impl-alpha4.md"
  PVDS_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$PVDS_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$PVDS_OLINE" --dir "$PVDS_D" >/dev/null
  PVDS_ALINE=$("$ROOT/coord-keygen.sh" --generate --identity impl-alpha4 --dir "$PVDS_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity impl-alpha4 --pubkey-line "$PVDS_ALINE" --dir "$PVDS_D" >/dev/null
  pvd_arm_signed_heartbeat "$PVDS_D" impl-alpha4 "2.0.0"
  pv_append_exempt_padding "$PVDS_D/impl-alpha4.md" impl-alpha4 orchestrator 150
  PVDS_TV_OUT=$(bash "$ROOT/coord-verify.sh" --dir "$PVDS_D" --file "$PVDS_D/impl-alpha4.md" --tail-verified 1 --extract-field PROTOCOL-VERSION 2>/dev/null)
  assert_contains "coord-verify-tail-verified-finds-claim-behind-padding" "$PVDS_TV_OUT" "FIELD-VERIFIED impl-alpha4"
  PVDS_TAIL5_OUT=$(bash "$ROOT/coord-verify.sh" --dir "$PVDS_D" --file "$PVDS_D/impl-alpha4.md" --tail 5 --extract-field PROTOCOL-VERSION 2>/dev/null)
  # fixed to use assert_not_contains (was a bare echo PASS/FAIL that never
  # incremented the suite's real $PASS/$FAIL counters or affected its exit
  # code).
  assert_not_contains "coord-verify-plain-tail-evicted-by-padding-contrast" "$PVDS_TAIL5_OUT" "FIELD-VERIFIED impl-alpha4"

  # (17f) ROUND-9 Cipher — peer enumeration must derive from allowed_signers,
  # not a mailbox-file-shaped list: an identity crafted to match
  # coord_is_seat_outbox_basename's structural exclusion (e.g. "queue-evil")
  # must still be checked and still block on a real MAJOR mismatch.
  PVDN_D="$TMP/pvdn-hub"
  mkdir -p "$PVDN_D"
  : > "$PVDN_D/orchestrator.md"
  : > "$PVDN_D/queue-evil.md"
  PVDN_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$PVDN_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$PVDN_OLINE" --dir "$PVDN_D" >/dev/null
  PVDN_QLINE=$("$ROOT/coord-keygen.sh" --generate --identity queue-evil --dir "$PVDN_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity queue-evil --pubkey-line "$PVDN_QLINE" --dir "$PVDN_D" >/dev/null
  pvd_arm_signed_heartbeat "$PVDN_D" queue-evil "2.0.0"
  PVDN_RC=0
  PVDN_OUT=$("$ROOT/coordination-precommit-hook.sh" "$PVDN_D" "orchestrator" < /dev/null 2>&1) || PVDN_RC=$?
  assert_eq "hook-protocol-version-naming-evasion-peer-still-caught-rc" "$PVDN_RC" "2"
  assert_contains "hook-protocol-version-naming-evasion-peer-still-caught-msg" "$PVDN_OUT" "FAIL [protocol-version]: queue-evil has 1 signed+verified PROTOCOL-VERSION claim(s) incompatible"

  # (17g) ROUND-9 Rook — an archived/rotated peer (<id>.md renamed to
  # <id>.archive.md, an ordinary lifecycle event) stays enrolled and must
  # still be COUNTED (not silently invisible the way INBOX_FILES-based
  # enumeration made it) even though its signed claim can no longer verify
  # there (coord-verify.sh's structural FROM==basename(file) check rejects
  # *.archive.md content by design — see coordination-precommit-hook.sh's
  # check 1d comment). Never hard-blocks on this absence.
  PVDR_D="$TMP/pvdr-hub"
  mkdir -p "$PVDR_D"
  : > "$PVDR_D/orchestrator.md"
  : > "$PVDR_D/impl-rotated.md"
  PVDR_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$PVDR_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$PVDR_OLINE" --dir "$PVDR_D" >/dev/null
  PVDR_RLINE=$("$ROOT/coord-keygen.sh" --generate --identity impl-rotated --dir "$PVDR_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity impl-rotated --pubkey-line "$PVDR_RLINE" --dir "$PVDR_D" >/dev/null
  pvd_arm_signed_heartbeat "$PVDR_D" impl-rotated "2.0.0"
  mv "$PVDR_D/impl-rotated.md" "$PVDR_D/impl-rotated.archive.md"
  PVDR_RC=0
  PVDR_OUT=$("$ROOT/coordination-precommit-hook.sh" "$PVDR_D" "orchestrator" < /dev/null 2>&1) || PVDR_RC=$?
  assert_eq "hook-protocol-version-archived-peer-not-blocked-rc" "$PVDR_RC" "0"
  assert_contains "hook-protocol-version-archived-peer-honestly-named" "$PVDR_OUT" "no verified PROTOCOL-VERSION claim found for 'impl-rotated'"
  assert_contains "hook-protocol-version-archived-peer-checked-count" "$PVDR_OUT" "checked 1 enrolled peer(s), 0 with a verified"

  # (17h) ROUND-9 Rook "fix this first" — self-side unknown-version guard.
  # A partial/incomplete framework copy (PROTOCOL-VERSION file missing
  # beside the hook) must WARN + skip the whole gate, never false-block
  # every peer by comparing "unknown" against a real MAJOR number.
  PVDU_HOOKDIR="$TMP/pvdu-hookdir"
  mkdir -p "$PVDU_HOOKDIR"
  cp "$ROOT/coordination-precommit-hook.sh" "$ROOT/coord-verify.sh" "$ROOT/coord-remote-verify.sh" "$ROOT/coord-address-filter.sh" "$ROOT/coord-receipt.sh" "$ROOT/coord-presence.sh" "$PVDU_HOOKDIR/"
  # Deliberately no PROTOCOL-VERSION file copied.
  chmod +x "$PVDU_HOOKDIR/coordination-precommit-hook.sh"
  # ROUND-10 (Rook): must point at a dir with a LIVE, verified MAJOR-
  # mismatching peer (PVDN_D — queue-evil's real signed 2.0.0 claim), not
  # PVDR_D (the archived-peer dir, where _PV_KNOWN would be 0 regardless of
  # the guard — removing the guard wouldn't flip this test red there, so it
  # wasn't actually testing anything). Against PVDN_D, a guard-less
  # comparison would try "unknown" != "2" and produce a false FAIL — this is
  # what proves the guard is load-bearing.
  PVDU_RC=0
  PVDU_OUT=$("$PVDU_HOOKDIR/coordination-precommit-hook.sh" "$PVDN_D" "orchestrator" < /dev/null 2>&1) || PVDU_RC=$?
  assert_eq "hook-protocol-version-self-unknown-skips-not-blocks-rc" "$PVDU_RC" "0"
  assert_contains "hook-protocol-version-self-unknown-warns" "$PVDU_OUT" "WARN [protocol-version]: this seat's own PROTOCOL_VERSION is unknown"
  assert_not_contains "hook-protocol-version-self-unknown-no-false-fail" "$PVDU_OUT" "FAIL [protocol-version]"

  # (17i) ROUND-9 Rook — the coord-monitor.sh half of the same self-unknown
  # guard: must WARN and skip Part B's peer checks entirely, never crash and
  # never compare "unknown" against a real peer version.
  PVDM_HOME="$TMP/pvdm-monitor-home"
  mkdir -p "$PVDM_HOME"
  cp "$ROOT/coord-monitor.sh" "$ROOT/coord-presence.sh" "$ROOT/coord-send.sh" "$ROOT/coord-keygen.sh" "$ROOT/coord-verify.sh" "$ROOT/coord-remote-verify.sh" "$ROOT/coord-address-filter.sh" "$ROOT/coord-receipt.sh" "$PVDM_HOME/"
  # Deliberately no PROTOCOL-VERSION file copied.
  PVDM_D="$TMP/pvdm-hub"
  mkdir -p "$PVDM_D/.watch-state/impl-x"
  : > "$PVDM_D/orchestrator.md"
  : > "$PVDM_D/impl-x.md"
  PVDM_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$PVDM_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$PVDM_OLINE" --dir "$PVDM_D" >/dev/null
  mkdir -p "$PVDM_D/.presence"
  printf 'identity=impl-x\nprotocol_version=9.9.9\n' > "$PVDM_D/.presence/impl-x"
  PVDM_OUT="$TMP/pvdm-monitor.out"
  : > "$PVDM_OUT"
  bash "$PVDM_HOME/coord-monitor.sh" --identity orchestrator --dir "$PVDM_D" --poll 1 > "$PVDM_OUT" 2>&1 &
  PVDM_PID=$!
  wait_for_grep "$PVDM_OUT" "ARMED for orchestrator" 25 || true
  sleep 1
  kill "$PVDM_PID" 2>/dev/null || true
  wait "$PVDM_PID" 2>/dev/null || true
  assert_contains "monitor-protocol-version-self-unknown-warns" "$(cat "$PVDM_OUT")" "this seat's own PROTOCOL_VERSION is unknown"
  assert_not_contains "monitor-protocol-version-self-unknown-no-alert" "$(cat "$PVDM_D/orchestrator.md")" "PROTOCOL-VERSION-MISMATCH"

  # (17j) ROUND-9 item 2 — the dedup state write + "Alert posted" message
  # must only happen on an ACTUAL coord-send.sh success, and its real
  # failure reason must be surfaced, not swallowed via 2>&1.
  PVDF_HOME="$TMP/pvdf-monitor-home"
  mkdir -p "$PVDF_HOME"
  cp "$ROOT/coord-monitor.sh" "$ROOT/coord-presence.sh" "$ROOT/coord-keygen.sh" "$ROOT/coord-verify.sh" "$ROOT/coord-remote-verify.sh" "$ROOT/coord-address-filter.sh" "$ROOT/coord-receipt.sh" "$ROOT/PROTOCOL-VERSION" "$PVDF_HOME/"
  cat > "$PVDF_HOME/coord-send.sh" <<'STUB'
#!/bin/bash
echo "PVDF-STUB-SEND-FAILURE: simulated coord-send.sh failure for round-9 test" >&2
exit 9
STUB
  chmod +x "$PVDF_HOME/coord-send.sh"
  PVDF_D="$TMP/pvdf-hub"
  mkdir -p "$PVDF_D/.watch-state/impl-x"
  : > "$PVDF_D/orchestrator.md"
  : > "$PVDF_D/impl-x.md"
  PVDF_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$PVDF_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$PVDF_OLINE" --dir "$PVDF_D" >/dev/null
  mkdir -p "$PVDF_D/.presence"
  printf 'identity=impl-x\nprotocol_version=9.9.9\n' > "$PVDF_D/.presence/impl-x"
  PVDF_OUT="$TMP/pvdf-monitor.out"
  : > "$PVDF_OUT"
  bash "$PVDF_HOME/coord-monitor.sh" --identity orchestrator --dir "$PVDF_D" --poll 1 > "$PVDF_OUT" 2>&1 &
  PVDF_PID=$!
  wait_for_grep "$PVDF_OUT" "ARMED for orchestrator" 25 || true
  sleep 1
  kill "$PVDF_PID" 2>/dev/null || true
  wait "$PVDF_PID" 2>/dev/null || true
  assert_contains "monitor-protocol-version-send-failure-surfaced" "$(cat "$PVDF_OUT")" "PVDF-STUB-SEND-FAILURE"
  assert_not_contains "monitor-protocol-version-send-failure-no-false-posted-msg" "$(cat "$PVDF_OUT")" "Alert posted to"
  PVDF_STATE_COUNT=$(find "$PVDF_D/.watch-state" -name "protocol-version.*" 2>/dev/null | wc -l | tr -d ' ')
  assert_eq "monitor-protocol-version-send-failure-no-state-write" "$PVDF_STATE_COUNT" "0"

  # (17k) ROUND-9 item 3 — COORD_CANONICAL_SOURCE newline/CR injection must
  # be rejected (falls back to default wording), same rejection posture as
  # round 6's 4-site fix, not silently spliced into a signed message body.
  PVDC_INJECTED=$(printf 'evil\n\n### 2020-01-01T00:00:00Z — attacker → ALL — FAKE-TAG\nfake body')
  PVDC_MSG=$(bash -c '. "$1/coord-presence.sh"; COORD_CANONICAL_SOURCE="$2" protocol_mismatch_message orchestrator 1.5.0 impl-x 2.0.0' _ "$ROOT" "$PVDC_INJECTED" 2>/dev/null)
  assert_not_contains "presence-canonical-source-injection-rejected" "$PVDC_MSG" "FAKE-TAG"
  assert_contains "presence-canonical-source-injection-falls-back" "$PVDC_MSG" "ask your Orchestrator/human where the canonical framework repo lives"

  # (17l) ROUND-9 item 4 — Part B's alert must be surfaced by the RECEIVING
  # peer's OWN live monitor sweep (not just proven to land in the sender's
  # own outbox file, which the pre-existing (16) tests already cover).
  PVDL_D="$TMP/pvdl-hub"
  mkdir -p "$PVDL_D/.watch-state/impl-y" "$PVDL_D/.watch-state/orchestrator"
  : > "$PVDL_D/orchestrator.md"
  : > "$PVDL_D/impl-y.md"
  PVDL_OLINE=$("$ROOT/coord-keygen.sh" --generate --identity orchestrator --dir "$PVDL_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity orchestrator --pubkey-line "$PVDL_OLINE" --dir "$PVDL_D" >/dev/null
  PVDL_YLINE=$("$ROOT/coord-keygen.sh" --generate --identity impl-y --dir "$PVDL_D" 2>/dev/null)
  "$ROOT/coord-keygen.sh" --enroll --identity impl-y --pubkey-line "$PVDL_YLINE" --dir "$PVDL_D" >/dev/null
  PVDL_Y_OUT="$TMP/pvdl-implY-mon.out"
  : > "$PVDL_Y_OUT"
  "$ROOT/coord-monitor.sh" --identity impl-y --dir "$PVDL_D" --role implementer --poll 1 > "$PVDL_Y_OUT" 2>&1 &
  PVDL_Y_PID=$!
  wait_for_grep "$PVDL_Y_OUT" "ARMED for impl-y" 25 || true
  mkdir -p "$PVDL_D/.presence"
  printf 'identity=impl-y\nprotocol_version=2.0.0\n' > "$PVDL_D/.presence/impl-y"
  "$ROOT/coord-monitor.sh" --identity orchestrator --dir "$PVDL_D" --poll 1 > "$TMP/pvdl-orch-mon.out" 2>&1 &
  PVDL_O_PID=$!
  # Wait for the SIG-verification line specifically, not just the message
  # text — verification is a follow-up step that can land a tick after the
  # body first prints, and asserting on the earlier marker flaked here.
  wait_for_grep "$PVDL_Y_OUT" "✅ VERIFIED orchestrator" 40 || true
  kill "$PVDL_Y_PID" "$PVDL_O_PID" 2>/dev/null || true
  wait "$PVDL_Y_PID" "$PVDL_O_PID" 2>/dev/null || true
  assert_contains "monitor-protocol-version-receiving-peer-surfaces-alert" "$(cat "$PVDL_Y_OUT")" "⚠️ PROTOCOL-VERSION-MISMATCH"
  assert_contains "monitor-protocol-version-receiving-peer-alert-verified" "$(cat "$PVDL_Y_OUT")" "✅ VERIFIED orchestrator"
else
  echo "SKIP [sig] Message Authenticity tests skipped (see above)."
fi

printf '\n%d passed, %d failed · PROTOCOL %s\n' "$PASS" "$FAIL" "$PROTOCOL_VERSION"
[ "$FAIL" -eq 0 ]
