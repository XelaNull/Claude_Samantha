#!/usr/bin/env bash
# coord-verify.sh — verify SSH signatures on coord-dir mailbox messages.
# PROTOCOL-VERSION: 1.4.0 (Message Authenticity amendment — see README.md
# § Message Authenticity (SSH signing), coord-keygen.sh, coord-send.sh).
#
# Scans a mailbox file for "### <ts> — <FROM> → <TO> — <TAG>" message headers
# and their trailing "<!-- SIG v1 ... -->" block (see MAILBOX-template.md §
# Message Grammar for the exact format coord-send.sh writes), and verifies
# each signed message against <coord-dir>/allowed_signers via:
#   ssh-keygen -Y verify -f allowed_signers -I <FROM> -n samantha-coord -s <sigfile> < <signed-region>
#
# BOUNDARY-EXACT PARSING (2026-08-09 hardening): the SIG block carries an
# explicit `bytes: N` field — the exact byte length of the header+body region
# that was signed, known precisely at sign time (coord-keygen.sh's
# sign_message_file always signs a byte-exact temp file). Verification reads
# exactly N bytes starting at the header line, full stop, regardless of what
# those bytes contain. This replaces an earlier heuristic that scanned
# forward for "the next line that looks like a header" to find a message's
# end — which broke on a legitimately signed message whose BODY merely
# quotes/cites a prior header on its own line (MAILBOX-template.md's own
# worked examples use this pattern): the quote truncated the real signed
# region and orphaned the trailing SIG block, producing a spurious
# INVALID/UNVERIFIED that could hard-block a peer's commit in ordinary,
# honest use. The byte-count field eliminates the ambiguity by construction
# instead of reducing it. A self-consistency check (does header-offset + N
# land exactly on the SIG block's start?) rejects any accidental/attacker
# association with the wrong SIG block; a header-shaped line embedded inside
# a correctly-signed message's own body is therefore automatically skipped
# on the next pass (see "consumed range" in the python body) instead of
# being mistaken for a second message.
#
# Per message prints exactly one of:
#   VERIFIED        ✅ VERIFIED <FROM> <ts>
#   UNVERIFIED       ⚠️  UNVERIFIED (no signature) <FROM> <ts>
#   UNKNOWN-SIGNER   ❓ UNKNOWN-SIGNER (identity not enrolled / allowed_signers stale) <FROM> <ts>
#   INVALID          ❌ INVALID (signature present, verification FAILED) <FROM> <ts>
# plus a SUMMARY line with counts.
#
# UNKNOWN-SIGNER vs INVALID (2026-08-09 hardening): a signature from an
# identity with no matching entry in allowed_signers (or allowed_signers
# missing entirely) used to read as INVALID — documented protocol-wide as
# "tamper/forgery, always fatal." But the overwhelmingly common real cause is
# benign (not enrolled yet / a stale local allowed_signers pull), and
# README's own § "The third clock" warns against exactly this alarm-fatigue
# shape. Classification is deterministic, not stderr-text-sniffing: run
# `ssh-keygen -Y match-principals -I <FROM> -f allowed_signers` FIRST — if it
# finds no matching principal (or the file is missing), the message is
# UNKNOWN-SIGNER, full stop, before a real -Y verify is even attempted. Only
# once an identity IS confirmed enrolled does a verify failure mean an actual
# bad signature (INVALID, tamper signal). UNKNOWN-SIGNER blocks under
# --strict exactly like non-exempt UNVERIFIED (the gate is not weakened —
# every real deployment's precommit hook always runs --strict). It EXITS 0
# without --strict (does not fail the run) but is never silent — it prints
# unconditionally either way, with different remedy text than INVALID
# ("enroll this identity / pull current allowed_signers", not "tamper
# detected") so a human reading the output isn't left guessing. (Comment
# corrected 2026-08-09 round-2 — a prior draft of this comment claimed the
# line was suppressed entirely without --strict; the code never did that.)
#
# STRUCTURAL CHECK — FROM must equal the mailbox file's own basename (minus
# .md). This is already supposed to hold for every legitimate message under
# the STAR single-writer-per-file invariant (each identity only ever appends
# to its own file). Two-tier application (2026-08-09 round-2 hardening —
# see EXEMPTIONS below for why it is NOT one single unconditional rule):
#   - A message that carries a SIG block and verifies cryptographically but
#     claims a FROM different from the file it sits in is downgraded
#     VERIFIED -> INVALID (always fatal — see EXIT CODE below). This closes
#     "a validly-signed message copy-pasted into a different mailbox
#     currently verifies fine," the cross-mailbox splice attack the
#     single-writer invariant exists to prevent.
#   - A message with NO SIG block (going through EXEMPTIONS below) requires
#     FROM == basename(file) UNCONDITIONALLY before ANY of the three
#     exemptions is even considered (previously only exemptions (a)/(c)
#     carried this check per-exemption; (b) ASSIGN-IDENTITY had none of its
#     own, letting an unsigned forged enrollment reply land as exempt in the
#     WRONG file). A mismatch here does NOT escalate to INVALID the way the
#     signed case above does — it stays non-exempt UNVERIFIED, which is
#     already fatal under --strict (the only mode every real deployment's
#     precommit hook runs — see EXIT CODE below), so the actual hole is
#     closed either way. Escalating the unsigned case to INVALID as well was
#     tried and reverted: exemption (a)'s own HEADS-UP message is a real,
#     permanently FROM/file-mismatched artifact BY DESIGN once
#     bootstrap-identity.sh's --adopt renames pending-<uuid>.md to the
#     assigned identity's own file (that rename never rewrites the
#     message's FROM field — it is history, not tamper). Making that
#     INVALID would leave every successfully-adopted identity's mailbox
#     permanently unable to verify cleanly, forever, even outside --strict —
#     a real regression discovered by running the test suite, not a
#     hypothetical.
#
# EXIT CODE:
#   Non-zero iff any message is INVALID (tamper/forgery signal) — always
#   fatal, --strict or not. UNVERIFIED and UNKNOWN-SIGNER alone exit 0 UNLESS
#   --strict is given, in which case UNKNOWN-SIGNER always fails and
#   UNVERIFIED fails WITH THREE EXEMPTIONS (below), because legacy/
#   pre-amendment history, the trust-bootstrap handshake, and the dead-man
#   alerts that must never be silently swallowed for auth-layer reasons all
#   need a way to stay readable/postable without deadlocking.
#
# EXEMPTIONS (--strict only, and ONLY for a verdict of UNVERIFIED — i.e. no
# SIG block was associated with the message at all; see the STRUCTURAL CHECK
# above and UNKNOWN-SIGNER above for why a message that DOES carry a SIG
# block is never exempted by anything below, tampered or not). Detected by
# FROM/TAG/TO pattern-matching on the extracted header line — no out-of-band
# flag, no state lookup. FROM == basename(file) is required UNCONDITIONALLY
# before any of the three exemptions below is even considered (2026-08-09
# round-2: previously duplicated per-exemption — (a) and (c) had their own
# copy, (b) had none — now one gate none of the three can bypass; see
# STRUCTURAL CHECK above for why this gate declines the exemption rather
# than escalating straight to INVALID). This is the one place a reviewer
# needs to be able to audit "did they just carve a hole in the gate", so the
# rule is exactly this and nothing more. TAG matching uses
# `.startswith(...)` on the canonical tag prefix, NEVER a bare substring
# match against the whole header-remainder field — that field also carries
# any appended `[$SUBJECT]` free text, and a substring match let an attacker
# forge exemption eligibility by putting an exempt tag's text inside an
# unrelated message's SUBJECT (2026-08-09 hardening; the anchored prefix
# match closes this because coord-send.sh always emits TAG first and
# SUBJECT, if any, strictly after it):
#   (a) FROM matches `pending-*` AND TAG starts with "🛰️ HEADS-UP" — the
#       newborn's very first message (bootstrap-identity.sh --provision),
#       which CARRIES the pubkey establishing trust. Nothing exists yet to
#       verify it against — it is written directly to the provisional file,
#       not via coord-send.sh, and is never signed. (The FROM ==
#       basename(file) structural check above already forces this to only
#       ever appear in its own poster's `pending-<uuid>.md`.)
#   (b) FROM == "orchestrator" AND TAG starts with "🤝 ASSIGN-IDENTITY" AND
#       TO starts with `pending-` — the reply that completes the newborn's
#       enrollment handshake. The TO requirement closes what was previously
#       an unconditional, permanent unsigned channel for anything claiming
#       FROM=orchestrator with this tag; a real handshake reply is only ever
#       addressed to a still-provisional identity. (The structural check
#       above also forces FROM == basename(file) — this exemption is
#       therefore only reachable from orchestrator.md itself, closing an
#       unsigned forged enrollment reply landing in the WRONG file, which
#       used to slip through because this exemption carried no file-binding
#       of its own.)
#   (c) TAG starts with "⚠️ " AND the literal sentinel `[SIGNING-FAILED —`
#       is the body's own first substantive line (leading blank lines
#       skipped, nothing else precedes it) — heartbeat.sh's own
#       best-effort-sign-first, flagged-unsigned-fallback for its dead-man
#       alarms (⚠️ WATCHER-DOWN, ⚠️ HOLD-WAKE-UNACKED — both self-terminate
#       the heartbeat to force a human or peer to notice, so both get
#       identical treatment: exempting one but not the other would be an
#       inconsistent trust model with no defensible reason). Collapsed into
#       ONE sentinel exemption (2026-08-09) rather than two separate
#       tag-enumerated ones: self-extending for any future alarm type
#       heartbeat.sh grows (no new enumerated hole needed). Tightened
#       2026-08-09 round-2 (Rook): the original match had no TAG constraint
#       and matched the sentinel string anywhere in the body, so anything
#       writing to a seat's own outbox could post ANY unsigned content under
#       ANY tag by merely including that string somewhere in the body; both
#       the anchored TAG prefix and "first substantive line" position match
#       exactly what heartbeat.sh actually emits at both call sites and
#       nothing looser. (The structural check above also forces FROM ==
#       basename(file) — a legitimate one can only ever appear in its own
#       poster's outbox, single-writer-per-file invariant.) A message of
#       either alarm type that DOES carry a SIG block gets zero special
#       treatment: per the UNKNOWN-SIGNER/STRUCTURAL CHECK rules above, it
#       is fully verified, file-bound, and a tampered/forged one still comes
#       back INVALID, never exempt.
#       Routine HEARTBEAT/IDLE-KICK/HOLD-CHECK entries carry NO exemption —
#       heartbeat.sh signs those or skips the append outright, so there is
#       no unsigned shape of them for --strict to ever need to tolerate.
#
# --tail N / --since-line N restrict which message HEADERS are considered
# (by line number) — so coord-monitor.sh can cheaply annotate only the
# newly-emitted chunk instead of re-verifying the whole file every wake.
# Neither flag re-scans anything before the cut, so pre-amendment history
# further up the same file is structurally never touched by this script.
#
# Usage:
#   coord-verify.sh --dir <coord-dir> --file <mailbox-file> [--tail N] [--since-line N] [--strict]

