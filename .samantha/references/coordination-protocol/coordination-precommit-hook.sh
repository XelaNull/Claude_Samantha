#!/usr/bin/env bash
# coordination-precommit-hook.sh — PreToolUse hook for git commit-landing and push verbs.
#
# PURPOSE:
#   Enforces coordination hygiene before any git commit-landing verb (commit, merge,
#   cherry-pick, rebase, am, revert, pull) or push in a dual-mode session:
#   1. MAILBOX-READ GATE: Check that no unread message is addressed to this instance.
#      (Rule 4: read your mailbox before any commit/push/deploy.)
#   2. DANGEROUS-VERB WARNING: Warn if `git add -A` or `git add .` was used in a shared tree.
#      (Rule 1: never stage everything in a shared tree.)
#   3. SECRET-SCAN: Scan the staged diff for obvious secrets (API keys, tokens, passwords).
#      (Rule 5: no secrets in any shared artifact.)
#
# WIRING:
#   Add to Claude Code's settings as a PreToolUse hook on Bash. In .claude/settings.json:
#
#     {
#       "hooks": {
#         "PreToolUse": [{
#           "matcher": "Bash",
#           "hooks": [{
#             "type": "command",
#             "command": "<coord-dir>/coordination-precommit-hook.sh <coord-dir> <my-identity>"
#           }]
#         }]
#       }
#     }
#
#   The hook fires for every Bash tool call. The script self-filters: it only runs its checks
#   if the Bash command matches a commit-landing verb (commit, merge, cherry-pick, rebase,
#   am, revert, pull) or a push (see `_is_commit_landing_cmd`/`_is_push_cmd` below). This is
#   a Bash-command-TEXT matcher, not a real git hook — see that function's header comment
#   for the stated ceiling (doesn't protect a human typing git directly in a terminal, can
#   always miss some future/uncommon verb).
#
# USAGE (standalone):
#   ./coordination-precommit-hook.sh <coord-dir> <my-identity>
#
# EXIT CODES:
#   0  All checks passed (or positively not a commit/push) — allow.
#   1  A check failed — the hook blocks the Bash call and surfaces the output to Claude.
#
# CUSTOMIZATION:
#   Set COORD_DIR and MY_ID below, or pass as arguments.
#   Adjust SECRET_PATTERNS for the project's known secret formats.

set -euo pipefail

# ── configuration ─────────────────────────────────────────────────────────────

COORD_DIR="${1:-}"
MY_ID="${2:-}"
_HOOK_HOME="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
# PROTOCOL 1.4.0: SSH signature verification over newly-read mail (see check 1b below).
COORD_VERIFY_SH="$_HOOK_HOME/coord-verify.sh"
# PROTOCOL 1.4.0 remote-seat extension (2026-08-09, real gap 2): shared
# fetch-a-buffer -> name-it-correctly -> verify-it helper, same one
# coord-monitor.sh's remote channel uses (see check 1c below) — one
# definition so the two can never drift on how a remote buffer is verified.
COORD_REMOTE_VERIFY_SH="$_HOOK_HOME/coord-remote-verify.sh"
if [[ -f "$COORD_REMOTE_VERIFY_SH" ]]; then
  # shellcheck source=coord-remote-verify.sh
  . "$COORD_REMOTE_VERIFY_SH"
fi
# PROTOCOL 1.3.0: same-project peer watch-set helpers, shared with coord-monitor.sh
# (item 9, 2026-08-09: this hook's own inbox set was still 1.2.x-shaped — spoke-only-
# watches-orchestrator.md — even though spokes have watched same-project peer outboxes
# since 1.3.0; reusing these helpers instead of re-deriving the rule keeps the two from
# drifting again).
COORD_ADDRESS_FILTER_SH="$_HOOK_HOME/coord-address-filter.sh"
if [[ -f "$COORD_ADDRESS_FILTER_SH" ]]; then
  # shellcheck source=coord-address-filter.sh
  . "$COORD_ADDRESS_FILTER_SH"
fi
# PROTOCOL 1.4.0: receipt read/write helpers, shared with coord-monitor.sh so
# the two can never disagree on the receipt format (item 1, 2026-08-09).
COORD_RECEIPT_SH="$_HOOK_HOME/coord-receipt.sh"
if [[ -f "$COORD_RECEIPT_SH" ]]; then
  # shellcheck source=coord-receipt.sh
  . "$COORD_RECEIPT_SH"
fi
# PROTOCOL 1.5.0 §3.5 Part D: presence_get (for reading a peer's last-known
# protocol_version) and this seat's own PROTOCOL_VERSION stamp — see check 1d
# below (protocol-version MAJOR mismatch gate).
COORD_PRESENCE_SH="$_HOOK_HOME/coord-presence.sh"
if [[ -f "$COORD_PRESENCE_SH" ]]; then
  # shellcheck source=coord-presence.sh
  . "$COORD_PRESENCE_SH"
fi
PROTOCOL_VERSION="unknown"
if [[ -f "$_HOOK_HOME/PROTOCOL-VERSION" ]]; then
  # shellcheck source=PROTOCOL-VERSION
  . "$_HOOK_HOME/PROTOCOL-VERSION"
fi
# The tool input arrives as JSON on STDIN under the current Claude Code hook
# protocol ({"tool_name":...,"tool_input":{"command":...}} or a bare tool_input
# object). The old CLAUDE_TOOL_INPUT env var is honored as a legacy fallback.
# A standalone tty invocation (no piped stdin, no env var) runs all checks.
BASH_CMD=""
if [ ! -t 0 ]; then
  BASH_CMD=$(cat 2>/dev/null || true)
fi
if [[ -z "$BASH_CMD" ]]; then
  BASH_CMD="${CLAUDE_TOOL_INPUT:-}"
fi

# ── Cursor beforeShellExecution contract ───────────────────────────────
# STDOUT must carry exactly ONE JSON permission object — nothing else. Every
# human-readable echo/printf below therefore goes to STDERR (still surfaced to
# the model + the Hooks output channel). Redirect real stdout to fd3 and point
# fd1 -> stderr; emit() is the ONLY writer to fd3 (the decision).
#   exit 0 + {"permission":"allow"}   -> Cursor proceeds with the command
#   exit 2 + {"permission":"deny",..} -> Cursor blocks it (belt-and-suspenders)
# WARNING: if stdout is ever left empty or non-JSON, Cursor FAIL-OPENS
# (auto-approves), silently disabling the secret-scan + mailbox gate.
exec 3>&1 1>&2
emit() { printf '%s\n' "$1" >&3; }

