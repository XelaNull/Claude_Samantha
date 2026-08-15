#!/usr/bin/env python3
"""queue_schema.py — canonical schema + shared parse/validate/format logic
for .samantha/coord/queue-<repo>.md and backlog-<repo>.md files.

Single source of truth for the queue-row shape. Built 2026-08-12 as the
direct follow-up to that day's queue->backlog rebalancing cleanup, whose
root cause was that no canonical writer or schema ever existed — 7-13
incompatible ad hoc table variants had accumulated per file over weeks of
different agents hand-formatting rows. This module is imported by
queue-lint.py (read-only CI-style check) and queue-append.py (the only
sanctioned way to add a new row) so every future write goes through one
place instead of drifting again.

Marker vocabulary here also encodes two real bugs found and fixed during
the 2026-08-12 rebalance's own build-and-self-test pass, kept here as the
canonical fix so they don't reappear in some future reimplementation:
  1. A row's DONE-ness can be stated in prose ("confirmed shipped",
     "already done") without ever using a literal DONE/CLOSED/MERGED token
     in a status-like column — DONE_MARKERS_RE covers both.
  2. A row can be explicitly non-buildable ("PARKED — do not build") without
     being GATED in the RBAC/design-ruling sense — NONBUILDABLE_MARKERS_RE
     is checked independently and is deliberately broader than "gated".
"""
import re

CANONICAL_COLUMNS = ["WO", "Priority", "Status", "Claimed-by", "Verified-against", "Description"]
CANONICAL_HEADER = (
    "| WO | Priority | Status | Claimed-by | Verified-against | Description |\n"
    "|----|----------|--------|------------|-------------------|-------------|\n"
)

# Two vocabularies coexist by design: HIGH/MED/LOW (Sectorwars2102,
# tw2002-aiclient, Speak-Pony) and P0-P4 (AIBudget2026). A project using
# one consistently is fine; validate_row does not require picking one.
VALID_PRIORITY_RE = re.compile(r"^(HIGH|MED(IUM)?|LOW|P[0-4])$", re.I)

VALID_STATUS = {"CURRENT", "PENDING", "READY", "DONE", "GATED", "PARKED", "NEEDS-TRIAGE"}
# READY is accepted as an input alias for PENDING (both are used live across
# files for "open, unclaimed, buildable") and normalized to PENDING on write.
STATUS_ALIAS = {"READY": "PENDING"}

EMPTY_CLAIMED_TOKENS = {"-", "—", "none", "n/a", "unclaimed", ""}
EMPTY_CELL_TOKENS = {"-", "—", ""}

# WO-id: no whitespace, no bare markdown-breaking pipe, reasonable length.
# "(no-id)" is explicitly accepted as the documented placeholder for a row
# that genuinely has none (routes to NEEDS-TRIAGE elsewhere, not rejected
# here as malformed).
WO_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_./#\-]{1,90}$")
NO_ID_PLACEHOLDER = "(no-id)"

