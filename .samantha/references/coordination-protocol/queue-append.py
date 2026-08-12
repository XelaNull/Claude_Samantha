#!/usr/bin/env python3
"""queue-append.py — the ONE sanctioned way to add a WO row to
queue-<repo>.md. Validates against queue_schema.py before writing anything,
refuses duplicate WO-ids, and auto-routes overflow to backlog-<repo>.md
instead of silently blowing past the row cap.

Usage:
  python3 queue-append.py --dir <coord-dir> --project foo \\
      --wo WO-FIX-THING --priority HIGH --status PENDING \\
      --verified "app.py:120" \\
      --description "One-line description of the work."

  # a claimed, in-progress row:
  python3 queue-append.py --dir <coord-dir> --project foo \\
      --wo WO-BUILD-X --priority MED --status CURRENT --claimed impl-foo \\
      --description "..."

--dir defaults to $COORD_DIR if set, else ./.samantha/coord relative to cwd.

Any agent (Orchestrator or Implementer) hand-editing a queue-<repo>.md table
directly instead of using this script recreates the schema-drift problem
this tool exists to prevent (a downstream site accumulated 7-13 incompatible
ad hoc table variants per file before this was built). Use this instead.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import queue_schema as qs

DEFAULT_CAP = 24


def existing_wo_ids(coord_dir, project):
    ids = set()
    for prefix in ("queue-", "backlog-"):
        path = f"{coord_dir}/{prefix}{project}.md"
        if not os.path.isfile(path):
            continue
        with open(path, errors="replace") as f:
            text = f.read()
        for e in qs.parse_table_text(text):
            wid = qs.wo_id(e["row"])
            if wid != qs.NO_ID_PLACEHOLDER:
                ids.add(wid)
    return ids


def count_ready(qpath):
    if not os.path.isfile(qpath):
        return 0
    n = 0
    for e in qs.parse_table(qpath):
        status = qs.row_get(e["row"], "status").strip().upper()
        status = qs.STATUS_ALIAS.get(status, status)
        if status == "PENDING":
            n += 1
    return n


def insert_row(path, row_line, section_marker):
    """Insert row_line as the last row under the <!-- SECTION --> comment
    in path, or append a new section if the comment doesn't exist yet."""
    with open(path, errors="replace") as f:
        lines = f.readlines()
    if section_marker in "".join(lines):
        idx = next(i for i, l in enumerate(lines) if section_marker in l)
        j = idx + 1
        while j < len(lines) and lines[j].strip().startswith("|"):
            j += 1
        lines.insert(j, row_line + "\n")
    else:
        lines.append(f"\n{section_marker}\n")
        lines.append(row_line + "\n")
    with open(path, "w") as f:
        f.writelines(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", default=os.environ.get("COORD_DIR", os.path.join(".samantha", "coord")),
                     help="coord-dir containing queue-<repo>.md / backlog-<repo>.md (default: $COORD_DIR or ./.samantha/coord)")
    ap.add_argument("--project", required=True, help="project key — matches queue-<project>.md's <project>")
    ap.add_argument("--wo", required=True)
    ap.add_argument("--priority", required=True, help="HIGH/MED/LOW or P0-P4")
    ap.add_argument("--status", required=True, choices=sorted(qs.VALID_STATUS))
    ap.add_argument("--claimed", default="—")
    ap.add_argument("--verified", default="—", help="file:line / audit ref / '—'")
    ap.add_argument("--description", required=True)
    ap.add_argument("--cap", type=int, default=DEFAULT_CAP)
    ap.add_argument("--force", action="store_true", help="skip the duplicate-id check (dangerous, rarely correct)")
    args = ap.parse_args()

    coord_dir = args.dir
    qpath = f"{coord_dir}/queue-{args.project}.md"
    bpath = f"{coord_dir}/backlog-{args.project}.md"
    if not os.path.isfile(qpath):
        print(f"ERROR: no queue file at {qpath} — check --dir/--project", file=sys.stderr)
        return 2

    fake_row = {
        "wo": args.wo, "priority": args.priority, "status": args.status,
        "claimed-by": args.claimed, "verified-against": args.verified,
        "description": args.description,
    }
    violations = qs.validate_row(fake_row)
    hard_errors = [v for v in violations if v.severity == "ERROR"
                   and "declared Status" not in v.message]  # cross-check needs real classify; skip for fresh input
    if hard_errors:
        print("REFUSED — schema violations:", file=sys.stderr)
        for v in hard_errors:
            print(f"  {v}", file=sys.stderr)
        return 1

    if not args.force:
        existing = existing_wo_ids(coord_dir, args.project)
        if args.wo in existing:
            print(f"REFUSED — {args.wo} already exists in queue-{args.project}.md or "
                  f"backlog-{args.project}.md. Use --force to override (rarely correct — "
                  f"check whether this is really a new row).", file=sys.stderr)
            return 1

    row_line = qs.format_row(args.wo, args.priority, args.status, args.claimed, args.verified, args.description)
    status_norm = qs.STATUS_ALIAS.get(args.status.strip().upper(), args.status.strip().upper())

    if status_norm == "CURRENT" or (args.claimed and args.claimed.strip() not in qs.EMPTY_CLAIMED_TOKENS):
        insert_row(qpath, row_line, "<!-- CURRENT (claimed / in-progress) -->")
        print(f"Appended to queue-{args.project}.md CURRENT section.")
        return 0

    ready_now = count_ready(qpath)
    if ready_now >= args.cap:
        if not os.path.isfile(bpath):
            print(f"ERROR: queue at cap ({ready_now}/{args.cap}) but no backlog-{args.project}.md "
                  f"exists to overflow into.", file=sys.stderr)
            return 2
        marker = f"## READY, over the {args.cap}-row queue cap"
        with open(bpath, errors="replace") as f:
            text = f.read()
        if marker not in text:
            insert_pt = text.index("## Full original content") if "## Full original content" in text else len(text)
            text = text[:insert_pt] + f"{marker}\n\n{qs.CANONICAL_HEADER}{row_line}\n\n---\n\n" + text[insert_pt:]
        else:
            lines = text.split("\n")
            idx = next(i for i, l in enumerate(lines) if marker in l)
            j = idx + 1
            while j < len(lines) and (lines[j].startswith("|") or not lines[j].strip()):
                j += 1
            insert_at = idx + 1
            for k in range(idx + 1, j):
                if lines[k].startswith("|"):
                    insert_at = k + 1
            lines.insert(insert_at, row_line)
            text = "\n".join(lines)
        with open(bpath, "w") as f:
            f.write(text)
        print(f"Queue at cap ({ready_now}/{args.cap}) — routed to backlog-{args.project}.md's "
              f"'READY, over the cap' section instead.")
        return 0

    with open(qpath, errors="replace") as f:
        qtext = f.read()
    ready_marker = next(
        (l.strip() for l in qtext.split("\n") if l.strip().startswith("<!-- READY")),
        "<!-- READY -->",
    )
    insert_row(qpath, row_line, ready_marker)
    print(f"Appended to queue-{args.project}.md READY section ({ready_now + 1}/{args.cap}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
