#!/usr/bin/env bash
# coord-gate-audit.sh — mechanical gate-audit for STAGED (or any) queue rows.
#
# Greps a queue row's cited files / canon sections for THREE confirmed gate kinds:
#   (a) code-comment markers: <gate-marker-pattern> (default: human-gated / [NO-CANON])
#       — EXCLUDES <acl-exclude-pattern> (default: owner-gated) — an in-repo ACL
#         marker is not automatically a process/sign-off gate; this exclusion is
#         itself just a default and can be overridden.
#   (b) canon-prose: provisional / implementer-proposed / pending a balance-tuning pass
#       (+ [NO-CANON] in cited canon-doc sections)
#   (c) standing safety-list keyword hits on the row text + cited paths
#       (see --safety-pattern; default covers auth/payments/MFA/admin-gating/RBAC,
#        AI-safety/AI-dialogue, destructive migrations, prod, force-push, new
#        external dependencies, docker-compose topology — adapt to the project's
#        own CLAUDE.md / constitution safety list, do not silently shorten it)
#
# Gates compound: every hit is listed; a single gated:YES is insufficient once a
# row can carry more than one kind.
#
# CEILING (stated so it is not later over-trusted): mechanical presence of
# gate-shaped markers near cited paths — this does not replace human review of
# whether a gate still applies, and a row with zero hits is not proof the row
# is actually ungated (it only means none of the configured markers fired).
#
# All markers/roots are CONFIGURABLE — no project-specific default is assumed
# for --code-root / --docs-root. The marker regexes ship with illustrative
# generic defaults (documented above) that a project should tune to its own
# vocabulary via --gate-marker-pattern / --safety-pattern / --acl-exclude-pattern.
#
# Usage:
#   coord-gate-audit.sh --queue <queue-*.md> [--wo WO-ID] --code-root PATH --docs-root PATH
#   coord-gate-audit.sh --queue queue-<repo>.md                     # sweep all rows
#   coord-gate-audit.sh --queue queue-<repo>.md --wo WO-EXAMPLE-ID
#
# Exit 0 always after a successful run (audit report). Exit 2 on usage/IO error.
set -euo pipefail

QUEUE=""
WO_FILTER=""
SELF_TEST=0
CODE_ROOT="${COORD_GATE_CODE_ROOT_DEFAULT:-}"
DOCS_ROOT="${COORD_GATE_DOCS_ROOT_DEFAULT:-}"
GATE_MARKER_PATTERN="${COORD_GATE_MARKER_PATTERN:-human-gated|\[NO-CANON\]}"
ACL_EXCLUDE_PATTERN="${COORD_GATE_ACL_EXCLUDE_PATTERN:-owner-gated}"
SAFETY_PATTERN="${COORD_GATE_SAFETY_PATTERN:-auth(?:entication)?/?login|\\bpayments?\\b|\\bMFA\\b|admin-gating|\\bRBAC\\b|AI-safety|AI[\\s/-]dialogue|destructive\\s+migrations?|force-push|history\\s+rewrite|new\\s+external\\s+dependenc(?:y|ies)|docker-compose\\s+topology}"