DONE_MARKERS_RE = re.compile(
    # The softer bare-word markers (SUPERSEDED/MERGED/CLOSED/CANCELLED/RETIRED/
    # RESOLVED) are scoped case-SENSITIVE (?-i:...) — every real status-marker
    # use of these words in this file's own DONE rows is written upper-case
    # ("PR #692 merged e8db2fdf" reads DONE only via the Status column, not
    # this regex), while ordinary lower-case prose legitimately uses these
    # words mid-sentence to describe what a WO is ABOUT, not its own status
    # (caught live 2026-08-12: WO-CLEANUP-FIND-PROFIT-CHAINS-DEAD-WRAPPER's own
    # PENDING description read "chains.find_profit_chains() is superseded by
    # find_profit_chains_with_note()" — a justification for retiring code, not
    # a claim the WO itself was done — and classify() false-positived DONE on
    # it). DONE/GHOST/WONT-BUILD/CONFIRMED SHIPPED/ALREADY */NOT CLAIMABLE stay
    # case-insensitive — no observed false-positive class for those yet.
    #
    # \bDONE\b (bare or after ALREADY) additionally excludes "DONE <WO-id>"
    # (found live 2026-08-14: WO-CLEANUP-ADMIN-COMPREHENSIVE-DUPLICATE-ROUTES-
    # RESIDUAL's own still-PENDING description read "Residual of the
    # already-DONE WO-CLEANUP-DEAD-DUPLICATE-ADMIN-ROUTES" — DONE-ness being
    # asserted of a DIFFERENT, cited WO-id, not of this row's own WO, and
    # queue-mark-done.py false-refused the row as "already DONE" on the
    # strength of it). A DONE/already-DONE immediately followed by a WO-id
    # token is describing that other WO, never this row's own status — this
    # row's own WO-id lives in the WO column, not inline in its Description.
    #
    # The bare case-sensitive words below are additionally bounded against a
    # trailing hyphen (found live 2026-08-15: WO-CANON-FIX-DEV-DRIVE-EXCEPTION-
    # DECISIONS-STALE-STATUS's own still-PENDING description opened
    # "DECISIONS.md's RESOLVED-DEV-DRIVE-EXCEPTION entry..." — a canon-anchor
    # identifier that merely CONTAINS "RESOLVED" as the first segment of a
    # longer hyphenated token, not a bare status word — and queue-mark-done.py
    # false-refused the row as "already DONE" on the strength of it, same
    # failure shape as the DONE/WO-id case above. A plain \b is NOT sufficient
    # here — a hyphen is itself a word-boundary character, so \bRESOLVED\b
    # still matches inside "RESOLVED-DEV-DRIVE-EXCEPTION"; the fix has to be a
    # negative lookahead against an immediately-following hyphen instead).
    r"\bDONE\b(?!\s+WO-)|(?-i:\bSUPERSEDED(?!-))|GHOST|(?-i:\bMERGED(?!-))|(?-i:\bCLOSED(?!-))|(?-i:\bCANCELLED(?!-))"
    r"|WONT-?BUILD|(?-i:\bRETIRED(?!-))|(?-i:\bRESOLVED(?!-))"
    r"|CONFIRMED SHIPPED|ALREADY (SHIPPED|BUILT|LIVE|MERGED)|ALREADY DONE(?!\s+WO-)|NOT CLAIMABLE",
    re.I,
)
NONBUILDABLE_MARKERS_RE = re.compile(
    r"\bPARKED\b|\bBLOCKED\b|\bDEFERRED\b|DO NOT BUILD|ON[- ]HOLD", re.I
)
# A bare \bGATED\b token was tried and dropped (2026-08-12, live-caught by
# queue-lint.py's own first run) — it false-positived on "gated: no ..."
# (a row explicitly saying it is NOT gated) and on ordinary compound words
# like "save-gated" in unrelated prose. Only an explicit "gated: yes"-shaped
# declaration counts.
GATED_DECLARED_RE = re.compile(r"gated:\s*yes\b", re.I)

_SEP_RE = re.compile(r"^:?-{2,}:?$")


def _is_sep_row(line):
    if not line.startswith("|"):
        return False
    cells = [c.strip() for c in line.strip("|").split("|")]
    return bool(cells) and all(_SEP_RE.match(c) or c == "" for c in cells)


def parse_table(path):
    """Parse every markdown table in the file at <path>. See parse_table_text
    for the actual parsing logic and return shape."""
    with open(path, errors="replace") as f:
        text = f.read()
    return parse_table_text(text)


def parse_table_text(text):
    """Parse every markdown table in <text> (already-read file content, or
    any substring of one — e.g. just a backlog file's quick-ref section
    above its verbatim historical dump). Returns a list of dicts:
    {"line": 1-indexed source line, "header": [...], "cells": [...],
     "row": {lowercased-header: cell}}. Header-detection matches
     implementer-manager.py's parse_queue(): a '|' line only starts a new
     header when the very next line is a genuine separator row; every other
     '|' line is data under whichever header is currently active (queue
     files group rows under one continuous table with blank-line/comment
     breaks, not a repeated header per group)."""
    lines = text.split("\n")
    header = None
    out = []
    i, n = 0, len(lines)
    while i < n:
        raw = lines[i]
        line = raw.strip()
        if not line.startswith("|"):
            i += 1
            continue
        if i + 1 < n and _is_sep_row(lines[i + 1].strip()):
            cells = [c.strip() for c in line.strip("|").split("|")]
            header = [c.lower() for c in cells]
            i += 2
            continue
        if _is_sep_row(line):
            i += 1
            continue
        if header is not None:
            cells = [c.strip() for c in line.strip("|").split("|")]
            row = dict(zip(header, cells))
            out.append({"line": i + 1, "header": header, "cells": cells, "row": row})
        i += 1
    return out


def row_get(row, *keys):
    for k in keys:
        v = row.get(k)
        if v:
            return v
    return ""


def wo_id(row):
    return row_get(row, "wo", "wo-n", "wo-id", "id") or NO_ID_PLACEHOLDER


_ID_KEYS = {"wo", "wo-n", "wo-id", "id"}