set -uo pipefail

DIR=""
FILE=""
TAIL_N=0
SINCE_LINE=0
STRICT=0
FIND_BOUNDARY=""
EXTRACT_FIELD=""
TAIL_VERIFIED_N=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    --file) FILE="$2"; shift 2 ;;
    --tail) TAIL_N="$2"; shift 2 ;;
    --since-line) SINCE_LINE="$2"; shift 2 ;;
    --strict) STRICT=1; shift ;;
    --find-boundary) FIND_BOUNDARY="$2"; shift 2 ;;
    --extract-field) EXTRACT_FIELD="$2"; shift 2 ;;
    --tail-verified) TAIL_VERIFIED_N="$2"; shift 2 ;;
    -h|--help)
      cat <<'USAGE'
Usage: coord-verify.sh --dir <coord-dir> --file <mailbox-file> [--tail N] [--since-line N] [--strict]
  --dir <coord-dir>   location of allowed_signers (the trust root)
  --file <mailbox.md> file to scan for message + SIG blocks
  --tail N            only consider message headers within the last N RAW
                       LINES of the file, before any signature classification
                       — a coord-dir-write-level attacker with no signing key
                       can pad a file with any number of unsigned/exempt
                       lines to evict an older, still-relevant VERIFIED
                       header from this window (round-12, 2026-08-10, Cipher
                       HIGH; see --tail-verified below for the anchored
                       alternative). Mutually exclusive with --tail-verified.
  --since-line N       only consider message headers on lines > N
  --tail-verified N    only consider the last N message spans that actually
                       classify as VERIFIED (plus whatever UNVERIFIED/exempt/
                       UNKNOWN-SIGNER/INVALID spans happen to fall after that
                       Nth-from-end VERIFIED one) — the window boundary is
                       chosen from CLASSIFIED content, never a raw line
                       count, so unsigned padding (including all three
                       --strict exemption shapes) cannot push a real VERIFIED
                       claim out of the window: it is skipped "for free"
                       instead of counting toward N. Round-12 (2026-08-10,
                       Cipher HIGH) fix for the exact gap --tail's raw-line
                       window has; same principle as --extract-field's
                       signed-bytes-only scoping, applied to window selection
                       instead of field extraction. Mutually exclusive with
                       --tail (an unbounded classify-then-slice pass is
                       required to find the Nth VERIFIED span, so combining
                       the two has no coherent meaning). May be combined with
                       --since-line, which still applies as a structural
                       floor on which headers are classified at all.
                       Accepted characteristic (not a bug — see README.md §
                       Protocol Version Handshake, Part D's ceiling notes):
                       finding N verified spans has unbounded worst-case
                       cost relative to file size (no cap — capping naively
                       would reopen the round-12 masking bug this flag
                       exists to fix). A very large or heavily-padded peer
                       mailbox file makes this proportionally slower. This
                       framework runs on private infrastructure between a
                       human's own agent sessions, not a public/multi-tenant
                       service.
  --strict             also fail on non-exempt UNVERIFIED and on
                        UNKNOWN-SIGNER (see header comment for the three
                        exempt shapes that never fail)
  --find-boundary N   print the line index to use as --since-line so that no
                       message whose span covers byte offset N is silently
                       skipped (snaps backward to that message's own header
                       if N falls mid-message); prints NOCOVER and exits
                       nonzero if N cannot be placed relative to any header
                       at all (used by coordination-precommit-hook.sh — see
                       its receipt-forgery hardening). Mutually exclusive
                       with a normal verify run.
  --extract-field NAME  for every VERIFIED message, if a line matching
                       "NAME: <value>" appears WITHIN signed_region (the
                       exact bytes this script verified against — never a
                       second, independent raw-file scan), print an extra
                       "FIELD-VERIFIED <frm> <ts> <value>" line. Content
                       appended after a message's own SIG block (or
                       otherwise outside what was cryptographically checked)
                       can never produce a FIELD-VERIFIED line, by
                       construction — round-10 (2026-08-10, Cipher HIGH):
                       this closes the exact gap a raw-file-scan-then-
                       match-back approach could not (round-9's original
                       fix moved the hole, not closed it).