# CRITICAL: identity charset assertion — MY_ID is interpolated raw into grep -E patterns
# (_addr_pattern). A metachar in the id (e.g. "feature/auth[2]", ".*") makes grep
# error or silently mis-behave: gate bypass (exit 0) or permanent block (DoS).
if [[ -n "$MY_ID" && ! "$MY_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR [pre-commit hook]: identity '${MY_ID}' contains characters outside [A-Za-z0-9._-]." >&2
  echo "Identity strings are interpolated into grep -E patterns; metacharacters cause silent mis-behaviour." >&2
  echo "Rename to letters, digits, dots, underscores, and dashes (e.g. 'impl-alpha', not 'feature/auth[2]')." >&2
  emit '{"permission":"deny","user_message":"pre-commit hook: identity charset invalid"}'
  exit 2
fi

# Secret patterns to scan for in staged diffs.
# Uses POSIX ERE compatible with both GNU grep and macOS BSD grep.
# Do NOT use \s (use [[:space:]]) or \x27 (use a literal ') — BSD grep rejects them.
# Add project-specific patterns below the canonical set.
#
# CLASSES COVERED: AWS, OpenAI, Anthropic, GitHub (classic + fine-grained), Slack,
#   Stripe live keys, GCP API keys, JWTs, database DSNs with embedded credentials,
#   generic credential assignments, PEM private key markers.
#
# CLASSES NOT COVERED — extend SECRET_PATTERNS for your project:
#   Azure SAS tokens / connection strings (format varies; no stable prefix)
#   HashiCorp Vault tokens (hvs.*, b.* — high false-positive risk without context)
#   SSH private keys in .pub or known_hosts form (only BEGIN markers are caught above)
#   Docker registry credentials / .dockerconfigjson blobs
#   .env KEY=VALUE catch-all (too broad without project-specific key names)
#   Project-specific internal token formats
SECRET_PATTERNS=(
  # AWS access key IDs
  'AKIA[0-9A-Z]{16}'

  # OpenAI API keys
  'sk-[a-zA-Z0-9_-]{32,}'

  # Anthropic API keys
  'sk-ant-[a-zA-Z0-9_-]{80,}'

  # GitHub classic personal access tokens
  'ghp_[a-zA-Z0-9]{36}'

  # GitHub fine-grained personal access tokens
  'github_pat_[A-Za-z0-9_]{82}'

  # Slack tokens
  'xox[baprs]-[a-zA-Z0-9]+'

  # Stripe live secret keys
  'sk_live_[A-Za-z0-9]{24}'

  # GCP API keys
  'AIza[0-9A-Za-z_-]{35}'

  # JSON Web Tokens (header.payload.signature)
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'

  # Database DSNs with embedded credentials
  '(postgres(ql)?|mysql|mongodb(\+srv)?)://[^[:space:]]*:[^[:space:]@]*@'

  # Generic credential assignments (quoted and unquoted values)
  '(token|secret|password|api[_-]?key)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}'

  # PEM private key markers
  'private_key'
  'BEGIN RSA PRIVATE'
  'BEGIN EC PRIVATE'
)

# F3 self-test: verify each pattern compiles on this grep implementation.
# BSD grep (macOS) exits 2 (not 1) when a pattern fails to compile — a pattern that
# doesn't compile produces false negatives (secrets pass through unseen).
_bad_patterns=()
for _p in "${SECRET_PATTERNS[@]}"; do
  _rc=0
  { printf '' | grep -qE "$_p"; } 2>/dev/null || _rc=$?
  if [[ $_rc -eq 2 ]]; then _bad_patterns+=("$_p"); fi
done
if [[ ${#_bad_patterns[@]} -gt 0 ]]; then
  printf 'WARN [secret-scan self-test]: %d pattern(s) failed to compile on this grep — false negatives possible:\n' \
    "${#_bad_patterns[@]}" >&2
  printf '  %s\n' "${_bad_patterns[@]}" >&2
fi
unset _bad_patterns _p _rc

# ── self-filter: only run on a commit-landing or push verb ────────────────────
#
# SECURITY: fail-closed on ambiguity (N posture).
# If the command cannot be determined (unparseable JSON, missing parsers), all three
# checks run rather than silently passing. exit 0 only when the command is positively
# identified as NOT a commit-landing/push verb. Ambiguity → checks run; positive
# non-commit → exit 0.
#
# VERB COVERAGE (round-3, item 1, 2026-08-09 — Cipher CRITICAL, human-directed
# fix): this used to gate on a literal `*"git commit"*` / `*"git push"*`
# substring match against the raw Bash command text. Cipher live-confirmed
# `git merge --no-edit`, `git cherry-pick <sha>`, `git rebase --continue`, and
# `git am <mbox>` all land a commit object and all return `{"permission":
# "allow"}` with ZERO checks run — no mailbox-read gate, no git-anchored
# sig-verify, no allowed_signers write-gate, no secret-scan. These are
# ordinary, everyday commit-landing verbs, not exotic plumbing; this fully
# defeated the round-2 hardening on both the git-anchor and the
# allowed_signers gate with no `--no-verify` or history rewrite needed.
# `_is_commit_landing_cmd`/`_is_push_cmd` below are the ONE shared classifier
# every gate in this file uses (the self-filter here, check 4's canon-doc
# advisory, check 6's allowed_signers gate) — a single definition so they can
# never drift apart on what counts as "this lands a commit".
#
# CEILING (matches this file's/README's established ceiling voice — the
# allowed_signers direct-filesystem-write admission, the gated-push "does not
# stop a determined liar" paragraph): this is a Claude-Code-session-scoped
# Bash COMMAND-TEXT matcher, not equivalent to a real git hook. It does not
# protect a human typing git commands directly in a terminal (this hook only
# fires on a Bash tool call inside a hooked session) and a text matcher can
# always be blindsided by some future/uncommon verb, alias, or wrapper script
# this list doesn't enumerate — over time this needs its own review as git
# usage patterns in this project evolve, matching README's own admission for
# the allowed_signers gate. A durable fix — real `.git/hooks/pre-commit` +
# `pre-merge-commit` hooks, enforced by git itself regardless of tool/process
# — is out of scope for 1.4.0; flagged as a future item (see README.md
# `advanced/REMOTE-SEATS.md` for the same "flagged, not solved this round"
# treatment of a comparably-scoped gap).
_is_commit_landing_cmd() {
  [[ "$1" =~ (^|[^A-Za-z0-9_-])git[[:space:]]+(commit|merge|cherry-pick|rebase|am|revert|pull)([^A-Za-z0-9_-]|$) ]]
}
_is_push_cmd() {
  [[ "$1" == *"git push"* ]]
}

extract_bash_command() {
  # Extract the "command" field from Claude tool input JSON.
  # Primary:  python3 — full JSON parser; handles escaped quotes, Unicode, etc.
  # Fallback: perl — regex-based; handles \" in values (grep/sed `[^"]*` stops at an
  #           escaped quote, silently missing "git commit -m \"msg\"" on python3-less hosts).
  # Returns 0 (prints command) on success, 1 (prints nothing) on failure.
  local json="$1"
  local result
  if command -v python3 >/dev/null 2>&1; then
    result=$(printf '%s' "$json" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  # Hook-protocol envelope: {'tool_name':..., 'tool_input':{'command':...}}
  # Legacy / bare tool_input: {'command': ...}
  ti = d.get('tool_input', d)
  print(ti.get('command', '') if isinstance(ti, dict) else '')
  sys.exit(0)
except Exception:
  sys.exit(1)
" 2>/dev/null) && { printf '%s' "$result"; return 0; }
  fi
  if command -v perl >/dev/null 2>&1; then
    result=$(printf '%s' "$json" | \
      perl -ne 'if(/"command"\s*:\s*"((?:[^"\\]|\\.)*)"/){print $1; exit 0}' 2>/dev/null)
    if [[ -n "$result" ]]; then printf '%s' "$result"; return 0; fi
  fi
  return 1
}

if [[ -n "$BASH_CMD" ]]; then
  cmd_field=""
  if ! cmd_field=$(extract_bash_command "$BASH_CMD") || [[ -z "$cmd_field" ]]; then
    # Could not determine the command (parse failed, unavailable parsers, or empty result).
    # N posture: run all checks rather than silently allowing. exit 0 only on positive
    # identification as not-a-commit-landing/push verb — never on ambiguity (including
    # missing parsers).
    # Round-2 (item 5): every downstream check gates on `_is_commit_landing_cmd`/
    # `_is_push_cmd` against $cmd_field — the placeholder text must therefore
    # actually match both classifiers (contain "git commit" and "git push"
    # literally), or checks 5 and 6 (allowed_signers gate) silently no-op on
    # ambiguity despite this comment's own stated intent, exactly the failure
    # mode check 1 above already avoids for the mailbox-read gate.
    echo "WARN [pre-commit hook]: Could not extract command from CLAUDE_TOOL_INPUT — running checks as precaution." >&2
    cmd_field="(command unknown — checks running as precaution for git commit / git push)"
  elif ! _is_commit_landing_cmd "$cmd_field" && ! _is_push_cmd "$cmd_field"; then
    emit '{"permission":"allow"}'; exit 0  # Positively not a commit-landing/push verb — allow.
  fi
else
  # Standalone invocation (no CLAUDE_TOOL_INPUT): run all checks.
  cmd_field="git commit (standalone invocation)"
fi

echo "[pre-commit hook] Checking coordination hygiene before: $cmd_field"
FAIL=0

# ── check 1: mailbox-read gate ────────────────────────────────────────────────
#
# Per-instance receipt tracks how far into each inbox file this agent has
# acknowledged. File: <coord-dir>/.watch-state/<id>/<inbox-file>.size — this is
# the SAME file coord-monitor.sh persists its read-time state to on every wake
# (auto-maintained by the watcher, no manual step, no drift between watcher
# state and hook state). Bytes after the acknowledged offset are "unread". We
# block if any contain a message header addressed to MY_ID OR the broadcast
# token ALL.
#
# No receipt on first run → auto-initialize at current EOF, so pre-existing
# sibling traffic never blocks a fresh implementer. The watcher auto-advances
# the receipt on every wake; the hook reads it directly. In standalone mode
# (no active watcher), initialize manually — see the suggestion printed below.
#
# Why a receipt file, not "last line I posted in orchestrator.md":
#   - Implementers NEVER post into orchestrator.md (they post in their own file).
#     The old grep-for-my-sent-line heuristic always returned 0 for implementers,
#     marking every message as unread → permanent block on first commit (deadlock).
#   - The receipt tracks what the agent has actually acknowledged — no
#     inference, no deadlock, no dependency on the watcher being armed first.
#   - Scanning for "→ ALL" in the delta catches broadcast DEPLOY-WINDOW signals
#     that the old pattern (→ MY_ID only) silently missed.
#
# RECEIPT-FORGERY HARDENING (item 1, 2026-08-09; scope narrowed round-2,
# 2026-08-09): the receipt used to be a bare integer — anything (a bug, a
# stray `echo 99999 > receipt`, a hand-edit) could set it past real content
# and silently disable the gate forever, with nothing to detect the forgery.
# The receipt is now TWO fields (offset=<n> / verified_sha256=<hash of the
# file's first n bytes>), and a reader recomputes and rejects on mismatch —
# see coord-receipt.sh's header comment for the exact contract. THIS RECEIPT
# IS USED ONLY FOR THE MAILBOX-READ NUDGE ABOVE (Rule 4: "have you read your
# new mail"), which pre-dates this amendment and never claimed to be a
# security boundary. Round-2 (Cipher): the receipt's hash-binding does not
# actually add security for anything MORE sensitive than that nudge — sha256
# is not a keyed MAC, so anything with write access to inject unsigned/
# tampered mail also has read access to compute a matching hash and
# self-write a forged receipt using the exact same write_receipt helper an
# honest watcher uses. Full bypass, one extra `shasum` call. The check 1b
# --strict signature hard-block below therefore does NOT use this receipt at
# all — see its own comment for what it anchors on instead.
if [[ -n "$COORD_DIR" && -n "$MY_ID" ]]; then
  # Inbox selection follows the STAR topology: the orchestrator's inbox is every
  # PEER file in the coord-dir; a spoke's inbox is orchestrator.md PLUS any
  # same-project peer impl-*.md (PROTOCOL 1.3.0 sibling awareness — item 9,
  # 2026-08-09: this used to be orchestrator.md only, silently missing the
  # peer-outbox traffic coord-monitor.sh's `watched()` has gated commits on
  # since 1.3.0; same protocol_resolve_project/protocol_project_of_identity
  # helpers as that function, so the two watch sets cannot drift apart again).
  # Never gate on your OWN outbox — heartbeat/dead-man alerts posted there
  # (→ ALL) would self-trigger the gate on every call forever.
  INBOX_FILES=()
  if [[ "$MY_ID" == "orchestrator" ]]; then
    # ROUND-6 (2026-08-09, Rook): this was the 4TH independently-maintained
    # "is this a seat outbox" exclusion list (round 5 unified the other
    # three — coord-monitor.sh's local watched(), its remote sweep, and this
    # SAME hook's remote check 1c — but missed this one, which predates the
    # remote extension). It was missing PROJECTS.md and queue-*.md — exactly
    # the multi-project topology this pack ships a template for
    # (QUEUE-template.md). An ordinary broadcast posted into queue-alpha.md
    # on a normal multi-project hub — no attacker — got the structural
    # FROM==basename(file) check applied incorrectly and permanently
    # hard-blocked the hub. Now uses the SAME shared predicate as the other
    # three sites. Falls back to the old (now-corrected) blocklist only if
    # coord-address-filter.sh somehow isn't sourced — same conservative
    # posture as this file already uses elsewhere, never "include everything
    # unfiltered" as the degrade path.
    if command -v coord_is_seat_outbox_basename >/dev/null 2>&1; then
      while IFS= read -r _f; do
        _b=$(basename "$_f")
        [[ "$_b" == "orchestrator.md" ]] && continue
        coord_is_seat_outbox_basename "$_b" || continue
        INBOX_FILES+=("$_f")
      done < <(find "$COORD_DIR" -maxdepth 1 -name "*.md" 2>/dev/null | sort)
    else
      while IFS= read -r _f; do INBOX_FILES+=("$_f"); done < <(
        find "$COORD_DIR" -maxdepth 1 -name "*.md" ! -name "orchestrator.md" ! -name "QUEUE.md" ! -name "PROJECTS.md" ! -name "queue-*.md" ! -name "*.archive.md" 2>/dev/null | sort)
    fi
  else
    [[ -f "$COORD_DIR/orchestrator.md" ]] && INBOX_FILES+=("$COORD_DIR/orchestrator.md")
    if command -v protocol_resolve_project >/dev/null 2>&1; then
      _my_project=$(protocol_resolve_project "$MY_ID" "" "$COORD_DIR/$MY_ID.md" "$COORD_DIR")
      if [[ -n "$_my_project" ]]; then
        while IFS= read -r _f; do
          _b=$(basename "$_f" .md)
          [[ "$_b" == "$MY_ID" ]] && continue
          _p=$(protocol_project_of_identity "$_b")
          [[ "$_p" == "$_my_project" ]] && INBOX_FILES+=("$_f")
        done < <(find "$COORD_DIR" -maxdepth 1 -name "impl-*.md" 2>/dev/null | sort)
      fi
      unset _my_project
    fi
  fi
  if [[ ${#INBOX_FILES[@]} -eq 0 ]]; then
    echo "INFO [mailbox-read gate]: no inbox files for '$MY_ID' in $COORD_DIR — skipping (not in dual mode?)."
  fi

  # ROUND-6 (2026-08-09, Cipher — live-demonstrated bypass): COORD_REMOTE_SEAT_HOOK
  # is meant ONLY for a remote seat running this hook against its own
  # single-file bus-dir-as-coord-dir (§ Message Authenticity in
  # REMOTE-SEATS.md). Before round-6 nothing enforced that scope — the var
  # was honored uniformly across the whole check-1b loop below wherever it
  # was set. Cipher set it in a HUB's own environment (a real multi-peer
  # $COORD_DIR, one local peer posting a genuinely unsigned message) and got
  # the local signature check silently skipped for THAT peer too —
  # PRE-COMMIT HOOK: PASSED on content that should have hard-blocked. A
  # real remote seat's own bus dir has exactly three properties a real hub
  # coord-dir never has all three of at once: MY_ID is never "orchestrator"
  # there (remote seats are always spokes), its own INBOX_FILES resolves to
  # AT MOST one file (a possibly-mirrored orchestrator.md — a remote seat
  # never watches same-project siblings the way a hub-side spoke check would
  # enumerate multiple), and it structurally has NO local allowed_signers
  # (the single-canonical-trust-root design) — a real hub coord-dir always
  # has one. Require all three before honoring the var at all; otherwise
  # WARN and ignore it (fail toward running the real check, never toward
  # skipping it on an unproven claim).
  _REMOTE_SEAT_HOOK_REQUESTED=0
  [[ "${COORD_REMOTE_SEAT_HOOK:-0}" = 1 ]] && _REMOTE_SEAT_HOOK_REQUESTED=1
  _REMOTE_SEAT_HOOK_SCOPE_OK=0
  if [[ "$_REMOTE_SEAT_HOOK_REQUESTED" = 1 ]]; then
    if [[ "$MY_ID" != "orchestrator" ]] && [[ ${#INBOX_FILES[@]} -le 1 ]] && [[ ! -f "$COORD_DIR/allowed_signers" ]]; then
      _REMOTE_SEAT_HOOK_SCOPE_OK=1
    else
      echo "WARN [sig-verify]: COORD_REMOTE_SEAT_HOOK=1 is set but this does not look like a remote seat's own bus-dir-as-coord-dir (MY_ID='$MY_ID', ${#INBOX_FILES[@]} inbox file(s), local allowed_signers $([[ -f "$COORD_DIR/allowed_signers" ]] && echo present || echo absent)) — IGNORING it and running the local signature check normally. If this IS a legitimate remote seat, check that MY_ID isn't 'orchestrator', that this coord-dir has no local allowed_signers, and that its inbox resolves to at most one file." >&2
    fi
  fi
  unset _REMOTE_SEAT_HOOK_REQUESTED

  for ORCH_FILE in ${INBOX_FILES[@]+"${INBOX_FILES[@]}"}; do
    RECEIPT_FILE="$COORD_DIR/.watch-state/$MY_ID/$(basename "$ORCH_FILE").size"
    orch_sz=$(wc -c < "$ORCH_FILE" 2>/dev/null | tr -d ' ' || echo 0)

    if [[ ! -f "$RECEIPT_FILE" ]]; then
      # No receipt: first run for this identity. Auto-initialize at current EOF
      # so pre-existing sibling traffic does not block a fresh implementer.
      # All content before this point is treated as already acknowledged.
      mkdir -p "$(dirname "$RECEIPT_FILE")" 2>/dev/null || true
      chmod 700 "$(dirname "$RECEIPT_FILE")" 2>/dev/null || true
      if write_receipt "$RECEIPT_FILE" "$orch_sz" "$ORCH_FILE"; then
        echo "OK [mailbox-read gate]: first run — receipt initialized at ${orch_sz}B."
      else
        echo "WARN [mailbox-read gate]: could not compute receipt hash (no shasum/sha256sum on PATH) — receipt not written; every run will re-treat this file as unread until one is available." >&2
      fi
    else
      # F6 + item 1: read_receipt (coord-receipt.sh) validates shape AND binds
      # the receipt to the content it actually claims to cover — any forged,
      # corrupted, or malformed receipt falls back to 0 (full unread), loudly
      # (WARN/FAIL on stderr), never silently trusted.
      receipt_sz=$(read_receipt "$RECEIPT_FILE" "$ORCH_FILE")

      if [[ "$orch_sz" -gt "$receipt_sz" ]]; then
        # There is content after the receipt. Check if any of it is addressed to us.
        # ERE matches both canonical Unicode headers AND ASCII-typed equivalents:
        #   Arrow: → (U+2192) OR ->    Dash: — (U+2014) OR --
        # Anchored on TO field; cannot match the FROM position or another identity.
        # Matches "→ ALL" broadcasts — a missed DEPLOY-WINDOW OPEN should block commit.
        _addr_pattern="(→|->)[[:space:]]*(${MY_ID}|ALL)[[:space:]]*(—|--)"
        unread=$(tail -c +"$((receipt_sz + 1))" "$ORCH_FILE" 2>/dev/null | \
          grep -cE "$_addr_pattern" 2>/dev/null) || true
        unread="${unread:-0}"
        if [[ "$unread" -gt 0 ]]; then
          echo ""
          echo "FAIL [mailbox-read gate]: $unread unread message header(s) addressed to '$MY_ID' or 'ALL' in $ORCH_FILE"
          echo "(file: ${orch_sz}B; read to: ${receipt_sz}B; unread: $((orch_sz - receipt_sz))B)"
          echo "Read your mailbox before committing (Rule 4). Unread headers:"
          tail -c +"$((receipt_sz + 1))" "$ORCH_FILE" 2>/dev/null | \
            grep -E "$_addr_pattern" | head -10 || true
          echo ""
          echo "After reading, re-arm the watcher — it auto-advances the receipt on every wake."
          echo "In standalone mode (no active watcher), advance the receipt manually:"
          _adv_n=$(wc -c < "$ORCH_FILE" 2>/dev/null | tr -d ' ')
          _adv_hash=$(compute_prefix_sha256 "$ORCH_FILE" "$_adv_n" 2>/dev/null || true)
          if [[ -n "$_adv_hash" ]]; then
            printf "  printf 'offset=%%s\\nverified_sha256=%%s\\n' %s %s > %q\n" "$_adv_n" "$_adv_hash" "$RECEIPT_FILE"
          fi
          unset _adv_n _adv_hash
          FAIL=1
        else
          echo "OK [mailbox-read gate]: new content in $ORCH_FILE not addressed to '$MY_ID' or 'ALL'."
        fi
      else
        echo "OK [mailbox-read gate]: offset current (${receipt_sz}B = file size)."
      fi
    fi

    # ── check 1b: SSH signature verification over unverified mail (PROTOCOL 1.4.0) ──
    #
    # GIT-ANCHORED LOWER BOUND (item 1, 2026-08-09; redesigned round-2,
    # 2026-08-09 — Cipher): this used to snap the RECEIPT's offset via
    # --find-boundary and trust it as the verification floor. Cipher
    # demonstrated that is a full bypass — see the RECEIPT-FORGERY HARDENING
    # comment above check 1 for why. This check is now fully independent of
    # the receipt and of the Rule-4 nudge above (runs every time, regardless
    # of what that block decided) and instead anchors on `git show
    # HEAD:<file>` — the file's content as of the last commit (empty string
    # if the file is untracked/new in this repo). This is not
    # attacker-forgeable without rewriting git history, which this protocol
    # already treats as a gated, irreversible action elsewhere (Disaster
    # Rule 1, the force-push carveout) — an attacker able to do that has a
    # far bigger problem to answer for than this gate. The git-derived byte
    # count is then snapped via coord-verify.sh --find-boundary (Rook: fixed
    # round-2 to walk the same consumed-range logic the main verify loop
    # uses, so a body-quoted header can never be chosen as the anchor — see
    # that script's header comment) to the nearest real message boundary at
    # or before it — NEVER a raw byte cut — so this can never start
    # mid-message and silently skip that message's remainder. This verifies
    # coord-verify.sh directly against the REAL mailbox file with
    # --since-line, not a scratch copy of the tail bytes — a scratch copy
    # has no real basename, which would falsely trip coord-verify.sh's
    # FROM==basename(file) structural check on every message. If the file
    # has never been committed (git show fails) or the derived offset can't
    # be placed relative to any header at all, this verifies the WHOLE file
    # rather than silently treating any prefix as clean — the safe default
    # in both directions.
    #
    # Runs coord-verify.sh --strict, which is fatal on any ❌ INVALID
    # (tamper/forgery signal — always fatal), any ❓ UNKNOWN-SIGNER, and
    # any non-exempt ⚠️ UNVERIFIED (an unsigned message once this
    # amendment is adopted — see coord-verify.sh's header comment for the
    # exempt message shapes that never fail this check).
    # ROUND-5 (2026-08-09, Rook): on the REMOTE seat's own machine, its
    # coord-dir IS its bus dir, with no local allowed_signers by design (see
    # REMOTE-SEATS.md § Message Authenticity — single canonical trust root).
    # If this hook ALSO runs there (e.g. a remote seat committing its own
    # coord-dir content locally), check 1b below would find no local trust
    # root and hard-block that seat's commits FOREVER — the exact same
    # failure shape coord-send.sh had before its own --remote-seat fix,
    # never previously addressed for this hook. Rook: "silence is the worst
    # of the three [choices]" — COORD_REMOTE_SEAT_HOOK=1 is the explicit,
    # documented escape (env-var-only: this hook has no CLI flag surface,
    # wired via fixed positional args in settings.json — see this file's own
    # header). Deliberately a DIFFERENT variable than coord-send.sh's
    # COORD_REMOTE_SEAT/--remote-seat (round-5 item 6): sharing one var would
    # mean setting it for the hook's benefit on a remote seat's machine also
    # silently changes coord-send.sh's behavior there, and vice versa on the
    # hub — two different explicit-vs-ambient risk profiles, kept separate on
    # purpose. The compensating control is the HUB's check 1c above, which
    # verifies this seat's traffic remotely regardless.
    if [[ "$_REMOTE_SEAT_HOOK_SCOPE_OK" = 1 ]]; then
      # WARN, not INFO (round-6, Cipher): COORD_REMOTE_SEAT_HOOK is an
      # environment variable — always ambient, same risk class that earned
      # coord-send.sh's sibling COORD_REMOTE_SEAT var a WARN in round 5 (a
      # stray export left set is invisible until output like this names it).
      echo "WARN [sig-verify]: COORD_REMOTE_SEAT_HOOK=1 — skipping the LOCAL signature check for $ORCH_FILE (this bus dir has no local allowed_signers by design, and this coord-dir passed the remote-seat scope check above). The HUB verifies this seat's traffic remotely via coordination-precommit-hook.sh's check 1c — see REMOTE-SEATS.md § Message Authenticity. If this WAS NOT intended, check for a stray COORD_REMOTE_SEAT_HOOK=1 in this seat's environment." >&2
    elif [[ -f "$COORD_VERIFY_SH" ]]; then
      _git_anchor_n=0
      # `HEAD:./<basename>`, resolved relative to a cwd inside the file's OWN
      # directory, not a manually-stripped absolute-toplevel prefix — a
      # toplevel computed via `git rev-parse --show-toplevel` can resolve
      # through a symlink (e.g. macOS /var -> /private/var) that $ORCH_FILE's
      # own absolute path never passes through, silently breaking a naive
      # string-prefix strip and falling back to "untracked" even for a file
      # that IS committed (caught by this suite's own git-backed fixture).
      # `git show HEAD:./x` sidesteps that entirely: git resolves it against
      # cwd's in-repo position, no path-prefix arithmetic needed.
      if _orch_dir=$(cd "$(dirname "$ORCH_FILE")" 2>/dev/null && pwd); then
        if ( cd "$_orch_dir" && git show "HEAD:./$(basename "$ORCH_FILE")" > /dev/null 2>&1 ); then
          _git_anchor_n=$(cd "$_orch_dir" && git show "HEAD:./$(basename "$ORCH_FILE")" 2>/dev/null | wc -c | tr -d ' ')
        elif ! ( cd "$_orch_dir" && git rev-parse --show-toplevel > /dev/null 2>&1 ); then
          echo "WARN [sig-verify]: not inside a git working tree — cannot derive a git-anchored verification floor for $ORCH_FILE; verifying the whole file." >&2
        fi
        unset _orch_dir
      fi
      [[ "$_git_anchor_n" =~ ^[0-9]+$ ]] || _git_anchor_n=0

      _fb_out=""
      _fb_rc=0
      _fb_out=$(bash "$COORD_VERIFY_SH" --dir "$COORD_DIR" --file "$ORCH_FILE" --find-boundary "$_git_anchor_n" 2>&1) || _fb_rc=$?
      unset _git_anchor_n
      if [[ "$_fb_rc" -ne 0 || "$_fb_out" == "NOCOVER" ]]; then
        _since_line=0
      elif [[ "$_fb_out" =~ ^[0-9]+$ ]]; then
        _since_line="$_fb_out"
      else
        echo "WARN [sig-verify]: unexpected --find-boundary output ('$_fb_out') for $ORCH_FILE — verifying the whole file." >&2
        _since_line=0
      fi
      unset _fb_out _fb_rc

      SIG_VERIFY_RC=0
      SIG_VERIFY_OUT=$(bash "$COORD_VERIFY_SH" --dir "$COORD_DIR" --file "$ORCH_FILE" --since-line "$_since_line" --strict 2>&1) || SIG_VERIFY_RC=$?
      unset _since_line
      if [[ "$SIG_VERIFY_RC" -ne 0 ]]; then
        echo ""
        echo "FAIL [sig-verify]: mail in $ORCH_FILE since the last commit contains an INVALID, UNKNOWN-SIGNER, or unsigned (non-exempt) message:"
        echo "$SIG_VERIFY_OUT" | sed 's/^/  /'
        echo ""
        echo "A verification failure is a tamper/impersonation signal, not friction to route around."
        echo "Never bypass this without explicit human sign-off (see safety-carveouts.md)."
        echo "If this IS a remote seat's own bus-dir-as-coord-dir (no local trust root by design), set COORD_REMOTE_SEAT_HOOK=1 in its environment — see REMOTE-SEATS.md § Message Authenticity."
        FAIL=1
      else
        echo "OK [sig-verify]: $ORCH_FILE since the last commit — no INVALID / UNKNOWN-SIGNER / non-exempt UNVERIFIED signatures."
      fi
    else
      echo "INFO [sig-verify]: coord-verify.sh not found beside this hook ($COORD_VERIFY_SH) — skipping SSH signature check."
    fi
  done
else
  echo "INFO [mailbox-read gate]: COORD_DIR or MY_ID not set — skipping."
fi

# ── check 1c: remote-channel signature verification (PROTOCOL 1.4.0 remote-seat
#    extension, 2026-08-09, real gap 2; hardened round-5, 2026-08-09 —
#    Cipher/Rook, both live-confirmed) ─────────────────────────────────────────
#
# check 1b above only ever enumerates $COORD_DIR/*.md on the LOCAL filesystem
# — a remote seat's bus dir lives on a different host by definition and is
# structurally invisible to it. This used to be REMOTE-SEATS.md's documented
# scoping gap ("a remote seat's traffic is structurally invisible to the
# hard-block gate"). Closed by reading <coord-dir>/.remote-channels (one
# "<host> <bus-dir>" line per configured channel, AUTO-WRITTEN by
# coord-monitor.sh's remote channel when it arms — see that script's own
# comment; never a manual step) and, for each channel, ssh-fetching every
# remote seat's outbox file(s) IN FULL and verifying each against the SAME
# LOCAL allowed_signers and SAME structural FROM==basename(file) rule check
# 1b uses (via coord-remote-verify.sh's verify_remote_buffer — the exact
# same helper coord-monitor.sh's remote channel uses, so the two can never
# verify differently).
#
# SCOPE, why full-file every time (not git-anchored like check 1b): there is
# no local git history for a file that lives on a different host — nothing
# to anchor against. Remote mailboxes are bounded by this protocol's own
# ~200-message/50KB archive-hygiene convention (see MAILBOX-template.md), so
# a full re-verify on every commit is cheap regardless of the channel's own
# rotation cadence, not a wasted-effort concern the way a fully unbounded
# file would be.
#
# REACHABILITY: a bounded ssh timeout (ConnectTimeout + ServerAlive — no new
# dependency on GNU coreutils `timeout(1)`, which this dev box does not even
# have, matching this protocol's "no new dependency" posture elsewhere).
# An unreachable remote host does NOT silently skip verification — that
# would be a bypass an attacker (or a flaky network) gets for free. It fails
# CLOSED, loud, with a diagnostic that names the real cause (network
# unreachability) rather than reading like a tamper signal.
#
# ROUND-5 HARDENING (Cipher live-exploited an RCE here; Rook independently
# found two more real gaps — see REMOTE-SEATS.md § Message Authenticity for
# the full closed-history writeup):
#   1. $_rc_name (a filename LISTED BY THE REMOTE HOST — i.e. as trustworthy
#      as whoever can write into the remote bus dir, exactly the population
#      this whole extension exists to distrust) used to be spliced into the
#      remote fetch command with ZERO shell-metacharacter escaping. A file
#      named e.g. "x'; id; echo '.md" executed arbitrary code on the hub,
#      BEFORE any signature check ran. Every value spliced into a remote
#      command string (bus dir + filename, for BOTH the listing and the
#      fetch) now goes through coord_remote_shquote (coord-remote-verify.sh)
#      — the SAME helper coord-monitor.sh's remote channel uses, so the two
#      can never diverge on how a value is escaped.
#   2. `for _rc_name in $_rc_files` was unquoted — remote filenames underwent
#      both local IFS word-splitting AND local pathname expansion against
#      this host's own cwd. `while IFS= read -r` below fixes it.
#   3. Every remote ssh call here now passes -n (redirect ssh's own stdin
#      from /dev/null) — this loop reads `.remote-channels` from fd0 via
#      `done < "$_REMOTE_CHANNELS_FILE"`; without -n, an ssh call inside that
#      loop body would race to drain the SAME fd0, silently truncating the
#      outer `while read` loop's remaining channel lines on a multi-channel
#      config (a real, latent correctness bug independent of the RCE, found
#      while fixing it — see coord-monitor.sh's remote_sweep_sizes for the
#      identical hazard/fix on the monitor side).
#   4. coord_is_seat_outbox_basename (coord-address-filter.sh, shared with
#      coord-monitor.sh's local + remote enumerators — see that function's
#      header for the full "three independently-drifting lists" history) is
#      now applied here too: a remote QUEUE.md/PROJECTS.md/queue-*.md/archive
#      file — an ORDINARY deployment using a queue file, not a crafted
#      attack — used to permanently hard-block every hub commit via a false
#      structural FROM/basename mismatch. This was previously the ONLY one
#      of the four enumerators applying NO exclusion at all.
#   5. This block now ALWAYS prints which host:bus-dir combination(s) were
#      checked, even zero — and cross-checks a live watcher-remote.pid
#      against an empty/missing .remote-channels. See the summary block
#      below the per-channel loop for the full rationale (a missing/empty/
#      redirected .remote-channels used to produce ZERO output, silently
#      indistinguishable from "no remote channel exists").
if [[ -n "$COORD_DIR" ]]; then
  _REMOTE_CHANNELS_FILE="$COORD_DIR/.remote-channels"
  _RC_CHECKED_COUNT=0
  _RC_CHECKED_SUMMARY=""

  # ROUND-6 (2026-08-09, Rook): this guard used to check for verify_remote_buffer
  # and coord_remote_shquote but NOT coord_is_seat_outbox_basename — if
  # coord-address-filter.sh alone was missing (while coord-remote-verify.sh
  # was present), the call at "coord_is_seat_outbox_basename ... || continue"
  # below would fail with exit 127 (command not found), silently swallowed
  # by that same `|| continue`, and EVERY remote file got skipped — while
  # this block still printed "checked N remote channel(s)" and exited 0.
  # coord_is_seat_outbox_basename is now part of the same guard as the other
  # two required helpers, so a partially-missing helper set degrades to the
  # fail-closed else branch below instead of a silent no-op skip.
  if [[ -f "$COORD_REMOTE_VERIFY_SH" && -f "$COORD_VERIFY_SH" ]] && command -v verify_remote_buffer >/dev/null 2>&1 && command -v coord_remote_shquote >/dev/null 2>&1 && command -v coord_is_seat_outbox_basename >/dev/null 2>&1; then
    if [[ -s "$_REMOTE_CHANNELS_FILE" ]]; then
      _SSH_OPTS=(-n -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2)
      while IFS=' ' read -r _rc_host _rc_bus; do
        [[ -z "$_rc_host" || -z "$_rc_bus" || "$_rc_host" == \#* ]] && continue
        _RC_CHECKED_COUNT=$((_RC_CHECKED_COUNT + 1))
        _RC_CHECKED_SUMMARY="${_RC_CHECKED_SUMMARY}  - ${_rc_host}:${_rc_bus}
"
        _q_rc_bus=$(coord_remote_shquote "$_rc_bus")
        _rc_list_script="for f in $_q_rc_bus/*.md; do [ -e \"\$f\" ] || continue; printf '%s\n' \"\$(basename \"\$f\")\"; done"
        _rc_files=""
        _rc_list_rc=0
        _rc_files=$(ssh "${_SSH_OPTS[@]}" "$_rc_host" "$_rc_list_script" 2>/dev/null) || _rc_list_rc=$?
        if [[ "$_rc_list_rc" -ne 0 ]]; then
          echo ""
          echo "FAIL [remote-sig-verify]: could not reach remote channel $_rc_host to verify — treating as UNVERIFIED, not skipping."
          echo "  (bus dir: $_rc_bus — configured in $_REMOTE_CHANNELS_FILE)"
          echo "Never bypass this without explicit human sign-off (see safety-carveouts.md)."
          FAIL=1
          unset _q_rc_bus
          continue
        fi
        while IFS= read -r _rc_name; do
          [[ -z "$_rc_name" ]] && continue
          # Round-6 (2026-08-09, Cipher): also reject an embedded newline/CR
          # here — consumption-side defense in depth alongside coord-remote-
          # verify.sh's identical extension, and coord-monitor.sh's
          # remote_sweep_script closing this at the LISTING source (see that
          # function's header for the wire-format-injection this is about).
          case "$_rc_name" in */*|.|..|*$'\n'*|*$'\r'*) continue;; esac
          coord_is_seat_outbox_basename "$_rc_name" || continue
          _q_rc_name=$(coord_remote_shquote "$_rc_name")
          _rc_buf=""
          _rc_fetch_rc=0
          _rc_buf=$(ssh "${_SSH_OPTS[@]}" "$_rc_host" "cat $_q_rc_bus/$_q_rc_name" 2>/dev/null) || _rc_fetch_rc=$?
          if [[ "$_rc_fetch_rc" -ne 0 ]]; then
            echo ""
            echo "FAIL [remote-sig-verify]: could not reach remote channel $_rc_host to fetch $_rc_name — treating as UNVERIFIED, not skipping."
            echo "Never bypass this without explicit human sign-off (see safety-carveouts.md)."
            FAIL=1
            continue
          fi
          _rc_verify_out=""
          _rc_verify_rc=0
          _rc_verify_out=$(printf '%s' "$_rc_buf" | verify_remote_buffer "$COORD_DIR" "$_rc_name" "$COORD_VERIFY_SH" --strict 2>&1) || _rc_verify_rc=$?
          if [[ "$_rc_verify_rc" -ne 0 ]]; then
            echo ""
            echo "FAIL [remote-sig-verify]: $_rc_host:$_rc_bus/$_rc_name contains an INVALID, UNKNOWN-SIGNER, or unsigned (non-exempt) message:"
            echo "$_rc_verify_out" | sed 's/^/  /'
            echo ""
            echo "A verification failure is a tamper/impersonation signal, not friction to route around."
            echo "Never bypass this without explicit human sign-off (see safety-carveouts.md)."
            FAIL=1
          else
            echo "OK [remote-sig-verify]: $_rc_host:$_rc_bus/$_rc_name — no INVALID / UNKNOWN-SIGNER / non-exempt UNVERIFIED signatures."
          fi
        done <<< "$_rc_files"
        unset _q_rc_bus
      done < "$_REMOTE_CHANNELS_FILE"
      unset _SSH_OPTS
    fi
  else
    # ROUND-6 (2026-08-09, Cipher — live-demonstrated): this used to be
    # INFO-only, no FAIL=1 anywhere. Live-confirmed: with a required helper
    # missing (e.g. coord-remote-verify.sh removed) and no live
    # watcher-remote.pid at that exact moment (the compensating cross-check
    # below only saves you if a watcher happens to be running right then), a
    # genuinely unsigned/tampered remote message sailed through — hook exit
    # 0, commit allowed, zero attacker involvement required (ordinary
    # deployment drift: a partial hub upgrade, a commit landing between
    # watcher restarts). A CONFIGURED-but-UNVERIFIABLE remote channel must
    # block, full stop — same fail-closed posture this check already uses
    # for an unreachable host and for the empty/redirected-file cross-check
    # below. "Verification could not run" is not a weaker case than
    # "verification ran and found nothing wrong" — it must never be treated
    # as equivalent to a clean pass.
    if [[ -s "$_REMOTE_CHANNELS_FILE" ]]; then
      echo ""
      echo "FAIL [remote-sig-verify]: coord-remote-verify.sh/coord-verify.sh/coord-address-filter.sh not found (or missing a required helper) beside this hook, but $_REMOTE_CHANNELS_FILE configures at least one remote channel — cannot verify it. Treating as UNVERIFIED, not skipping."
      echo "Never bypass this without explicit human sign-off (see safety-carveouts.md)."
      FAIL=1
    fi
  fi

  # Round-5 (2026-08-09, Cipher/Rook — both live-confirmed): ALWAYS state
  # explicitly which channels were checked, even zero. A missing/empty
  # .remote-channels used to produce ZERO output from this whole block —
  # indistinguishable from "no remote channels exist" for a human reading
  # hook output. Worse, Cipher demonstrated that pointing .remote-channels
  # at an unrelated, genuinely-empty DECOY directory (while a real forged/
  # unsigned message sits in the ACTUAL remote bus dir) produced exit 0 and
  # zero diagnostic output — a completely silent bypass, since .remote-
  # channels is itself unsigned, gitignored, coord-dir-local state, writable
  # by exactly the actor this whole mechanism defends against.
  #
  # This does NOT cryptographically prevent that redirect (Rook: don't build
  # a new verified-floor artifact to solve it — that ceiling is the same one
  # already accepted for allowed_signers itself, see check 6 above and
  # README.md § Message Authenticity: a coord-dir-write-level attacker can
  # already edit either file). What it buys: the redirect becomes VISIBLE —
  # an operator who knows their real remote bus dir sees the wrong one named
  # right here in hook output, rather than silence. Tampering becomes noisy,
  # not prevented outright — stated plainly, not overclaimed.
  echo ""
  echo "INFO [remote-sig-verify]: checked $_RC_CHECKED_COUNT remote channel(s) from $_REMOTE_CHANNELS_FILE"
  [[ -n "$_RC_CHECKED_SUMMARY" ]] && printf '%s' "$_RC_CHECKED_SUMMARY"

  # Cross-check (closes the missing/empty half of the gap above): a remote
  # channel auto-writes its own watcher-remote.pid AND .remote-channels line
  # together at arm time (coord-monitor.sh) — if a watcher-remote.pid shows a
  # LIVE process but this hook found zero channels to check, either
  # .remote-channels was never written (stale/pre-1.4.0 watcher), got
  # deleted, or was redirected to a decoy that happens to be empty. All three
  # are the same failure shape from here: a remote channel this host believes
  # is armed is not being verified. Fail loud rather than silently trust an
  # empty result — same posture as this file's other fail-closed gates.
  if [[ "$_RC_CHECKED_COUNT" -eq 0 ]]; then
    _RC_LIVE_WATCHER=""
    for _rc_pidfile in "$COORD_DIR"/.watch-state/*/watcher-remote.pid; do
      [[ -f "$_rc_pidfile" ]] || continue
      _rc_wpid=$(cat "$_rc_pidfile" 2>/dev/null || true)
      if [[ -n "$_rc_wpid" ]] && ps -p "$_rc_wpid" >/dev/null 2>&1; then
        _RC_LIVE_WATCHER="$_rc_pidfile"
        break
      fi
    done
    if [[ -n "$_RC_LIVE_WATCHER" ]]; then
      echo ""
      echo "FAIL [remote-sig-verify]: a remote-channel watcher is running ($_RC_LIVE_WATCHER) but no channel was checked (.remote-channels missing/empty/unreadable at $_REMOTE_CHANNELS_FILE) — a live remote channel this host believes is armed is NOT being verified."
      echo "  Restart the remote coord-monitor.sh channel (it re-writes .remote-channels on arm) or add the missing '<host> <bus-dir>' line by hand, then retry."
      echo "Never bypass this without explicit human sign-off (see safety-carveouts.md)."
      FAIL=1
    fi
    unset _RC_LIVE_WATCHER _rc_wpid _rc_pidfile
  fi
  unset _REMOTE_CHANNELS_FILE _RC_CHECKED_COUNT _RC_CHECKED_SUMMARY
fi

# ── check 1d: protocol-version MAJOR mismatch gate (PROTOCOL 1.5.0 §3.5 Part D) ──
#
# MAJOR = wire/grammar-breaking (a seat on the old MAJOR cannot correctly
# produce or parse what the new MAJOR expects) — see README.md § Protocol
# Version Handshake for the full MAJOR/MINOR/PATCH convention. MINOR/PATCH
# mismatches never block here — they're advisory-only, surfaced by
# coord-monitor.sh's re-arm-time check and the bootstrap-time exchange (Parts
# A/B), not this gate.
#
# ROUND-9 (2026-08-10, Cipher HIGH — live-demonstrated both directions): this
# used to source a peer's protocol_version from their .presence sidecar —
# unsigned, coord-dir-write-level-forgeable state with no ownership
# enforcement (unlike mailbox files). Anyone with coord-dir write access
# could forge a peer's presence to (a) fabricate a MAJOR mismatch and
# hard-block the hub's commits (DoS), or (b) mask a REAL mismatch by
# matching the hub's own version, defeating the gate entirely. The human's
# call: a hard block is only as trustworthy as what feeds it — extend
# SIGNING coverage to this data rather than downgrade to advisory-only.
#
# Every seat's routine, already-signed HEARTBEAT append (heartbeat.sh) now
# embeds PROTOCOL-VERSION in its body. For each enrolled peer this collects
# EVERY message in their mailbox file, within a bounded recent tail window
# (not an unbounded full-history rewalk every commit — heartbeats are
# frequent enough this is sufficient in practice), that (a) carries a
# PROTOCOL-VERSION field and (b) verifies cleanly against allowed_signers —
# via coord-verify.sh's OWN engine (never a second, parallel verification
# path). See ROUND-11 below for why this no longer tries to pick a single
# "current" claim.
#
# ROUND-10 (2026-08-10, Cipher HIGH — round-9's fix moved this hole, did not
# close it): the original round-9 version extracted (timestamp, version)
# candidates via a SECOND, INDEPENDENT raw-file awk scan, then only checked
# that the CANDIDATE'S TIMESTAMP matched some coord-verify.sh "✅ VERIFIED"
# line — never that the specific PROTOCOL-VERSION line itself sat inside the
# bytes that were actually signed. Cipher live-demonstrated both directions:
# `printf >>` unsigned text straight after a real message's own SIG block
# (same timestamped message, no new `### ` header) was picked up by the raw
# scan and passed the timestamp match-back, letting unsigned content
# fabricate a false MAJOR mismatch (DoS) or mask a real one — full defeat,
# same as before the round-9 rewrite existed. Fix: coord-verify.sh's
# `--extract-field NAME` (see that script's own header comment) scans ONLY
# `signed_region` — the EXACT bytes it independently computes and passes to
# `ssh-keygen -Y verify` for that message — and prints `FIELD-VERIFIED <frm>
# <ts> <value>` only when found there. There is no longer a second scan of
# any kind on this side: every value below comes directly from coord-verify.sh
# parsing its OWN already-verified content, by construction.
#
# ROUND-11 (2026-08-10, Cipher HIGH — the THIRD distinct way "which claim is
# authoritative" was gamed): round-10's version still picked a single
# "current" claim — the LAST FIELD-VERIFIED line coord-verify.sh printed.
# coord-verify.sh emits these in PHYSICAL FILE-BYTE-OFFSET order, never by
# the message's own timestamp. A coord-dir-write-level attacker with ZERO
# signing key can physically reorder two of a peer's own, genuinely,
# honestly signed historical HEARTBEATs — no forgery, not one byte inside
# either message touched, both independently still VERIFIED — and flip
# which one this logic treated as "most recent," in either direction (mask
# a real current mismatch by putting the compatible one last, or fabricate
# a false one by putting a stale incompatible one last). The attack
# precondition — a peer having 2+ genuinely different historical version
# claims in the tail window — is not an edge case: it is the literal shape
# of a genuine version transition, the exact event this gate exists to
# catch.
#
# The human's call: stop trying to determine "most recent" at all — there is
# no arbitration left to game if there is no arbitration. This now collects
# EVERY verified PROTOCOL-VERSION claim for a peer in the tail window and
# blocks if ANY of them has an incompatible MAJOR, full stop, listing every
# incompatible claim found (not just one) so a human resolving this sees the
# actual history. Accepted, documented tradeoff (see README.md § Protocol
# Version Handshake, Part D — same ceiling-statement area as this gate's
# other accepted limits): immediately after a genuine, deliberate MAJOR
# transition, the peer's own past incompatible claim can still sit in the
# tail window until enough newer content ages it out — a brief,
# self-resolving false-positive block. Deliberately preferred over any
# scheme that re-introduces a "pick the winner" step: MAJOR bumps are rare
# (nothing shipped 1.1.0-1.5.0 has ever been one) and deliberate; "briefly
# noisy right after an expected rare transition" is a categorically safer
# failure mode than "an attacker with no signing key decides which of a
# peer's own real, honest claims counts."
#
# ROUND-12 (2026-08-10, Cipher HIGH — round-11's fix has its own gap, one
# layer up): round-11 correctly stopped arbitrating WHICH claim wins, but the
# tail window feeding that collection was still `coord-verify.sh --tail N` —
# a RAW LINE COUNT computed before any signature classification. A
# coord-dir-write-level attacker with ZERO signing key can append any number
# of unsigned messages SHAPED to match the dead-man-alarm's own documented
# exemption (c) (tag starting "⚠️ ", body's first line the exact
# "[SIGNING-FAILED — ...]" sentinel — that exemption checks SHAPE only, never
# that heartbeat.sh itself produced it or that a real signing failure
# occurred). Each one is legitimately non-fatal under --strict (working
# exactly as exemption (c) is meant to) while ALSO counting as raw lines
# toward --tail's eviction boundary — enough of them pushes a peer's real,
# currently-true, genuinely signed+verified incompatible PROTOCOL-VERSION
# claim out of the window entirely, so this check's own claim-collection loop
# below sees "0 with a verified claim" instead of the real one. One-
# directional only (can hide a real mismatch, never fabricate a fake one),
# but that is the single worst-case failure for this gate's entire purpose.
# Neither check 1b (mailbox-read gate) nor check 1c catch this: the padding
# can trickle in across many small, individually-unremarkable commits, and
# once the hub's own receipt tracking advances past it (automatic on any
# armed watcher's normal wake cycle), the eviction is permanent for this
# check regardless of how it arrived.
#
# Fix: coord-verify.sh's new `--tail-verified N` (see that script's own
# header comment) computes its window boundary from CLASSIFIED content —
# the last N message spans that actually verify — never a raw line count.
# Unsigned padding of any shape, including all three --strict exemption
# shapes, is skipped "for free" and cannot consume any of the N budget, so
# it can no longer evict a real VERIFIED claim no matter how much of it an
# attacker appends. Same structural principle as round-10's fix
# (--extract-field scoping to signed_region instead of a second raw scan),
# applied one layer up: to window selection instead of field extraction.
# `_PV_TAIL_LINES` (a raw line count) is replaced below with
# `_PV_TAIL_VERIFIED_N` (a VERIFIED-message count) — smaller in absolute
# terms is fine and expected, since it now only has to count messages that
# actually verified, not raw lines an attacker could freely inflate.
#
# check_peer_protocol_versions (Part B, coord-monitor.sh's advisory re-arm
# alert) deliberately STAYS presence-sourced — Cipher separately rated that
# path's forgery risk LOW (informational, cheap, frequent; the human's
# hard-block decision is what makes signed-sourcing worth its cost here, not
# every consumer of protocol_version).
#
# ROUND-9 (Cipher + Rook, peer enumeration): INBOX_FILES enumerates MAILBOX
# FILES, not real peers — two independent, non-overlapping ways that
# diverges from "who is actually enrolled": (1) Cipher — an identity named
# to match coord_is_seat_outbox_basename's structural-file exclusion (e.g.
# "queue-evil") evades INBOX_FILES entirely, a genuine MAJOR-divergent peer
# sails through unnoticed; (2) Rook — a seat mid-archive-rotation (<id>.md
# just renamed to <id>.archive.md, a normal, documented operation) has live
# presence/enrollment but no current INBOX_FILES entry, same blind spot with
# zero malice. The peer set is now derived from allowed_signers (the actual
# enrolled-identity trust root) — an attacker cannot rename their way out of
# being enrolled, and archive rotation never changes enrollment.
if [[ -n "$COORD_DIR" && -n "$MY_ID" && -f "$COORD_VERIFY_SH" ]]; then
  # ROUND-12: a VERIFIED-message count, not a raw line count — several
  # signed HEARTBEAT cycles' worth, generous but immune to unsigned padding
  # of any shape (see ROUND-12 comment above _PV_TAIL_LINES's old use).
  _PV_TAIL_VERIFIED_N=50
  _PV_CHECKED=0
  _PV_KNOWN=0
  _PV_SELF_UNKNOWN=0
  # ROUND-9 (Rook — "fix this first, most dangerous in practice"): a
  # partial/incomplete framework copy (PROTOCOL-VERSION file missing beside
  # this hook) leaves PROTOCOL_VERSION at the "unknown" default from the
  # sourcing block near the top of this file. The peer-side guard below
  # already refuses to compare against an unknown PEER version; this guards
  # the SELF side the same way — skip the whole check with a loud WARN
  # rather than hard-blocking every peer, every commit, forever, on not
  # knowing our own version. Never fail on absence-of-data alone.
  [[ "$PROTOCOL_VERSION" == "unknown" || -z "$PROTOCOL_VERSION" ]] && _PV_SELF_UNKNOWN=1

  if [[ "$_PV_SELF_UNKNOWN" = 1 ]]; then
    echo "WARN [protocol-version]: this seat's own PROTOCOL_VERSION is unknown (PROTOCOL-VERSION file missing beside this hook — partial/incomplete framework copy?) — skipping the protocol-version gate rather than false-blocking every peer." >&2
  else
    MY_PV_MAJOR="${PROTOCOL_VERSION%%.*}"
    if [[ -f "$COORD_DIR/allowed_signers" ]]; then
      while IFS= read -r _pv_peer; do
        [[ -z "$_pv_peer" || "$_pv_peer" == \#* || "$_pv_peer" == "$MY_ID" ]] && continue
        _PV_CHECKED=$((_PV_CHECKED + 1))
        # ROUND-9 (Rook — archive-rotation lifecycle): a seat mid-rotation
        # (<id>.md renamed to <id>.archive.md, coord_is_seat_outbox_basename's
        # documented, ordinary lifecycle — see coord-address-filter.sh:86-92)
        # stays enrolled and is therefore still counted in _PV_CHECKED below
        # (the old INBOX_FILES-based enumeration made them silently invisible
        # instead). Deliberately NOT also scanning <peer>.archive.md for a
        # claim: coord-verify.sh's structural FROM==basename(file) check (see
        # coord-verify.sh:60-89) is a hardened anti-splice control that always
        # rejects archive-file content by design — every message inside says
        # FROM=<peer> but the archive's own basename is "<peer>.archive", so
        # it can never verify there. Loosening that check for this one caller
        # would reopen the exact cross-mailbox splice attack it exists to
        # prevent, for a rotation case that already degrades safely: an
        # archived peer with no live claim simply falls into the same
        # never-hard-block-on-absence path as a brand-new peer, but is now
        # honestly named in the INFO line below instead of dropped silently.
        _pv_peer_file="$COORD_DIR/$_pv_peer.md"
        _pv_claims=""
        if [[ -f "$_pv_peer_file" ]]; then
          # coord-verify.sh exits non-zero whenever the file contains ANY
          # invalid message — not just a protocol-version-shaped one. Under
          # this hook's own `set -euo pipefail`, a bare `var=$(...)`
          # assignment with no `|| ` guard would abort the ENTIRE hook script
          # right here on ANY tampered message anywhere in a peer's file,
          # short-circuiting checks 1c/2's own proper FAIL-with-exit-2
          # reporting for it (round-9 regression, caught by this pack's own
          # full test suite — see notebook memory
          # feedback_set_e_command_substitution_guard.md). Safe to swallow
          # here ONLY because this check only ever consumes stdout below,
          # never branches on the exit code, AND because check 1b already
          # fails closed ahead of this point if ssh-keygen/python3/
          # coord-verify.sh itself is genuinely missing (the `-f
          # "$COORD_VERIFY_SH"` guard at this block's own top) — if that
          # posture in check 1b ever changes, this `|| true` needs revisiting
          # alongside it.
          _pv_verify_out=$(bash "$COORD_VERIFY_SH" --dir "$COORD_DIR" --file "$_pv_peer_file" --tail-verified "$_PV_TAIL_VERIFIED_N" --extract-field PROTOCOL-VERSION 2>/dev/null) || true
          # ROUND-11 (2026-08-10, Cipher HIGH — the third hole in this same
          # gate): coord-verify.sh emits FIELD-VERIFIED lines in PHYSICAL
          # FILE-BYTE-OFFSET order, never by the message's own timestamp. A
          # coord-dir-write-level attacker with ZERO signing key can
          # physically reorder two of a peer's own, genuinely, honestly
          # signed historical HEARTBEATs — no forgery, not one byte inside
          # either message touched, both still independently VERIFIED — and
          # flip which claim a "pick the most recent one" rule would treat
          # as authoritative, in either direction (mask a real current
          # mismatch, or fabricate a false one from stale history). This is
          # the THIRD distinct way "which claim wins" has been gamed
          # (unsigned presence in round 8, an unscoped byte range in round
          # 9, file order in round 10) — the human's call (round-11): stop
          # trying to determine "most recent" at all. Collect EVERY
          # FIELD-VERIFIED claim in the tail window below and block on ANY
          # of them being MAJOR-incompatible, full stop. There is no
          # "winner" left to game.
          _pv_claims=$(printf '%s\n' "$_pv_verify_out" | awk -v peer="$_pv_peer" '$1=="FIELD-VERIFIED" && $2==peer { v=$4; for (i=5;i<=NF;i++) v=v" "$i; print $3"|"v }')
        fi
        if [[ -z "$_pv_claims" ]]; then
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
          done
          echo "A MAJOR difference means one side cannot correctly produce or parse what the other expects (wire/grammar-breaking) — this is not friction to route around."
          echo "Upgrade the stale side to a matching MAJOR version before committing further. See README.md § Message Authenticity, Protocol Version Handshake."
          echo "If this peer genuinely already transitioned and only a stale historical claim is triggering this: this is expected, self-resolving noise — it clears once enough newer content pushes the old claim past the tail window (see README's ceiling note for this check)."
          FAIL=1
        fi
      # ROUND-10 (Rook): split the principal field on commas before printing
      # — every tool-written line (coord-keygen.sh) is always one bare
      # identity, but ssh's own allowed_signers format permits a
      # comma-separated principal list, which a hand-edited line could use.
      # A bare `{ print $1 }` would treat "alice,bob" as one literal
      # (phantom, non-matching) peer and silently enumerate neither real
      # identity.
      done < <(awk '!/^#/ && NF { n = split($1, a, ","); for (i = 1; i <= n; i++) print a[i] }' "$COORD_DIR/allowed_signers" 2>/dev/null | sort -u)
    fi
  fi

  echo ""
  if [[ "$_PV_SELF_UNKNOWN" = 1 ]]; then
    echo "INFO [protocol-version]: skipped — this seat's own PROTOCOL_VERSION is unknown, see WARN above."
  else
    echo "INFO [protocol-version]: checked $_PV_CHECKED enrolled peer(s), $_PV_KNOWN with a verified PROTOCOL-VERSION claim (self: $PROTOCOL_VERSION, MAJOR ${MY_PV_MAJOR:-?})."
  fi
  unset _PV_TAIL_VERIFIED_N _PV_CHECKED _PV_KNOWN _PV_SELF_UNKNOWN MY_PV_MAJOR _pv_peer _pv_peer_file _pv_verify_out _pv_claims _pv_incompatible _pv_claim _pv_cts _pv_cver _pv_cmajor _pv_inc
elif [[ -n "$COORD_DIR" && -n "$MY_ID" ]]; then
  # ROUND-10 (Rook): the guard above stays silent when coord-verify.sh
  # itself is missing — same "one missing helper, no stated posture"
  # pattern this file already learned to avoid at round 5-6's other sites.
  # Absence-of-tooling is not a security gap here the way an absent
  # allowed_signers or a failed remote fetch would be (nothing to hard-block
  # ON without it), but it should never be silent either.
  echo ""
  echo "INFO [protocol-version]: skipping — coord-verify.sh not found at $COORD_VERIFY_SH (partial/incomplete framework copy?)."
fi

# ── check 2: Rule 1 advisory — dangerous staging verb ────────────────────────

if [[ "$cmd_field" =~ "git add -A" || "$cmd_field" =~ "git add ." ]]; then
  echo ""
  echo "ADVISORY [Rule 1 — staging]: Detected 'git add -A' or 'git add .' in a potential shared tree."
  echo "Rule 1: commit only explicit paths in dual mode. An in-flight implementer may have"
  echo "  staged artifacts in your tree that you'd inadvertently include."
  echo ""
  echo "  If you are sure this is safe (e.g. you are in an isolated worktree),"
  echo "  add an explicit '--' path to the commit command and proceed."
  echo "  If unsure: run 'git status' first and stage explicit files only."
  echo ""
  # This is a WARNING, not a hard block — the human may override.
  # Change FAIL=1 here to enforce it as a hard block if desired.
fi

# ── check 3: secret-scan staged diff ─────────────────────────────────────────

STAGED_DIFF=$(git diff --cached 2>/dev/null || true)
if [[ -n "$STAGED_DIFF" ]]; then
  found_secrets=0
  for pattern in "${SECRET_PATTERNS[@]}"; do
    if printf '%s\n' "$STAGED_DIFF" | grep -qE "$pattern" 2>/dev/null; then
      if [[ $found_secrets -eq 0 ]]; then
        echo ""
        echo "FAIL [secret-scan]: Possible secret(s) detected in staged diff:"
      fi
      echo "  Pattern matched: $pattern"
      printf '%s\n' "$STAGED_DIFF" | grep -E "$pattern" | head -3 | sed 's/^/    /' || true
      found_secrets=1
    fi
  done
  if [[ $found_secrets -eq 1 ]]; then
    echo ""
    echo "Rule 5: no secrets in any shared artifact. Review the matches above."
    echo "If this is a false positive, unstage the file, add it to .gitignore or .secretignore,"
    echo "and re-stage only the non-secret changes."
    FAIL=1
  else
    echo "OK [secret-scan]: no obvious secrets detected in staged diff."
  fi
else
  echo "INFO [secret-scan]: no staged changes found."
fi

# ── check 4: canon-doc reverse-index advisory ─────────────────────────────────
# Advisory only — never sets FAIL. If a project keeps canon/spec docs that cite
# source paths (e.g. "services/foo/bar.py"), this builds a cheap reverse index
# so a commit touching a cited path surfaces "N docs mention this" — a nudge to
# check whether the doc needs updating, without blocking the commit on it.
# No project-specific default doc root is assumed — set COORD_CANON_DOCS_DIR
# (a directory of *.md files) and COORD_CANON_CITE_PATTERN (a regex matching
# the source-path shape your docs cite, e.g. 'services/[A-Za-z0-9_./-]+\.py')
# to enable this check. Silently skipped when either is unset.
_CANON_DOCS_DIR="${COORD_CANON_DOCS_DIR:-}"
_CANON_CITE_PATTERN="${COORD_CANON_CITE_PATTERN:-}"
_INDEX_CACHE="${COORD_DIR:-/tmp}/.watch-state/path-doc-index.tsv"
if [[ -n "$_CANON_DOCS_DIR" && -n "$_CANON_CITE_PATTERN" ]] && { _is_commit_landing_cmd "$cmd_field" || _is_push_cmd "$cmd_field"; }; then
  _changed_paths=$(git diff --cached --name-only 2>/dev/null || true)
  if [[ -z "$_changed_paths" && "$cmd_field" == *"git push"* ]]; then
    _changed_paths=$(git diff --name-only "@{upstream}..HEAD" 2>/dev/null || git diff --name-only "HEAD~5..HEAD" 2>/dev/null || true)
  fi
  if [[ -n "$_changed_paths" && -d "$_CANON_DOCS_DIR" ]]; then
    mkdir -p "$(dirname "$_INDEX_CACHE")" 2>/dev/null || true
    # Rebuild cache if missing or docs dir newer than cache (best-effort).
    _rebuild=0
    if [[ ! -f "$_INDEX_CACHE" ]]; then
      _rebuild=1
    elif [[ -n "$(find "$_CANON_DOCS_DIR" -type f -name '*.md' -newer "$_INDEX_CACHE" 2>/dev/null | head -1)" ]]; then
      _rebuild=1
    fi
    if [[ "$_rebuild" -eq 1 ]]; then
      CANON_CITE_PATTERN="$_CANON_CITE_PATTERN" python3 - "$_CANON_DOCS_DIR" "$_INDEX_CACHE" <<'PY' 2>/dev/null || true
import os, re, sys
from pathlib import Path
docs, out = Path(sys.argv[1]), Path(sys.argv[2])
pat = re.compile(os.environ["CANON_CITE_PATTERN"])
index = {}
for md in docs.rglob("*.md"):
    try:
        text = md.read_text(encoding="utf-8", errors="replace")
    except OSError:
        continue
    rel = str(md)
    for m in pat.finditer(text):
        index.setdefault(m.group(0), set()).add(rel)
with out.open("w", encoding="utf-8") as f:
    for path, docs_set in sorted(index.items()):
        f.write(path + "\t" + "|".join(sorted(docs_set)) + "\n")
PY
    fi
    if [[ -f "$_INDEX_CACHE" ]]; then
      _cite_summary=$(CHANGED_PATHS="$_changed_paths" python3 - "$_INDEX_CACHE" <<'PY'
import os, sys
from collections import Counter
cache = sys.argv[1]
index = {}
for line in open(cache, encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if not line or "\t" not in line:
        continue
    path, docs = line.split("\t", 1)
    index[path] = docs.split("|") if docs else []
hits = Counter()
changed = [ln.strip() for ln in os.environ.get("CHANGED_PATHS", "").splitlines() if ln.strip()]
for p in changed:
    base = p.split("/")[-1]
    for k, docs in index.items():
        if k == p or k.endswith("/" + base) or k.endswith(base):
            for d in docs:
                hits[d] += 1
if not hits:
    print("")
    sys.exit(0)
top = hits.most_common(3)
n = len(hits)
names = [t[0].rsplit("/", 1)[-1] for t in top]
more = n - len(names)
msg = f"{n} docs cite paths in this commit: " + ", ".join(names)
if more > 0:
    msg += f" … +{more} more (full list: {cache})"
print(msg)
PY
)
      if [[ -n "$_cite_summary" ]]; then
        echo ""
        echo "ADVISORY [canon-doc reverse-index]: $_cite_summary"
      else
        echo "OK [canon-doc reverse-index]: no canon-doc citations for staged paths."
      fi
    fi
  fi
fi

# ── check 5: fail-closed gated push ───────────────────────────────────────────
# BLOCK a push to a gated remote/target, OR a commit touching gated paths,
# without an explicit authorization reference in the commit message(s) (or
# COORD_AUTH_REF env). This is a project-configurable gate — with no config
# set, this check is a no-op (nothing is gated by default).
#
# Ceiling: the reference string is actor-written — this forces an auditable
# assertion at the point of action; it does not prove the authorization is
# genuine. It blocks accidental publish, not a determined fabrication.
#
# Configuration (all optional; unset = that gate class is disabled):
#   COORD_GATED_REMOTE_PATTERN   grep -E pattern matched against `git remote -v`
#                                 output and cwd (e.g. a public-auto-deploy repo)
#   COORD_GATED_PATH_PATTERN     grep -E pattern matched against changed/pushed
#                                 paths (e.g. canon docs, ADRs, a DECISIONS.md)
#   COORD_AUTH_REF               if set (non-empty), always satisfies the gate
_GATED_REMOTE_PATTERN="${COORD_GATED_REMOTE_PATTERN:-}"
_GATED_PATH_PATTERN="${COORD_GATED_PATH_PATTERN:-}"

_auth_ref_ok() {
  local blob="$1"
  # Round-2 (item 5): DECISION-[A-Z0-9-]+ under -i (case-insensitive) matched
  # "decision-tree"/"decision-making"/"decision-log" — any prose containing
  # those words satisfied the trust-root gate. It also matched this
  # protocol's OWN unrelated "DECISION-NEEDED" vocabulary (MAILBOX-template.md
  # § Message Grammar) — the opposite of an authorization, quoting a STATUS
  # tag would have satisfied the gate. Requiring a trailing digit closes both:
  # a real DECISION reference (DECISION-42, DECISION-2026-08-09-3) always
  # ends in one; neither false positive above does.
  printf '%s' "$blob" | grep -qiE \
    '(AUTH:|authorized[[:space:]]+by|human[[:space:]]+GO|human-GO|COORD-AUTH:|DECISION-[A-Z0-9-]*[0-9]|sign-off:|human[[:space:]]+sign-?off)' \
    && return 0
  [[ -n "${COORD_AUTH_REF:-}" ]] && return 0
  return 1
}

if [[ ( -n "$_GATED_REMOTE_PATTERN" || -n "$_GATED_PATH_PATTERN" ) && "$cmd_field" == *"git push"* ]]; then
  _push_gated=0
  _push_why=""
  _remotes=$(git remote -v 2>/dev/null || true)
  _cwd=$(pwd -P 2>/dev/null || pwd)
  if [[ -n "$_GATED_REMOTE_PATTERN" ]] && printf '%s\n' "$_remotes" "$_cwd" | grep -qiE "$_GATED_REMOTE_PATTERN"; then
    _push_gated=1
    _push_why="remote/cwd matches gated-remote pattern"
  fi
  if [[ -n "$_GATED_PATH_PATTERN" ]]; then
    _push_paths=$(git diff --name-only "@{upstream}..HEAD" 2>/dev/null || git diff --name-only "HEAD~3..HEAD" 2>/dev/null || true)
    if printf '%s\n' "$_push_paths" | grep -qiE "$_GATED_PATH_PATTERN"; then
      _push_gated=1
      _push_why="${_push_why:+$_push_why; }changed paths hit gated-path pattern"
    fi
  fi
  if [[ "$_push_gated" -eq 1 ]]; then
    _msgs=$(git log --format=%B "@{upstream}..HEAD" 2>/dev/null || git log -3 --format=%B 2>/dev/null || true)
    if _auth_ref_ok "$_msgs"; then
      echo "OK [gated-push]: gated target, authorization reference present in commit message(s) or COORD_AUTH_REF."
    else
      echo ""
      echo "FAIL [gated-push]: push touches a gated target without an authorization reference."
      echo "  reason: ${_push_why:-gated}"
      echo "  Include AUTH:/human GO/DECISION-…/sign-off: in the commit message, or export COORD_AUTH_REF=…"
      echo "  Ceiling: reference is actor-written — this blocks accidental publish, not determined fabrication."
      FAIL=1
    fi
  else
    echo "OK [gated-push]: push target not on the configured gated list."
  fi
elif [[ "$cmd_field" == *"git push"* ]]; then
  echo "INFO [gated-push]: no COORD_GATED_REMOTE_PATTERN / COORD_GATED_PATH_PATTERN configured — gate disabled."
fi

# ── check 6: always-on allowed_signers write gate (item 2, human-approved 2026-08-09) ──
# UNCONDITIONAL and NOT project-configurable, unlike check 5 above.
# allowed_signers is the trust root for every signature verification in this
# protocol (coord-verify.sh's `ssh-keygen -Y verify -f allowed_signers ...`)
# — a silent or careless edit here (a bad rotate, a forged row slipped in by
# a buggy script, a copy-paste mistake merging two coord-dirs' trust roots)
# can quietly downgrade what every reader trusts with no visible sign until
# an attack actually lands. Any commit-landing verb (see
# `_is_commit_landing_cmd` above — commit, merge, cherry-pick, rebase, am,
# revert, pull) OR `git push` touching a file named allowed_signers is
# BLOCKED unless an explicit authorization reference (same _auth_ref_ok
# pattern as check 5) is present.
#
# For a commit-landing verb, no NEW commit object exists yet to `git log`
# inspect — the reference must be in the COMMAND text itself (the -m message
# being typed right now, or a heredoc/file the caller is about to commit
# with). For `git push`, reuse check 5's git-log scan of already-made commits.
#
# DETECTION SCOPE (round-2, item 5; verb coverage widened round-3, item 1):
# `git diff --cached --name-only` alone misses `git commit -a` / `git commit
# -am` / `git commit <pathspec>` — all stage their own content AT COMMIT
# TIME, invisible to a check that only looks at what is ALREADY staged
# before the commit runs. Also checks the working-tree diff (`git diff
# --name-only`, tracked-file modifications not yet staged — exactly what
# `-a` would pick up) and the command text itself for a literal
# `allowed_signers` mention (catches an explicit pathspec argument even if,
# for some reason, the git diff calls above can't run). The same
# staged+working-tree+text-mention union now runs for merge/cherry-pick/
# rebase/am/revert/pull too, not just literal `git commit` — those verbs
# land a commit from the working tree or an existing ref just as surely,
# and over-detection here is explicitly safe (see below).
# A false positive here (flagging a commit that doesn't actually end up
# touching allowed_signers) just asks for an unnecessary auth reference —
# safe to err toward over-detection for a trust-root file.
#
# Ceiling (matches check 5's + README.md § Message Authenticity's "honest
# ceiling" voice): this does NOT stop a determined malicious co-resident
# process with write access to the coord-dir — filesystem permissions were
# never an isolation boundary in this protocol, and the reference string is
# actor-written, not cryptographically tied to the change. It stops an
# ACCIDENTAL or careless edit from slipping through unreviewed, and forces
# an auditable trail for a deliberate one. Full enforcement against a
# hostile co-resident needs OS-level process isolation — out of scope for a
# filesystem-perms-based protocol.
_touches_allowed_signers() {
  printf '%s\n' "$1" | grep -qE '(^|/)allowed_signers$'
}

if _is_commit_landing_cmd "$cmd_field" || _is_push_cmd "$cmd_field"; then
  _AS_TOUCHED=0
  if _is_commit_landing_cmd "$cmd_field"; then
    _as_paths=$(git diff --cached --name-only 2>/dev/null || true)
    _touches_allowed_signers "$_as_paths" && _AS_TOUCHED=1
    _as_wt_paths=$(git diff --name-only 2>/dev/null || true)
    _touches_allowed_signers "$_as_wt_paths" && _AS_TOUCHED=1
    unset _as_wt_paths
    printf '%s' "$cmd_field" | grep -qE '(^|[[:space:]/])allowed_signers([[:space:]]|$)' && _AS_TOUCHED=1
  fi
  if _is_push_cmd "$cmd_field"; then
    _as_paths=$(git diff --name-only "@{upstream}..HEAD" 2>/dev/null || git diff --name-only "HEAD~5..HEAD" 2>/dev/null || true)
    _touches_allowed_signers "$_as_paths" && _AS_TOUCHED=1
  fi
  if [[ "$_AS_TOUCHED" -eq 1 ]]; then
    _as_ref_ok=0
    _auth_ref_ok "$cmd_field" && _as_ref_ok=1
    if [[ "$_as_ref_ok" -ne 1 && "$cmd_field" == *"git push"* ]]; then
      _as_msgs=$(git log --format=%B "@{upstream}..HEAD" 2>/dev/null || git log -3 --format=%B 2>/dev/null || true)
      _auth_ref_ok "$_as_msgs" && _as_ref_ok=1
    fi
    if [[ "$_as_ref_ok" -eq 1 ]]; then
      echo "OK [allowed_signers-gate]: touches allowed_signers, authorization reference present."
    else
      echo ""
      echo "FAIL [allowed_signers-gate]: this commit/push touches allowed_signers without an authorization reference."
      echo "  allowed_signers is the trust root for every signature verification in this protocol —"
      echo "  an unreviewed change here can silently downgrade what every reader trusts."
      echo "  Include AUTH:/human GO/DECISION-…/sign-off: in the commit message, or export COORD_AUTH_REF=…"
      echo "  Ceiling: this blocks an accidental/unreviewed edit, not a determined co-resident forger — see README.md § Message Authenticity."
      FAIL=1
    fi
  fi
fi

# ── dump roster (informational) ───────────────────────────────────────────────

if [[ -n "$COORD_DIR" && -d "$COORD_DIR" ]]; then
  echo ""
  echo "--- Active roster (live presence files in $COORD_DIR) ---"
  find "$COORD_DIR" -maxdepth 1 -name "*.md" ! -name "QUEUE.md" ! -name "archive" | sort | while IFS= read -r f; do
    identity=$(basename "$f" .md)
    state=$(grep -o 'state[:=][[:space:]]*[A-Za-z-]*' "$f" 2>/dev/null | head -1 | sed 's/state[:=][[:space:]]*//' || true)
    state="${state:-unknown}"
    wos=$(grep "^current_wos:" "$f" 2>/dev/null | head -1 | cut -d: -f2- | tr -d ' ' || echo "none")
    echo "  $identity  state=$state  wos=$wos"
  done
fi

# ── result ────────────────────────────────────────────────────────────────────

echo ""
if [[ $FAIL -ne 0 ]]; then
  echo "PRE-COMMIT HOOK: FAILED. Resolve the issues above before committing."
  emit '{"permission":"deny","user_message":"Pre-commit hook blocked: unread mailbox, secret, and/or gated push without auth reference.","agent_message":"Read mailbox / remove secret / add an auth reference for gated push, then retry."}'
  exit 2
else
  echo "PRE-COMMIT HOOK: PASSED. Proceeding with commit."
  emit '{"permission":"allow"}'
  exit 0
fi
