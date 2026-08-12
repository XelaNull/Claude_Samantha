#!/usr/bin/env python3
"""queue-lint.py — read-only schema check for queue-<repo>.md /
backlog-<repo>.md files against queue_schema.py's canonical shape.

Usage:
  python3 queue-lint.py --dir <coord-dir>                  # lint every project's queue file
  python3 queue-lint.py --dir <coord-dir> --all             # + every backlog file's quick-ref tables
  python3 queue-lint.py --dir <coord-dir> queue-foo.md       # lint one specific file
  python3 queue-lint.py --dir <coord-dir> --cap 24           # override the queue row-cap check
  python3 queue-lint.py --dir <coord-dir> --exclude queue-x.md,queue-y.md

--dir defaults to $COORD_DIR if set, else ./.samantha/coord relative to cwd.

Exit code 0 = clean, 1 = violations found. No filesystem is written to.

Framework tooling (backported from a downstream deployment 2026-08-12): the
underlying problem this exists to prevent is that no canonical writer/lint
ever existed for queue files at that site, so 7-13 incompatible ad hoc table
schemas accumulated per file over weeks of different agents hand-formatting
rows — including one row that stayed miscategorized as buildable-now despite
its own text saying "confirmed shipped, already done." This does not fix
drift by itself — it only reports it. queue-append.py is the paired writer
meant to prevent new drift going forward; run this lint periodically (e.g.
each proactive-loop discovery pass, or before a manual rebalance) to catch
whatever slips through hand-edits anyway.
"""
import argparse
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import queue_schema as qs

DEFAULT_CAP = 24


def lint_queue_file(path, cap=DEFAULT_CAP):
    """Strict check: this file's rows must match the canonical 6-column
    schema exactly, no duplicate WO-ids, READY section must not exceed cap."""
    violations = []
    if not os.path.isfile(path):
        return violations
    entries = qs.parse_table(path)
    seen_ids = {}
    ready_count = 0
    for e in entries:
        line, row = e["line"], e["row"]
        header = e["header"]
        if header != [c.lower() for c in qs.CANONICAL_COLUMNS]:
            violations.append(qs.Violation(
                "ERROR",
                f"table header {header} != canonical {[c.lower() for c in qs.CANONICAL_COLUMNS]}",
                line,
            ))
            continue  # column positions are meaningless if the header itself drifted
        if len(e["cells"]) != len(qs.CANONICAL_COLUMNS):
            violations.append(qs.Violation(
                "ERROR",
                f"row has {len(e['cells'])} cells, canonical schema has {len(qs.CANONICAL_COLUMNS)}",
                line,
            ))
        violations.extend(qs.validate_row(row, line=line))
        wid = qs.wo_id(row)
        if wid != qs.NO_ID_PLACEHOLDER:
            if wid in seen_ids:
                violations.append(qs.Violation(
                    "ERROR", f"duplicate WO-id, first seen at line {seen_ids[wid]}", line, wid,
                ))
            else:
                seen_ids[wid] = line
        status = qs.STATUS_ALIAS.get(qs.row_get(row, "status").strip().upper(), qs.row_get(row, "status").strip().upper())
        if status == "PENDING":
            ready_count += 1
    if ready_count > cap:
        violations.append(qs.Violation(
            "ERROR", f"{ready_count} READY/PENDING rows in live queue exceeds the {cap}-row cap "
            f"— overflow belongs in backlog-{os.path.basename(path).replace('queue-', '')}",
        ))
    return violations


def lint_backlog_quickref(path):
    """Lenient check on a backlog file's own quick-reference tables only
    (NEEDS-TRIAGE / Gated-Parked / READY-over-cap) — a verbatim historical
    dump further down a backlog file intentionally preserves whatever legacy
    schema it always had and is not linted."""
    violations = []
    if not os.path.isfile(path):
        return violations
    with open(path, errors="replace") as f:
        text = f.read()
    marker = "## Full original content"
    head = text.split(marker, 1)[0] if marker in text else text
    for e in qs.parse_table_text(head):
        row = e["row"]
        if qs.row_get(row, "wo", "id"):
            violations.extend(qs.validate_row(row, line=e["line"]))
    return violations


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", default=os.environ.get("COORD_DIR", os.path.join(".samantha", "coord")),
                     help="coord-dir containing queue-<repo>.md / backlog-<repo>.md (default: $COORD_DIR or ./.samantha/coord)")
    ap.add_argument("--cap", type=int, default=DEFAULT_CAP)
    ap.add_argument("--all", action="store_true", help="also lint every backlog-<repo>.md's quick-ref tables")
    ap.add_argument("--exclude", default="", help="comma-separated queue-<repo>.md basenames to skip in the default sweep")
    ap.add_argument("files", nargs="*", help="specific file(s) to lint instead of the default sweep")
    args = ap.parse_args()

    coord_dir = args.dir
    exclude = {e.strip() for e in args.exclude.split(",") if e.strip()}

    if args.files:
        targets = [f if os.path.isabs(f) else os.path.join(coord_dir, f) for f in args.files]
    else:
        targets = sorted(
            p for p in glob.glob(f"{coord_dir}/queue-*.md")
            if os.path.basename(p) not in exclude
        )

    total = 0
    for path in targets:
        v = lint_queue_file(path, cap=args.cap)
        rel = os.path.basename(path)
        if v:
            print(f"\n{rel}: {len(v)} issue(s)")
            for viol in v:
                print(f"  {viol}")
        else:
            print(f"{rel}: clean")
        total += len(v)

    if args.all:
        for path in sorted(glob.glob(f"{coord_dir}/backlog-*.md")):
            v = lint_backlog_quickref(path)
            rel = os.path.basename(path)
            if v:
                print(f"\n{rel} (quick-ref tables): {len(v)} issue(s)")
                for viol in v:
                    print(f"  {viol}")
            total += len(v)

    print(f"\n{'PASS' if total == 0 else 'FAIL'} — {total} total violation(s) across {len(targets)} file(s)")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