Exit 0 = clean. Non-zero iff any INVALID, or (--strict) any non-exempt
UNVERIFIED or any UNKNOWN-SIGNER.
USAGE
      exit 0
      ;;
    *) echo "ERROR [coord-verify]: unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$DIR" || -z "$FILE" ]]; then
  echo "ERROR [coord-verify]: --dir and --file are required." >&2
  exit 2
fi
if [[ "$TAIL_N" != "0" && "$TAIL_VERIFIED_N" != "0" ]]; then
  echo "ERROR [coord-verify]: --tail and --tail-verified are mutually exclusive (see --help)." >&2
  exit 2
fi
if [[ ! -f "$FILE" ]]; then
  echo "ERROR [coord-verify]: file not found: $FILE" >&2
  exit 2
fi
command -v python3 >/dev/null 2>&1 || { echo "ERROR [coord-verify]: python3 required." >&2; exit 2; }
command -v ssh-keygen >/dev/null 2>&1 || { echo "ERROR [coord-verify]: ssh-keygen not found — cannot verify signatures." >&2; exit 2; }

# VERSION FLOOR (round-2, item 7): `-Y sign`/`-Y verify` only need OpenSSH
# 8.2+, but the deterministic UNKNOWN-SIGNER classification above (`-Y
# match-principals`) needs 8.9+ — a box at 8.2-8.8 (stock on Ubuntu 20.04
# LTS, macOS Monterey) has EVERY signed message misclassify as
# UNKNOWN-SIGNER and hard-block every commit under --strict, with the
# UNKNOWN-SIGNER remedy text ("enroll this identity / pull current
# allowed_signers") sending the operator chasing the wrong problem entirely.
# One-time probe, distinct diagnostic — never silently degrades.
_ssh_ver=$(ssh -V 2>&1 | grep -oE 'OpenSSH_[0-9]+\.[0-9]+' | head -1)
if [[ -n "$_ssh_ver" ]]; then
  _ssh_major="${_ssh_ver#OpenSSH_}"; _ssh_major="${_ssh_major%%.*}"
  _ssh_minor="${_ssh_ver#OpenSSH_*.}"; _ssh_minor="${_ssh_minor%%[!0-9]*}"
  if [[ "$_ssh_major" =~ ^[0-9]+$ && "$_ssh_minor" =~ ^[0-9]+$ ]] && \
     { [[ "$_ssh_major" -lt 8 ]] || { [[ "$_ssh_major" -eq 8 ]] && [[ "$_ssh_minor" -lt 9 ]]; }; }; then
    echo "WARN [coord-verify]: detected $_ssh_ver — this protocol's deterministic UNKNOWN-SIGNER classification (ssh-keygen -Y match-principals) needs OpenSSH 8.9+; every signed message below may misclassify as UNKNOWN-SIGNER regardless of enrollment. Upgrade OpenSSH, or expect false UNKNOWN-SIGNER verdicts (not a real enrollment/trust problem)." >&2
  fi