usage() {
  cat >&2 <<'EOF'
Usage: coord-gate-audit.sh --queue <queue-*.md> [--wo WO-ID] [--code-root PATH] [--docs-root PATH]
       coord-gate-audit.sh --self-test

  Mechanical gate-audit. Greps cited paths for 3 gate kinds; excludes
  ACL-noise markers by default. Lists every gate found (gates compound).

  --queue               Path to a queue-*.md file (required unless --self-test)
  --wo                  Audit a single WO-N (default: sweep all non-DONE/CLOSED rows)
  --code-root           Product code root (no default — pass explicitly)
  --docs-root           Canon/docs root (no default — pass explicitly)
  --code-subdir DIR     Repeatable. High-signal subdir under code-root to search first
                        (e.g. src, app). Default: search code-root directly.
  --docs-subdir DIR     Repeatable. High-signal subdir under docs-root to search first
                        (e.g. FEATURES, ADR). Default: search docs-root directly.
  --gate-marker-pattern Regex for kind-a code-comment gate markers
                        (default: human-gated|\[NO-CANON\])
  --acl-exclude-pattern Regex for ACL-only markers that must NOT count as kind-a
                        (default: owner-gated)
  --safety-pattern      Regex for kind-c standing safety-list vocabulary
                        (default: a generic auth/payments/MFA/RBAC/AI-safety/
                        migrations/force-push/new-deps/docker-compose list —
                        tune to the project's own safety list)
  --self-test           Prove kind-a fires on the gate marker and does NOT fire
                        on the ACL-exclude marker alone
EOF
  exit 2
}

CODE_SUBDIRS=()
DOCS_SUBDIRS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --queue) QUEUE="${2:-}"; shift 2 ;;
    --wo) WO_FILTER="${2:-}"; shift 2 ;;
    --code-root) CODE_ROOT="${2:-}"; shift 2 ;;
    --docs-root) DOCS_ROOT="${2:-}"; shift 2 ;;
    --code-subdir) CODE_SUBDIRS+=("${2:-}"); shift 2 ;;
    --docs-subdir) DOCS_SUBDIRS+=("${2:-}"); shift 2 ;;
    --gate-marker-pattern) GATE_MARKER_PATTERN="${2:-}"; shift 2 ;;
    --acl-exclude-pattern) ACL_EXCLUDE_PATTERN="${2:-}"; shift 2 ;;
    --safety-pattern) SAFETY_PATTERN="${2:-}"; shift 2 ;;
    --self-test) SELF_TEST=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

if [[ "$SELF_TEST" -eq 1 ]]; then
  COORD_GATE_MARKER_PATTERN="$GATE_MARKER_PATTERN" COORD_GATE_ACL_EXCLUDE_PATTERN="$ACL_EXCLUDE_PATTERN" python3 - <<'PY'
import os, re, sys
marker_pat = os.environ["COORD_GATE_MARKER_PATTERN"]
acl_pat = os.environ["COORD_GATE_ACL_EXCLUDE_PATTERN"]
# Negative lookbehind only works cleanly when acl_pat is a simple literal-ish
# token; that is the documented default shape ("owner-gated").
KIND_A = re.compile(rf"(?i)(?<!{acl_pat[:-1] if acl_pat.endswith('-') else acl_pat}-)(?:{marker_pat})")
samples = [
    (f"{acl_pat} only", f"only SETS the value ({acl_pat} + clamped)", False),
    ("gate-marker", "the cutover is human-gated, spec §8", True),
    ("NO-CANON", "[NO-CANON] thresholds", True),
    ("mixed", f"{acl_pat} human-gated both", True),
]
fail = 0
for name, text, expect in samples:
    got = bool(KIND_A.search(text))
    ok = got == expect
    print(f"  {'PASS' if ok else 'FAIL'}: {name} expect={expect} got={got}")
    if not ok:
        fail += 1
if fail:
    print("coord-gate-audit --self-test: FAILED (ACL exclusion broken)")
    sys.exit(1)
print("coord-gate-audit --self-test: OK (ACL marker excluded; gate marker fires)")
sys.exit(0)
PY
  exit $?
fi

[[ -n "$QUEUE" && -f "$QUEUE" ]] || usage
[[ -n "$CODE_ROOT" && -n "$DOCS_ROOT" ]] || {
  echo "ERROR: --code-root and --docs-root are required (no project default assumed)." >&2
  usage
}

