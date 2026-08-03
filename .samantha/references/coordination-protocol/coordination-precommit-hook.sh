#!/usr/bin/env bash
# coordination-precommit-hook.sh — PreToolUse hook for git commit and push.
#
# PURPOSE:
#   Enforces coordination hygiene before any git commit or push in a dual-mode session:
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
#   if the Bash command contains "git commit" or "git push".
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

# ── self-filter: only run on git commit / git push ────────────────────────────
#
# SECURITY: fail-closed on ambiguity (N posture).
# If the command cannot be determined (unparseable JSON, missing parsers), all three
# checks run rather than silently passing. exit 0 only when the command is positively
# identified as NOT a commit/push. Ambiguity → checks run; positive non-commit → exit 0.

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
    # identification as not-a-commit — never on ambiguity (including missing parsers).
    echo "WARN [pre-commit hook]: Could not extract command from CLAUDE_TOOL_INPUT — running checks as precaution." >&2
    cmd_field="(command unknown — checks running as precaution)"
  elif [[ "$cmd_field" != *"git commit"* && "$cmd_field" != *"git push"* ]]; then
    emit '{"permission":"allow"}'; exit 0  # Positively not a commit/push — allow.
  fi
else
  # Standalone invocation (no CLAUDE_TOOL_INPUT): run all checks.
  cmd_field="git commit (standalone invocation)"
fi

echo "[pre-commit hook] Checking coordination hygiene before: $cmd_field"
FAIL=0

# ── check 1: mailbox-read gate ────────────────────────────────────────────────
#
# Per-instance offset file tracks how far into orchestrator.md this agent has
# acknowledged. File: <coord-dir>/.watch-state/<id>/orchestrator.md.size
# (byte offset, plain text). This is the SAME file that watch-coordination.sh
# persists its read-time EOF to on every wake — auto-maintained by the watcher
# with no manual wc -c step and no drift between watcher state and hook state.
# Bytes after the stored offset are "unread". We block if any contain a message
# header addressed to MY_ID OR the broadcast token ALL.
#
# No offset file on first run → auto-initialize at current EOF, so pre-existing
# sibling traffic never blocks a fresh implementer. The watcher auto-advances
# the offset file on every wake; the hook reads it directly. In standalone mode
# (no active watcher), initialize manually — see the suggestion printed below.
#
# Why offset-file, not "last line I posted in orchestrator.md":
#   - Implementers NEVER post into orchestrator.md (they post in their own file).
#     The old grep-for-my-sent-line heuristic always returned 0 for implementers,
#     marking every message as unread → permanent block on first commit (deadlock).
#   - The offset file tracks what the agent has actually acknowledged — no
#     inference, no deadlock, no dependency on the watcher being armed first.
#   - Scanning for "→ ALL" in the delta catches broadcast DEPLOY-WINDOW signals
#     that the old pattern (→ MY_ID only) silently missed.

if [[ -n "$COORD_DIR" && -n "$MY_ID" ]]; then
  # Inbox selection follows the STAR topology: the orchestrator's inbox is every
  # PEER file in the coord-dir; a spoke's inbox is orchestrator.md only. Never
  # gate on your OWN outbox — heartbeat/dead-man alerts posted there (→ ALL)
  # would self-trigger the gate on every call forever.
  INBOX_FILES=()
  if [[ "$MY_ID" == "orchestrator" ]]; then
    while IFS= read -r _f; do INBOX_FILES+=("$_f"); done < <(
      find "$COORD_DIR" -maxdepth 1 -name "*.md" ! -name "orchestrator.md" ! -name "QUEUE.md" ! -name "*.archive.md" 2>/dev/null | sort)
  else
    [[ -f "$COORD_DIR/orchestrator.md" ]] && INBOX_FILES+=("$COORD_DIR/orchestrator.md")
  fi
  if [[ ${#INBOX_FILES[@]} -eq 0 ]]; then
    echo "INFO [mailbox-read gate]: no inbox files for '$MY_ID' in $COORD_DIR — skipping (not in dual mode?)."
  fi
  for ORCH_FILE in ${INBOX_FILES[@]+"${INBOX_FILES[@]}"}; do
    RECEIPT_FILE="$COORD_DIR/.watch-state/$MY_ID/$(basename "$ORCH_FILE").size"
    orch_sz=$(wc -c < "$ORCH_FILE" 2>/dev/null | tr -d ' ' || echo 0)

    if [[ ! -f "$RECEIPT_FILE" ]]; then
      # No receipt: first run for this identity. Auto-initialize at current EOF
      # so pre-existing sibling traffic does not block a fresh implementer.
      # All content before this point is treated as already acknowledged.
      mkdir -p "$(dirname "$RECEIPT_FILE")" 2>/dev/null || true
      chmod 700 "$(dirname "$RECEIPT_FILE")" 2>/dev/null || true
      printf '%s\n' "$orch_sz" > "$RECEIPT_FILE" 2>/dev/null || true
      echo "OK [mailbox-read gate]: first run — receipt initialized at ${orch_sz}B."
    else
      receipt_sz=$(cat "$RECEIPT_FILE" 2>/dev/null | tr -d '[:space:]' || echo 0)
      # F6: validate receipt integrity — reject non-integer or forged oversized offsets.
      if ! [[ "$receipt_sz" =~ ^[0-9]+$ ]] || [[ "$receipt_sz" -gt "$orch_sz" ]]; then
        echo "WARN [mailbox-read gate]: receipt value ('${receipt_sz}') is invalid or exceeds file size; treating as 0 (unread)." >&2
        receipt_sz=0
      fi

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
          echo "After reading, re-arm the watcher — it auto-advances the offset file on every wake."
          echo "In standalone mode (no active watcher), advance the offset manually:"
          printf "  wc -c < %q | tr -d ' ' > %q\n" "$ORCH_FILE" "$RECEIPT_FILE"
          FAIL=1
        else
          echo "OK [mailbox-read gate]: new content in $ORCH_FILE not addressed to '$MY_ID' or 'ALL'."
        fi
      else
        echo "OK [mailbox-read gate]: offset current (${receipt_sz}B = file size)."
      fi
    fi
  done
else
  echo "INFO [mailbox-read gate]: COORD_DIR or MY_ID not set — skipping."
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
if [[ -n "$_CANON_DOCS_DIR" && -n "$_CANON_CITE_PATTERN" && ( "$cmd_field" == *"git commit"* || "$cmd_field" == *"git push"* || "$cmd_field" == *"standalone"* ) ]]; then
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
  printf '%s' "$blob" | grep -qiE \
    '(AUTH:|authorized[[:space:]]+by|human[[:space:]]+GO|human-GO|COORD-AUTH:|DECISION-[A-Z0-9-]+|sign-off:|human[[:space:]]+sign-?off)' \
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