fi
unset _ssh_ver _ssh_major _ssh_minor

python3 - "$FILE" "$DIR" "$TAIL_N" "$SINCE_LINE" "$STRICT" "$FIND_BOUNDARY" "$EXTRACT_FIELD" "$TAIL_VERIFIED_N" <<'PY'
import sys, os, re, subprocess, tempfile

file_path, coord_dir = sys.argv[1], sys.argv[2]
tail_n = int(sys.argv[3])
since_line = int(sys.argv[4])
strict = sys.argv[5] == "1"
find_boundary_n = int(sys.argv[6]) if len(sys.argv) > 6 and sys.argv[6] != "" else None
extract_field = sys.argv[7] if len(sys.argv) > 7 and sys.argv[7] != "" else None
extract_field_re = re.compile(r'^' + re.escape(extract_field) + r': (.*)$') if extract_field else None
tail_verified_n = int(sys.argv[8]) if len(sys.argv) > 8 and sys.argv[8] != "" else 0

allowed_signers = os.path.join(coord_dir, "allowed_signers")
allowed_signers_present = os.path.isfile(allowed_signers)
file_basename = os.path.splitext(os.path.basename(file_path))[0]

with open(file_path, "rb") as f:
    raw = f.read()

raw_lines = raw.splitlines(keepends=True)
n_lines = len(raw_lines)
offsets = []
pos = 0
for bl in raw_lines:
    offsets.append(pos)
    pos += len(bl)