export COORD_GATE_QUEUE="$QUEUE"
export COORD_GATE_WO="$WO_FILTER"
export COORD_GATE_CODE_ROOT="$CODE_ROOT"
export COORD_GATE_DOCS_ROOT="$DOCS_ROOT"
export COORD_GATE_MARKER_PATTERN="$GATE_MARKER_PATTERN"
export COORD_GATE_ACL_EXCLUDE_PATTERN="$ACL_EXCLUDE_PATTERN"
export COORD_GATE_SAFETY_PATTERN="$SAFETY_PATTERN"
# Space-joined subdir lists (subdirs are expected to be plain relative paths,
# no spaces — matches typical repo layout conventions).
export COORD_GATE_CODE_SUBDIRS="${CODE_SUBDIRS[*]+"${CODE_SUBDIRS[*]}"}"
export COORD_GATE_DOCS_SUBDIRS="${DOCS_SUBDIRS[*]+"${DOCS_SUBDIRS[*]}"}"

python3 <<'PY'
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

queue_path = Path(os.environ["COORD_GATE_QUEUE"])
wo_filter = (os.environ.get("COORD_GATE_WO") or "").strip()
code_root = Path(os.environ["COORD_GATE_CODE_ROOT"])
docs_root = Path(os.environ["COORD_GATE_DOCS_ROOT"])
code_subdirs = [s for s in os.environ.get("COORD_GATE_CODE_SUBDIRS", "").split() if s]
docs_subdirs = [s for s in os.environ.get("COORD_GATE_DOCS_SUBDIRS", "").split() if s]

# --- patterns (configurable via CLI flags / env, generic defaults above) ---
_marker_src = os.environ["COORD_GATE_MARKER_PATTERN"]
_acl_src = os.environ["COORD_GATE_ACL_EXCLUDE_PATTERN"]
_safety_src = os.environ["COORD_GATE_SAFETY_PATTERN"]

# Kind (a): process gate markers. Explicitly do NOT match the ACL-exclude marker.
KIND_A = re.compile(rf"(?i)(?<!{_acl_src}-)(?:{_marker_src})")
# Guard: any line whose only "gated" token is the ACL-exclude marker must not fire kind A.
ACL_EXCLUDE_ONLY = re.compile(rf"(?i){_acl_src}")

# Kind (b): canon-prose gates near cited doc sections
KIND_B = re.compile(
    r"(?i)(?:\bprovisional\b|\bimplementer-proposed\b|"
    r"pending\s+a\s+balance-tuning\s+pass|pending\s+balance-tuning|"
    r"\[NO-CANON\])"
)

# Kind (c): standing safety-list (configurable — tune to the project's own list;
# do not silently shorten it once tuned).
KIND_C = re.compile(rf"(?i)(?:{_safety_src})")

CITE_RE = re.compile(
    r"(?P<path>[\w./-]+\.(?:py|ts|tsx|js|jsx|md|yml|yaml|toml|sql))"
    r"(?::(?P<line>\d+)(?:-(?P<line2>\d+))?)?"
)

SKIP_STATUS = re.compile(r"\b(DONE|CLOSED|MERGED)\b", re.I)


def parse_tables(text: str) -> list[dict]:
    """Parse markdown pipe-tables; return list of row dicts keyed by header."""
    rows: list[dict] = []
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip().startswith("|"):
            i += 1
            continue
        # header
        header_cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if i + 1 >= len(lines) or not re.match(r"^\|?\s*:?-+:?\s*\|", lines[i + 1]):
            i += 1
            continue
        i += 2  # skip separator
        while i < len(lines) and lines[i].strip().startswith("|"):
            cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
            # pad / trim to header length
            if len(cells) < len(header_cells):
                cells += [""] * (len(header_cells) - len(cells))
            cells = cells[: len(header_cells)]
            row = {header_cells[j]: cells[j] for j in range(len(header_cells))}
            wo = row.get("WO-N") or row.get("WO") or ""
            if wo and not wo.startswith("---") and wo.lower() != "wo-n":
                rows.append(row)
            i += 1
        continue
    return rows


_RESOLVE_CACHE: dict[str, list[Path]] = {}


