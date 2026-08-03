#!/usr/bin/env bash
# coord-session-healthcheck.sh — third clock outside the monitor/heartbeat pair.
#
# Alert ONLY when BOTH are true over --window seconds:
#   1. no write under the coord-dir (any tracked mailbox / queue / presence)
#   2. no git commit AND no worktree file mtime change under watched repo roots
#
# This is session-external: intended for cron / launchd, not inside a live agent.
# A healthy mid-build seat that is quiet on the mailbox will NOT trip this —
# WT/commit activity counts as work product.
#
# Usage:
#   coord-session-healthcheck.sh --dir <coord-dir> [--window <secs>] [--repo <path>]...
# Exit 0 = healthy (or insufficient history); exit 1 = QUIET-SESSION alert fired.
#
# No default --repo list is assumed — pass every repo/worktree this seat is
# expected to be touching. With zero --repo flags the script still checks the
# coord-dir alone (commit/WT signal degrades to "unknown", never fires early).
set -euo pipefail

COORD_DIR=""
WINDOW=2700   # 45 min default
REPOS=()

usage() {
  echo "Usage: $0 --dir <coord-dir> [--window <secs>] [--repo <path>]..." >&2
  echo "  Alert if BOTH no coord-dir write AND no commit/WT touch over --window." >&2
  echo "  Pass one --repo per watched git working tree; none => coord-dir-only check." >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) COORD_DIR="${2:-}"; shift 2 ;;
    --window) WINDOW="${2:-}"; shift 2 ;;
    --repo) REPOS+=("${2:-}"); shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$COORD_DIR" && -d "$COORD_DIR" ]] || usage
mkdir -p "$COORD_DIR/.watch-state/_session-health"

# Python for portable mtime/commit scanning (macOS+Linux).
export COORD_DIR WINDOW
# shellcheck disable=SC2016
python3 - "$WINDOW" "$COORD_DIR" "${REPOS[@]+"${REPOS[@]}"}" <<'PY'
import os, sys, subprocess, time
from pathlib import Path

window = int(sys.argv[1])
coord = Path(sys.argv[2])
repos = [Path(p) for p in sys.argv[3:]]
now = time.time()
cutoff = now - window

def mtime(p: Path) -> float:
    try:
        return p.stat().st_mtime
    except OSError:
        return 0.0

newest_coord = 0.0
for pat in ("*.md", "migration-chain.status"):
    for f in coord.glob(pat):
        if f.name.startswith("."):
            continue
        newest_coord = max(newest_coord, mtime(f))

newest_commit = 0.0
newest_wt = 0.0
skip_parts = {".git", "node_modules", ".venv", "dist", "build", "__pycache__"}

for repo in repos:
    git_dir = repo / ".git"
    if not (git_dir.exists() or git_dir.is_file()):
        continue
    try:
        out = subprocess.check_output(
            ["git", "-C", str(repo), "log", "-1", "--format=%ct"],
            stderr=subprocess.DEVNULL, text=True,
        ).strip()
        if out:
            newest_commit = max(newest_commit, float(out))
    except (subprocess.CalledProcessError, ValueError):
        pass
    # Cap walk — sample recent activity without scanning huge trees forever
    n = 0
    try:
        for root, dirs, files in os.walk(repo):
            dirs[:] = [d for d in dirs if d not in skip_parts and not d.startswith(".")]
            for name in files:
                if name.startswith("."):
                    continue
                fp = Path(root) / name
                newest_wt = max(newest_wt, mtime(fp))
                n += 1
                if n >= 8000:
                    break
            if n >= 8000:
                break
    except OSError:
        pass

newest_work = max(newest_commit, newest_wt)
coord_age = int(now - newest_coord) if newest_coord else 999999
work_age = int(now - newest_work) if newest_work else 999999

print(f"session-healthcheck: window={window}s now={int(now)} repos={len(repos)}")
print(f"  newest coord-dir write: {int(newest_coord)} (age {coord_age}s)")
print(f"  newest commit/WT touch: {int(newest_work)} (age {work_age}s; commit={int(newest_commit)} wt={int(newest_wt)})")

if not repos:
    print("  NOTE: no --repo passed — commit/WT signal is trivially absent; this run")
    print("  only proves coord-dir silence, not session abandonment. Pass --repo for a real check.")

if newest_coord < cutoff and newest_work < cutoff:
    print()
    print(f"⚠️ QUIET-SESSION: no coord-dir write AND no commit/WT touch for ≥{window}s")
    print("  Both monitor/heartbeat can be ALIVE while the session is abandoned — investigate.")
    sys.exit(1)

print("OK: activity observed within window (coord and/or work product).")
sys.exit(0)
PY