HEADER_RE = re.compile(
    r'^### (\S+) (?:—|--) (\S+) (?:→|->) (\S+) (?:—|--) (.+)$'
)
SIG_START_LINE = b"<!-- SIG v1"
SIG_END_LINE = b"-->"

def decode(bl):
    return bl.decode("utf-8", errors="replace")

header_idxs = []
for i, bl in enumerate(raw_lines):
    if bl.startswith(b"### ") and HEADER_RE.match(decode(bl).rstrip("\n")):
        header_idxs.append(i)

start_idx = 0
# ROUND-12 (2026-08-10, Cipher HIGH): --tail's raw-line start_idx is deliberately
# NOT applied when --tail-verified is in play — that would reintroduce the exact
# raw-line eviction gap --tail-verified exists to close (an attacker could still
# use unsigned padding to push start_idx itself past a real VERIFIED header
# before classification ever runs). --since-line stays a valid structural floor
# either way; it restricts by document position, not by a count an attacker's
# unsigned padding can inflate.
if tail_n > 0:
    start_idx = max(start_idx, n_lines - tail_n)
if since_line > 0:
    start_idx = max(start_idx, since_line)

relevant = [i for i in header_idxs if i >= start_idx]

if not allowed_signers_present:
    print(f"NOTE [coord-verify]: {allowed_signers} not found — every signed message below will read as UNKNOWN-SIGNER until it exists.")