def resolve_cite(basename_or_rel: str) -> list[Path]:
    """Resolve a citation path against code_root and docs_root."""
    if basename_or_rel in _RESOLVE_CACHE:
        return _RESOLVE_CACHE[basename_or_rel]
    p = Path(basename_or_rel)
    found: list[Path] = []
    candidates: list[Path] = []
    if p.is_absolute() and p.is_file():
        _RESOLVE_CACHE[basename_or_rel] = [p]
        return [p]
    for root, subdirs in ((code_root, code_subdirs), (docs_root, docs_subdirs)):
        direct = root / basename_or_rel
        if direct.is_file():
            candidates.append(direct)
        name = p.name
        # Prefer configured high-signal subdirs first (avoids a slow full-tree
        # rglob on huge repos when possible); falls back to the root itself.
        search_roots = []
        for sub in subdirs:
            sp = root / sub
            if sp.is_dir():
                search_roots.append(sp)
        if not search_roots:
            search_roots = [root]
        try:
            for sr in search_roots:
                for hit in sr.rglob(name):
                    if not hit.is_file():
                        continue
                    s = str(hit)
                    if any(x in s for x in ("node_modules", ".git", "__pycache__", "archive/")):
                        continue
                    candidates.append(hit)
                    if len(candidates) >= 6:
                        break
                if len(candidates) >= 6:
                    break
        except OSError:
            pass
    seen: set = set()
    for c in candidates:
        rp = c.resolve()
        if rp not in seen:
            seen.add(rp)
            found.append(c)
    _RESOLVE_CACHE[basename_or_rel] = found
    return found


def line_window(path: Path, line: int | None, radius: int = 12) -> str:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    if not line or line < 1:
        # whole file, but cap for huge files
        if len(text) > 400_000:
            return text[:200_000] + "\n" + text[-200_000:]
        return text
    lines = text.splitlines()
    lo = max(0, line - 1 - radius)
    hi = min(len(lines), line - 1 + radius + 1)
    return "\n".join(lines[lo:hi])


def kind_a_hits(snippet: str, path: Path, base_line: int | None = None) -> list[str]:
    """Return kind-a hits; cap verbosity at 6 + '+N more'."""
    out: list[str] = []
    lines = snippet.splitlines()
    # If snippet is a window, base_line is the first real line number
    start_n = (base_line - 0) if base_line and base_line > 0 else None
    # Prefer mapping via full-file index when we have the whole file
    full_index: dict[str, list[int]] = {}
    try:
        for n, L in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            full_index.setdefault(L, []).append(n)
    except OSError:
        full_index = {}

    for offset, line in enumerate(lines):
        if ACL_EXCLUDE_ONLY.search(line) and not KIND_A.search(line):
            continue  # ACL-noise only
        m = KIND_A.search(line)
        if not m:
            continue
        nums = full_index.get(line) or []
        ln = str(nums[0]) if nums else (
            str(start_n + offset) if start_n is not None else "?"
        )
        out.append(f"kind-a code-comment:{m.group(0)} @ {path.name}:{ln}")
    if len(out) > 6:
        more = len(out) - 6
        out = out[:6] + [f"kind-a code-comment:… +{more} more in {path.name}"]
    return out


def kind_b_hits(snippet: str, path: Path) -> list[str]:
    out: list[str] = []
    if path.suffix.lower() != ".md":
        return out
    seen = set()
    for m in KIND_B.finditer(snippet):
        tok = m.group(0)
        key = tok.lower()
        if key in seen:
            continue
        seen.add(key)
        # Prefer path with line if we can find it
        line_no = "?"
        try:
            for n, L in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
                if tok in L or key in L.lower():
                    line_no = str(n)
                    break
        except OSError:
            pass
        out.append(f"kind-b canon-prose:{tok} @ {path.name}:{line_no}")
    return out


def kind_c_hits(text: str, source: str) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for m in KIND_C.finditer(text):
        tok = m.group(0)
        low = tok.lower()
        if low in seen:
            continue
        seen.add(low)
        out.append(f"kind-c safety-list:{tok} @ {source}")
    return out