def classify(row):
    """DONE > GATED/PARKED (non-buildable) > CURRENT > PENDING. Scans every
    non-id cell (not just a literal 'status' column) since the description
    cell is frequently where the real DONE/PARKED marker lives — the exact
    gap that let WO-NPC-TRADER-TARIFF-WIRING sit in a live CURRENT queue
    with its own text saying 'already done', and that nearly let a PARKED
    row into CURRENT (2026-08-12 rebalance post-mortem). The WO-id cell
    itself is excluded from the scan — id names routinely embed words like
    RETIRED/CLOSED as part of the WO's own title (e.g.
    WO-CANON-DRAFT-AUTOPILOT-RETIRED-STALE-CLUSTER), which is not a status
    declaration (caught live by queue-lint.py's first real run)."""
    cells = [v for k, v in row.items() if v and k not in _ID_KEYS]
    for v in cells:
        if DONE_MARKERS_RE.search(v.strip()[:60]):
            return "DONE"
    claimed = row_get(row, "claimed by", "claimed-by", "owner").strip()
    is_claimed = claimed and claimed.lower() not in EMPTY_CLAIMED_TOKENS
    for v in cells:
        head = v.strip()[:60]
        if NONBUILDABLE_MARKERS_RE.search(head) or GATED_DECLARED_RE.search(head):
            return "PARKED" if not is_claimed else "GATED"
    if is_claimed:
        return "CURRENT"
    return "PENDING"


class Violation:
    def __init__(self, severity, message, line=None, wo=None):
        self.severity = severity  # "ERROR" | "WARN"
        self.message = message
        self.line = line
        self.wo = wo

    def __str__(self):
        loc = f"line {self.line}" if self.line else "?"
        wo = self.wo or "?"
        return f"[{self.severity}] {loc} {wo}: {self.message}"


def validate_row(row, line=None, expect_columns=None):
    """Validate one parsed row dict against the canonical schema. Returns a
    list of Violation. Does not require the row's raw header to literally
    be CANONICAL_COLUMNS (legacy backlog quick-ref tables reuse this on
    already-migrated rows) but flags it as an ERROR when expect_columns is
    passed and the row's own header list doesn't match it column-for-column
    — that's the actual drift this tool exists to catch."""
    violations = []
    wid = wo_id(row)

    if expect_columns is not None:
        header = row.get("__header__")  # optional, set by caller if available

    rid = row_get(row, "wo", "wo-n", "wo-id", "id")
    if not rid:
        violations.append(Violation("ERROR", "missing WO-id column/value", line, wid))
    elif rid != NO_ID_PLACEHOLDER and not WO_ID_RE.match(rid):
        violations.append(Violation("ERROR", f"malformed WO-id {rid!r} (whitespace or bad chars)", line, wid))

    priority = row_get(row, "priority", "pri", "severity").strip()
    if not priority:
        violations.append(Violation("WARN", "missing Priority", line, wid))
    elif not VALID_PRIORITY_RE.match(priority):
        violations.append(Violation("ERROR", f"invalid Priority {priority!r} (want HIGH/MED/LOW or P0-P4)", line, wid))

    status = row_get(row, "status").strip().upper()
    status = STATUS_ALIAS.get(status, status)
    if not status:
        violations.append(Violation("WARN", "missing Status (falls back to inferred classification)", line, wid))
    elif status not in VALID_STATUS:
        violations.append(Violation("ERROR", f"invalid Status {status!r} (want one of {sorted(VALID_STATUS)})", line, wid))

    desc = row_get(row, "description", "title", "finding", "detail", "notes")
    if not desc:
        violations.append(Violation("WARN", "empty Description", line, wid))

    # Cross-check: does the row's own inferred classification agree with its
    # declared Status? Disagreement is exactly the class of bug this schema
    # exists to catch (a DONE row sitting under a CURRENT/PENDING label).
    inferred = classify(row)
    if status and status in VALID_STATUS:
        agree = (
            status == inferred
            or (status == "PENDING" and inferred in ("PENDING", "CURRENT"))
            or (status in ("GATED", "PARKED") and inferred in ("GATED", "PARKED"))
        )
        if not agree:
            violations.append(Violation(
                "ERROR",
                f"declared Status={status} but row content reads as {inferred} "
                f"(marker found in a cell) — likely stale/misfiled",
                line, wid,
            ))

    return violations


def format_row(wo, priority, status, claimed, verified, description):
    def cell(v):
        v = (v or "").strip().replace("|", "❘")
        return v if v else "—"

    status = STATUS_ALIAS.get(status.strip().upper(), status.strip().upper())
    return f"| {cell(wo)} | {cell(priority)} | {cell(status)} | {cell(claimed)} | {cell(verified)} | {cell(description)} |"