def match_principal(frm):
    """True iff allowed_signers has an entry for frm. Deterministic
    (ssh-keygen -Y match-principals), never stderr-text-sniffed."""
    if not allowed_signers_present:
        return False
    proc = subprocess.run(
        ["ssh-keygen", "-Y", "match-principals", "-I", frm, "-f", allowed_signers],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    return proc.returncode == 0

def body_text_for_sentinel(hi):
    """Best-effort body text for the UNVERIFIED exemption's sentinel search
    only — never used to define a cryptographic boundary, so the old
    next-header heuristic is fine here (imprecision has no security
    consequence, it only affects whether the sentinel exemption fires)."""
    j = hi + 1
    parts = []
    while j < n_lines and j not in header_idxs_set:
        if raw_lines[j].rstrip(b"\n") == SIG_START_LINE:
            break
        parts.append(decode(raw_lines[j]))
        j += 1
    return "".join(parts)

def body_starts_with_sentinel(hi):
    """True iff this header's body's first substantive (non-blank) line is
    exactly the SIGNING-FAILED sentinel — not merely present anywhere in
    the body (2026-08-09 round-2 tightening; see EXEMPTIONS (c) above).
    Matches exactly what heartbeat.sh emits at both its call sites: a blank
    line after the header, then the sentinel as the next line."""
    for line in body_text_for_sentinel(hi).split("\n"):
        if line.strip() == "":
            continue
        return line.startswith("[SIGNING-FAILED —")
    return False

header_idxs_set = set(header_idxs)

def _self_consistent_span(hi):
    """True iff header hi has ITS OWN self-consistent bytes:N field pointing
    at a real SIG block — i.e. is independently, unambiguously a complete
    signed message of its own, with no guessing/fallback involved. Used only
    by find_span's self-inconsistency fallback below to tell "a genuinely
    separate, independently-signed later message sits between hi and the
    found SIG block" (must NOT be swallowed) apart from "the only thing
    between hi and its SIG block is a header-shaped line quoted inside hi's
    OWN body" (safe to fall through past — that quoted line has no
    self-consistent span of its own, since the nearest SIG block it finds is
    really hi's, whose bytes:N field is exactly the thing that's already
    known to be wrong here)."""
    H = offsets[hi]
    sig_line_idx = None
    for k in range(hi + 1, n_lines):
        if raw_lines[k].rstrip(b"\n") == SIG_START_LINE:
            sig_line_idx = k
            break
    if sig_line_idx is None:
        return False
    S = offsets[sig_line_idx]
    bytes_field = None
    close_idx = None
    k = sig_line_idx + 1
    while k < n_lines:
        if raw_lines[k].rstrip(b"\n") == SIG_END_LINE:
            close_idx = k
            break
        dl = decode(raw_lines[k])
        if dl.startswith("bytes:"):
            bytes_field = dl.split(":", 1)[1].strip()
        k += 1
    if close_idx is None or bytes_field is None:
        return False
    try:
        n_claimed = int(bytes_field)
    except ValueError:
        return False
    return H + n_claimed == S

def find_span(hi):
    """For header at line index hi, locate its SIG block (if any) and
    determine the exact byte/line span this message occupies. SHARED by the
    main verify loop and --find-boundary so the two can never disagree about
    where a message ends — that agreement is exactly what makes
    --find-boundary's snap-to-header-boundary guarantee actually hold.

    Returns a dict:
      end_line       line index one past this message's own content (the
                      SIG block's closing '-->' line + 1 if a SIG block was
                      unambiguously associated, else hi + 1 — the latter is
                      NOT a claim about how far an unsigned message's body
                      actually extends, only "nothing beyond here is known
                      to belong to this header").
      signed_region  exact bytes to verify, or None if unsigned/unassociated.
      sig_pem        the PEM signature block text, or None.
      bytes_note     advisory string, "" if bytes:N was self-consistent.
    """
    H = offsets[hi]

    # Find the first SIG-block-start line at or after this header (unbounded
    # search) — the "bytes: N" self-consistency check below rejects any
    # accidental/attacker association with a SIG block that isn't actually
    # this header's own, so an unbounded search is safe: it cannot cause a
    # message to be mis-verified against a later, unrelated message's
    # signature.
    sig_line_idx = None
    for k in range(hi + 1, n_lines):
        if raw_lines[k].rstrip(b"\n") == SIG_START_LINE:
            sig_line_idx = k
            break

    if sig_line_idx is None:
        return {"end_line": hi + 1, "signed_region": None, "sig_pem": None, "bytes_note": ""}

    S = offsets[sig_line_idx]
    bytes_field = None
    sig_pem_lines = []
    in_pem = False
    close_idx = None
    k = sig_line_idx + 1
    while k < n_lines:
        dl = decode(raw_lines[k])
        if raw_lines[k].rstrip(b"\n") == SIG_END_LINE:
            close_idx = k
            break
        if dl.startswith("bytes:"):
            bytes_field = dl.split(":", 1)[1].strip()
        if "BEGIN SSH SIGNATURE" in dl:
            in_pem = True
        if in_pem:
            sig_pem_lines.append(dl)
        if "END SSH SIGNATURE" in dl:
            in_pem = False
        k += 1

    if close_idx is None:
        return {"end_line": hi + 1, "signed_region": None, "sig_pem": None, "bytes_note": ""}

    n_claimed = None
    if bytes_field is not None:
        try:
            n_claimed = int(bytes_field)
        except ValueError:
            n_claimed = None

    self_consistent = n_claimed is not None and H + n_claimed == S
    # A tamper that changes the BODY'S BYTE LENGTH (the realistic case — an
    # attacker rarely preserves exact length) breaks the bytes:N
    # self-consistency check above even though the SIG block found above is
    # still the nearest one at-or-after this header. Round-2 hardening
    # (2026-08-09, Cipher HIGH, live-demonstrated): the previous code
    # additionally required the association to be "unambiguous" (no other
    # header-shaped line — real OR body-quoted, the two are indistinguishable
    # by a bare per-line scan — sitting between this header and the SIG
    # block) before falling through to verify against the actual bytes — and
    # simply gave up (UNVERIFIED, exemptible) whenever ANY such line existed
    # in between, even though the code's own header comment claimed it
    # always fell through. Cipher live-signed a real ASSIGN-IDENTITY reply
    # whose body legitimately quoted a prior header, MITM-tampered the
    # embedded pubkey (breaking self-consistency), and got
    # ⚠️ UNVERIFIED [exempt] instead of ❌ INVALID — silently downgrading a
    # real tamper signal.
    #
    # Fix: fall through to verifying against the actual bytes (raw[H:S])
    # UNLESS a genuinely separate, independently self-consistent later
    # message sits between this header and the found SIG block — in that
    # case that later message legitimately owns the SIG block (or one past
    # it) and swallowing it here would hide it from verification entirely
    # (a real regression, not a security fix — this is not a hypothetical:
    # the ordinary "unsigned exempt message immediately followed by any
    # normal signed message" shape, ubiquitous in real traffic, hits this
    # exact path). _self_consistent_span distinguishes the two: a body-
    # quoted pseudo-header has no self-consistent span of its own (the
    # nearest SIG block it finds is really this header's, whose bytes:N is
    # exactly the thing already known to be wrong here), so it never
    # triggers the decline path — only a genuinely independent later message
    # does. Once declined for that reason, ssh-keygen's own crypto check is
    # never even reached for hi on this call; it is left UNVERIFIED, and
    # consumed_walk (below) hands the later message its own, independent
    # find_span call.
    if not self_consistent and any(
        hi < other < sig_line_idx and _self_consistent_span(other)
        for other in header_idxs
    ):
        return {"end_line": hi + 1, "signed_region": None, "sig_pem": None, "bytes_note": ""}

    bytes_note = ""
    if self_consistent:
        signed_region = raw[H:H + n_claimed]
    else:
        signed_region = raw[H:S]
        bytes_note = " [bytes: field mismatch — verified against actual content instead]"

    return {
        "end_line": close_idx + 1,
        "signed_region": signed_region,
        "sig_pem": "".join(sig_pem_lines),
        "bytes_note": bytes_note,
    }

def consumed_walk(header_list):
    """Walk header_list (must be sorted ascending) in order, yielding
    (header_idx, span) for each header NOT already swallowed by a prior
    span in THIS walk — i.e. skips any header-shaped line embedded inside
    an earlier message's own signed/unsigned content, exactly like the main
    verify loop's consumption logic. SHARED between the main verify loop
    and --find-boundary (2026-08-09 round-2, Rook) so the two can never
    disagree about which lines are real message headers: before this fix,
    --find-boundary scanned header_idxs directly and could pick a
    body-quoted header as its anchor, reintroducing the exact misparse
    bug the bytes: field exists to kill, just in this one code path."""
    idx = 0
    while idx < len(header_list):
        hi = header_list[idx]
        span = find_span(hi)
        yield hi, span
        idx += 1
        while idx < len(header_list) and header_list[idx] < span["end_line"]:
            idx += 1

if find_boundary_n is not None:
    # --find-boundary: structural-only pass, no crypto — used by
    # coordination-precommit-hook.sh to snap a trusted lower-bound offset to
    # a safe --since-line before ever calling this script for real. See
    # usage text above for the contract. Walks the FULL header_idxs list
    # (not tail/since-line-restricted) through consumed_walk so a
    # body-quoted header can never be chosen as the anchor.
    N = find_boundary_n
    real_headers = list(consumed_walk(header_idxs))
    if not real_headers:
        print("NOCOVER")
        sys.exit(1)
    anchor_hi = None
    anchor_span = None
    for hi, span in real_headers:
        if offsets[hi] <= N:
            anchor_hi = hi
            anchor_span = span
        else:
            break
    if anchor_hi is None:
        if N == 0:
            print(0)
            sys.exit(0)
        print("NOCOVER")
        sys.exit(1)
    anchor_end_byte = offsets[anchor_span["end_line"]] if anchor_span["end_line"] < n_lines else len(raw)
    if N < anchor_end_byte:
        # N falls inside this message's own span — snap back to its header
        # so the message is fully re-covered, never silently skipped.
        print(anchor_hi)
    else:
        nxt = next((hi for hi, _ in real_headers if hi > anchor_hi and offsets[hi] >= N), None)
        print(nxt if nxt is not None else n_lines)
    sys.exit(0)

results = []
for hi, span in consumed_walk(relevant):
    header_line = decode(raw_lines[hi])
    m = HEADER_RE.match(header_line.rstrip("\n"))
    ts, frm, to, tag = m.group(1), m.group(2), m.group(3), m.group(4)

    verdict = None
    note = ""

    if span["signed_region"] is not None:
        signed_region = span["signed_region"]
        sig_pem = span["sig_pem"]
        bytes_note = span["bytes_note"]

        if not sig_pem.strip():
            verdict = "INVALID"
            note = " [SIG block present but no PEM signature found]" + bytes_note
        elif not match_principal(frm):
            verdict = "UNKNOWN-SIGNER"
            note = bytes_note
        else:
            sig_fd, sig_path = tempfile.mkstemp(suffix=".sig")
            try:
                with os.fdopen(sig_fd, "w") as sf:
                    sf.write(sig_pem)
                proc = subprocess.run(
                    ["ssh-keygen", "-Y", "verify",
                     "-f", allowed_signers,
                     "-I", frm,
                     "-n", "samantha-coord",
                     "-s", sig_path],
                    input=signed_region, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                )
                verdict = "VERIFIED" if proc.returncode == 0 else "INVALID"
                note = bytes_note
            finally:
                os.unlink(sig_path)

        # STRUCTURAL CHECK, signed path: a message that verifies
        # cryptographically but claims a FROM different from the file it
        # sits in is downgraded VERIFIED -> INVALID (see header comment).
        if verdict == "VERIFIED" and frm != file_basename:
            verdict = "INVALID"
            note = f" [FROM/file mismatch: claims FROM={frm} but resides in {file_basename}.md — single-writer-per-file violation]" + bytes_note

        results.append((verdict, frm, ts, tag, False, note, signed_region if verdict == "VERIFIED" else None))
    else:
        verdict = "UNVERIFIED"
        # STRUCTURAL CHECK, unsigned path: FROM == basename(file) is
        # required UNCONDITIONALLY before ANY exemption below is considered
        # (see header comment for why this declines the exemption rather
        # than escalating to INVALID the way the signed path above does).
        exempt = False
        if frm == file_basename:
            if frm.startswith("pending-") and tag.startswith("🛰️ HEADS-UP"):
                exempt = True
            elif frm == "orchestrator" and tag.startswith("🤝 ASSIGN-IDENTITY") and to.startswith("pending-"):
                exempt = True
            elif tag.startswith("⚠️ ") and body_starts_with_sentinel(hi):
                exempt = True
        results.append((verdict, frm, ts, tag, exempt, "", None))

# ROUND-12 (2026-08-10, Cipher HIGH): --tail-verified's window boundary is
# chosen HERE, from `results` — every header in `relevant` has already been
# fully classified above — never from a raw line count computed before
# classification (that was the round-12 gap in plain --tail: unsigned
# padding, including all three --strict exemption shapes, counts toward a
# raw-line budget it should never be able to spend). Walk `results`
# (ascending file-order, same order coord-verify.sh has always printed in)
# backward from EOF, counting only VERIFIED spans, until N are found or the
# start is reached; UNVERIFIED/exempt/UNKNOWN-SIGNER/INVALID spans in
# between are skipped "for free" — they never consume any of the N budget,
# so no amount of unsigned padding can push a real VERIFIED span out of the
# window. If fewer than N VERIFIED spans exist at all, the boundary is the
# start of `relevant` — i.e. everything classified above is kept, same
# fail-open-on-absent-data posture --tail already has.
#
# Accepted characteristic, not a bug (2026-08-10, per the human, on review
# of a round-13 finding): classifying `relevant` above has unbounded
# worst-case cost relative to file size — no cap, since capping naively
# (stopping the classify pass early) would reopen this exact masking bug
# for whatever content falls past the cap. A very large or heavily-padded
# peer mailbox file makes this proportionally slower. Not fixed: this
# framework runs on the human's own private infrastructure between their
# own agent sessions, not a public/multi-tenant service — an actor who
# already has coord-dir write access to deliberately pad a peer's file
# purely to slow down a git commit has far more damaging options available
# at that point; see README.md § Protocol Version Handshake, Part D.
if tail_verified_n > 0:
    _tv_boundary = 0
    _tv_seen = 0
    for _tv_idx in range(len(results) - 1, -1, -1):
        if results[_tv_idx][0] == "VERIFIED":
            _tv_seen += 1
            if _tv_seen >= tail_verified_n:
                _tv_boundary = _tv_idx
                break
    results = results[_tv_boundary:]

counts = {"VERIFIED": 0, "UNVERIFIED": 0, "INVALID": 0, "UNKNOWN-SIGNER": 0}
fail = False
for verdict, frm, ts, tag, exempt, note, signed_region in results:
    counts[verdict] += 1
    if verdict == "VERIFIED":
        print(f"✅ VERIFIED {frm} {ts}{note}")
        # ROUND-10 (2026-08-10, Cipher HIGH): scan ONLY signed_region — the
        # exact bytes ssh-keygen -Y verify just checked above — never the
        # raw file. Content appended after this message's own SIG block (or
        # anywhere else outside signed_region) structurally cannot produce a
        # FIELD-VERIFIED line, no matter how it's shaped or where it sits.
        if extract_field_re is not None and signed_region is not None:
            for line in signed_region.decode("utf-8", errors="replace").split("\n"):
                fm = extract_field_re.match(line.rstrip("\r"))
                if fm:
                    print(f"FIELD-VERIFIED {frm} {ts} {fm.group(1)}")
                    break
    elif verdict == "UNVERIFIED":
        exempt_note = " [exempt]" if exempt else ""
        print(f"⚠️ UNVERIFIED (no signature) {frm} {ts}{exempt_note}")
        if strict and not exempt:
            fail = True
    elif verdict == "UNKNOWN-SIGNER":
        print(f"❓ UNKNOWN-SIGNER (identity not enrolled / allowed_signers stale) {frm} {ts} — remedy: enroll this identity or pull current allowed_signers")
        if strict:
            fail = True
    else:
        print(f"❌ INVALID (signature present, verification FAILED) {frm} {ts}{note}")
        fail = True

print(f"SUMMARY: {counts['VERIFIED']} verified, {counts['UNVERIFIED']} unverified, "
      f"{counts['UNKNOWN-SIGNER']} unknown-signer, {counts['INVALID']} invalid "
      f"({len(results)} total message(s) scanned)")

sys.exit(1 if fail else 0)
PY