def audit_row(row: dict) -> tuple[str, list[str], str]:
    wo = row.get("WO-N") or ""
    blob = " | ".join(f"{k}: {v}" for k, v in row.items() if v)
    cites = list(CITE_RE.finditer(blob))
    gates: list[str] = []

    # Kind C on the row text itself (title/notes often name the safety surface)
    gates.extend(kind_c_hits(blob, f"queue-row:{wo}"))

    resolved_files: list[tuple[Path, int | None]] = []
    for m in cites:
        rel = m.group("path")
        line = int(m.group("line")) if m.group("line") else None
        # skip obvious non-repo noise
        if rel.startswith("http"):
            continue
        for fp in resolve_cite(rel):
            resolved_files.append((fp, line))

    # de-dupe files but keep closest line cite
    by_file: dict[Path, int | None] = {}
    for fp, line in resolved_files:
        rp = fp.resolve()
        if rp not in by_file or (line and not by_file[rp]):
            by_file[Path(rp)] = line

    for fp, line in by_file.items():
        # No line cite → whole-file scan (capped in kind_a_hits).
        # Line cite → ±40 lines around the cite (catches nearby markers).
        radius = 40 if line else 0
        snippet = line_window(fp, line, radius=radius) if line else line_window(fp, None)
        base = max(1, line - radius) if line else None
        gates.extend(kind_a_hits(snippet, fp, base_line=base))
        gates.extend(kind_b_hits(snippet, fp))
        # Kind C on cited *file* bodies is limited: row text already carries the
        # safety-list vocabulary for queue audits. Scanning whole files for
        # incidental safety-list-adjacent words is noise, so this reuses the
        # same configured pattern rather than a separate "strong" subset.
        for m in KIND_C.finditer(snippet):
            gates.append(f"kind-c safety-list:{m.group(0)} @ {fp}")

    # de-dupe gate strings while preserving order
    uniq: list[str] = []
    seen_g = set()
    for g in gates:
        if g not in seen_g:
            seen_g.add(g)
            uniq.append(g)

    if uniq:
        verdict = "gated:YES pending review"
    else:
        verdict = "gated:no (no configured gate markers hit on cited paths/row text)"
    return wo, uniq, verdict


def main() -> int:
    text = queue_path.read_text(encoding="utf-8", errors="replace")
    rows = parse_tables(text)
    if not rows:
        print(f"coord-gate-audit: no table rows in {queue_path}", file=sys.stderr)
        return 2

    print(f"coord-gate-audit — queue={queue_path}")
    print(f"  code-root={code_root}")
    print(f"  docs-root={docs_root}")
    print(f"  acl-exclude-pattern={_acl_src} (ACL noise, not a process gate)")
    print()

    audited = 0
    flagged = 0
    for row in rows:
        wo = row.get("WO-N") or ""
        if wo_filter and wo != wo_filter:
            continue
        status = row.get("Status") or ""
        # Still allow explicit --wo on DONE rows; for sweeps skip DONE/CLOSED
        if not wo_filter and SKIP_STATUS.search(status):
            continue
        audited += 1
        wo_id, gates, verdict = audit_row(row)
        title = (row.get("Title") or "")[:60]
        print(f"=== {wo_id} — {title}")
        print(f"  status: {status}")
        print(f"  {verdict}")
        if gates:
            flagged += 1
            # List every gate (compound)
            for g in gates:
                print(f"  - {g}")
        else:
            print("  - (none)")
        print()

    if wo_filter and audited == 0:
        print(f"coord-gate-audit: WO not found: {wo_filter}", file=sys.stderr)
        return 2

    print(f"SUMMARY: audited={audited} flagged={flagged} clean={audited - flagged}")
    print("CEILING: mechanical presence of gate-shaped markers near cited paths —")
    print("  does not replace human review of whether a gate still applies.")
    return 0


sys.exit(main())
PY
