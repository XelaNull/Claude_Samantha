#!/usr/bin/env python3
"""implementer-manager.py — standalone TUI to start/stop Samantha-framework implementer seats.

Arrow-key project picker -> per-project seat list.

Home screen (project picker):
  ↑/↓   move
  Enter  manage the selected project's seats
  a      add a new project to the managed list (see "Adding a project" below)
  x      remove the selected project from the managed list (does NOT touch the
         directory or any seats already running there — just stops tracking it
         here; re-add it any time with 'a')
  i      install/fix the coordination protocol for the selected project (see
         "Coordination-protocol check" below) — same action 'a' runs
         automatically for a brand-new project
  q      quit

Each row shows a status glyph for whether that project's coordination
protocol looks correctly wired: [✓] OK, [⚠] partial, [✗] missing, [?] the
directory itself is gone. The zone path is shown on its own line under each
project.

Per-project seat screen:
  ↑/↓   move
  n      start N new headless Cursor-CLI seat(s) in this project's zone
  s      stop the selected seat (kill heartbeat + monitor by recorded PID,
         never pkill -f) — leaves its presence file in place, marked
         Spun-down, so it still shows in the list (see 'd' below)
  u      restart a DEAD seat — relaunches cursor-headless-seat.sh for its
         EXISTING identity (skips provision/ASSIGN-IDENTITY/adopt entirely,
         since the identity + its enrolled signing key already exist). Use
         this to bring a stopped/crashed seat back; 'n' is for a brand-new
         identity instead. Refuses if the seat still looks ALIVE or is
         already STARTING.
  d      delete a DEAD seat's entry from the list — archives its presence
         file to coord/archive/ and clears its .watch-state/ dir. Refuses if
         the seat still looks ALIVE (stop it first with 's'). This is
         deliberately a separate action from 's': stopping and deleting have
         different blast radii, and Max caught 'stop leaves a dead entry
         sitting there with no way to clear it' as a real gap (2026-08-11) —
         conflating the two would risk archiving a presence file a process
         is still writing to.
  w      work-order stream — see "Work-order stream view" below
  i      install/fix the coordination protocol for this project
  r      refresh
  b/ESC  back to project list
  q      quit

──────────────────────── Work-order stream view ('w') ────────────────────────
Reads coord/queue-<key>.md (Orchestrator/CLAUDE.md territory — this tool only
ever reads it, never writes it) and renders every row from every markdown
table in the file as one scrollable list, ordered DONE-ish rows first, then
CURRENT (claimed, not yet done), then PENDING (READY/gated/blocked/
unclaimed) — so completed history sits above, open future sits below, and
the view opens with the viewport centered on the first CURRENT row (or the
overall middle if nothing's currently claimed), landing you on "where things
are" without having to scroll to find it. ↑/↓ move one row, PgUp/PgDn move a
page, Home/End jump to the ends. Re-parses only when the queue file's mtime
changes (cheap check every refresh tick; a full reparse only on an actual
change — some of these files run 200+ rows). A project with no
queue-<key>.md yet (e.g. a just-added project) shows an empty-state message,
not an error.

────────────────────── Coordination-protocol check ───────────────────────────
Every project row is checked for two install markers, deterministically (no
LLM call — Max's explicit choice, 2026-08-11, over "spin up a Cursor agent to
install it": faster, free, and reviewable):
  1. `.claude/settings.json` has a PreToolUse Bash hook pointed at this
     your orchestrator workspace's `coordination-precommit-hook.sh`.
  2. `.gitignore` excludes `.samantha/coord/` (skipped — counts as satisfied —
     for a directory that isn't a git repo at all).
[✓] both present, [⚠] one present, [✗] neither, [?] directory missing.
Adding a project ('a') runs this check immediately and auto-installs
anything missing UNLESS settings.json already has an unrelated PreToolUse
Bash hook (won't silently overwrite someone else's hook — flags it instead
for a manual 'i' review). Existing/pre-existing tracked projects are never
auto-installed into on this check alone — press 'i' to fix one by hand.

────────────────────────────── Adding a project ─────────────────────────────
Press 'a' on the home screen. You'll be asked for:
  - a display name (anything, e.g. "MyNewIdea")
  - a directory (absolute path or ~-relative; does NOT need to be a git repo —
    any directory works, it's just where a seat's `cwd` will be and what its
    presence `zone:` field will point at)
The project key used for auto-generated seat identities (impl-<key>-h<N>) is
derived from the name automatically (lowercased, non-alnum stripped) — you'll
see it echoed before it's saved, no separate prompt.

Projects you add here are saved to implementer-manager-projects.json (same
directory as this script) and persist across runs — this is the SSOT for
"what does the TUI know about," separate from (and additive to)
.samantha/coord/PROJECTS.md, which is the orchestrator's own prose coordination board
and is not machine-parsed by this tool. Removing a project from the TUI list
('x') does not touch PROJECTS.md, the directory, or any seat's coord file.

If you forget any of this later: ask Samantha (or re-read this docstring —
`python3 implementer-manager.py --help` prints it without launching the UI).

A freshly-launched seat (via 'n' or 'u') shows STARTING rather than DEAD for
up to STARTING_GRACE_SECONDS (240s) — provision/ASSIGN-IDENTITY/adopt/enroll
plus a cold cursor-agent session prime genuinely takes ~2 minutes before
heartbeat.sh writes its first pidfile; showing DEAD during that window reads
as a failure when it's actually still booting. Past the grace window with
still no pidfile, it reads DEAD like any other stopped/failed seat.

This tool does NOT reimplement coordination protocol logic — it shells out to
the existing scripts (bootstrap-identity.sh, coord-send.sh,
cursor-headless-seat.sh) for every protocol-meaningful action, and reads
.watch-state/<id>/{heartbeat,watcher}.pid (the same files coord-status.sh
reads) to determine liveness and to stop a seat.

Only headless Cursor-CLI seats (via cursor-headless-seat.sh) can actually be
STARTED by this tool — a Cursor-IDE or Claude-Code seat is a human opening an
app, this script can't do that part. Any known seat, of any harness, can be
STOPPED from here (kill by recorded PID is harness-agnostic).

Run: python3 .claude/implementer-manager.py
"""
import curses
import datetime
import glob
import json
import os
import re
import subprocess
import sys
import textwrap
import time

# ORCHESTRATOR_ROOT: the hub workspace root — where .claude/ and
# .samantha/coord/ live for this deployment. Framework copy: no hardcoded
# per-install path — set SAMANTHA_ORCHESTRATOR_ROOT in your environment, or
# this falls back to the current working directory (run the tool from your
# orchestrator workspace root, same convention as the other Required-tier
# scripts in this pack — see README.md § Script tiers).
ORCHESTRATOR_ROOT = os.environ.get("SAMANTHA_ORCHESTRATOR_ROOT") or os.getcwd()
CLAUDE_DIR = f"{ORCHESTRATOR_ROOT}/.claude"
COORD_DIR = f"{ORCHESTRATOR_ROOT}/.samantha/coord"
CURSOR_SEAT_SH = f"{CLAUDE_DIR}/cursor-headless-seat.sh"
BOOTSTRAP_SH = f"{CLAUDE_DIR}/bootstrap-identity.sh"
COORD_SEND_SH = f"{CLAUDE_DIR}/coord-send.sh"
STATE_DIR = f"{CLAUDE_DIR}/.implementer-manager-state"
PROJECTS_JSON = f"{CLAUDE_DIR}/implementer-manager-projects.json"

# Seeded into PROJECTS_JSON on first run only — after that, PROJECTS_JSON is
# the sole source of truth and this constant is never consulted again. Not a
# fallback-on-every-launch default; edits made in-app (or by hand-editing the
# JSON) are never overwritten by this list. Framework copy ships with one
# illustrative placeholder — add your own deployment's real projects via the
# in-app 'a' (add project) action, or hand-edit PROJECTS_JSON directly.
SEED_PROJECTS = [
    {"name": "example-project", "key": "example", "zone": f"{ORCHESTRATOR_ROOT}/example-project"},
]

NON_SEAT_BASENAMES = re.compile(
    r"^(orchestrator|PROJECTS|QUEUE|queue-.*|components-.*|RATIFIED-.*|.*\.archive|orchestrator-session-handover)$"
)

COORD_HOOK_SH = f"{CLAUDE_DIR}/coordination-precommit-hook.sh"
GITIGNORE_BLOCK = (
    "\n# Inter-instance coordination mailbox — local-only, never committed\n"
    "# (see your orchestrator workspace's CLAUDE.md)\n"
    ".samantha/coord/\n"
    ".samantha-identity\n"
)


# ───────────────────── coordination-protocol install check ──────────────────
# Deterministic, no LLM involved (Max's explicit call, 2026-08-11): every check
# here is "does this specific file contain this specific marker," same shape
# as by-hand fixes previously applied to a seat's .claude/settings.json and
# .gitignore in this framework's own dogfooding (wrong-repo hook pointer, missing
# mailbox gitignore entry) — those were real, found-live bugs, not
# hypotheticals, which is why this check exists at all.

def check_protocol(zone):
    """Inspect <zone> for the coordination-protocol install markers this tool
    knows how to create. Returns a dict with an overall `status` in
    {"NO_DIR", "MISSING", "PARTIAL", "OK"} plus per-marker detail."""
    result = {
        "status": "NO_DIR",
        "settings_path": f"{zone}/.claude/settings.json",
        "hook_wired": False,
        "hook_wrong": False,
        "hook_identity": None,
        "gitignore_path": f"{zone}/.gitignore",
        "gitignore_ok": False,
        "gitignore_applicable": False,
        "detail": [],
    }
    if not os.path.isdir(zone):
        result["detail"].append(f"{zone} does not exist")
        return result

    settings_path = result["settings_path"]
    if os.path.isfile(settings_path):
        try:
            with open(settings_path) as f:
                data = json.load(f)
            cmds = []
            for entry in data.get("hooks", {}).get("PreToolUse", []):
                for h in entry.get("hooks", []):
                    c = h.get("command", "")
                    if c:
                        cmds.append(c)
            for c in cmds:
                if COORD_HOOK_SH in c:
                    result["hook_wired"] = True
                    m = re.search(r"coordination-precommit-hook\.sh[^'\"]*?(\S+)\s*['\"]?$", c)
                    idm = re.search(r"SAMANTHA_IDENTITY:-([A-Za-z0-9._-]+)|coord\s+([A-Za-z0-9._-]+)['\"]?\s*$", c)
                    if idm:
                        result["hook_identity"] = idm.group(1) or idm.group(2)
                    break
            if not result["hook_wired"] and cmds:
                # A PreToolUse Bash hook exists but none of its commands point at
                # OUR coordination-precommit-hook.sh — could be the exact
                # wrong-repo-pointer bug found in a real deployment (some other
                # project's absolute path), or a project-specific hook that has
                # nothing to do with coordination. Flag as wrong, not missing —
                # a human should look, not silently overwrite.
                result["hook_wrong"] = True
                result["detail"].append("settings.json has a PreToolUse Bash hook, but not pointed at this orchestrator install")
        except (OSError, json.JSONDecodeError) as e:
            result["detail"].append(f"settings.json unreadable: {e}")
    else:
        result["detail"].append("no .claude/settings.json")

    if os.path.isdir(f"{zone}/.git"):
        result["gitignore_applicable"] = True
        gi = result["gitignore_path"]
        if os.path.isfile(gi):
            try:
                with open(gi, errors="replace") as f:
                    content = f.read()
                result["gitignore_ok"] = ".samantha/coord" in content
            except OSError:
                pass
        if not result["gitignore_ok"]:
            result["detail"].append("no coordination mailbox exclusion in .gitignore")
    else:
        result["gitignore_ok"] = True  # not a git repo — nothing to exclude from committing

    if result["hook_wired"] and result["gitignore_ok"]:
        result["status"] = "OK"
    elif result["hook_wired"] or result["gitignore_ok"] and not result["hook_wrong"]:
        result["status"] = "PARTIAL" if not (result["hook_wired"] and result["gitignore_ok"]) else "OK"
    else:
        result["status"] = "MISSING"
    return result


def install_protocol(zone, identity_hint):
    """Deterministically write/patch the two install markers check_protocol()
    looks for. Never touches anything else in settings.json or .gitignore —
    merges alongside existing content. Returns a list of action strings."""
    actions = []
    claude_dir = f"{zone}/.claude"
    os.makedirs(claude_dir, exist_ok=True)
    settings_path = f"{claude_dir}/settings.json"

    data = {}
    if os.path.isfile(settings_path):
        try:
            with open(settings_path) as f:
                data = json.load(f)
        except (OSError, json.JSONDecodeError) as e:
            return [f"ABORTED — existing settings.json is not valid JSON, not touching it: {e}"]

    data.setdefault("outputStyle", "Samantha")
    hooks = data.setdefault("hooks", {})
    pretool = hooks.setdefault("PreToolUse", [])
    bash_entry = None
    for entry in pretool:
        if entry.get("matcher") == "Bash":
            bash_entry = entry
            break
    if bash_entry is None:
        bash_entry = {"matcher": "Bash", "hooks": []}
        pretool.append(bash_entry)

    already = any(COORD_HOOK_SH in h.get("command", "") for h in bash_entry["hooks"])
    if already:
        actions.append("settings.json: hook already wired, left as-is")
    else:
        cmd = (f"bash -lc 'ID=\"${{SAMANTHA_IDENTITY:-{identity_hint}}}\"; "
               f"exec {COORD_HOOK_SH} {COORD_DIR} \"$ID\"'")
        bash_entry["hooks"].append({"type": "command", "command": cmd})
        tmp = settings_path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.replace(tmp, settings_path)
        actions.append(f"settings.json: wired PreToolUse hook (default identity {identity_hint}, override via SAMANTHA_IDENTITY)")

    if os.path.isdir(f"{zone}/.git"):
        gi = f"{zone}/.gitignore"
        content = ""
        if os.path.isfile(gi):
            try:
                with open(gi, errors="replace") as f:
                    content = f.read()
            except OSError:
                pass
        if ".samantha/coord" in content:
            actions.append(".gitignore: mailbox exclusion already present, left as-is")
        else:
            with open(gi, "a") as f:
                if content and not content.endswith("\n"):
                    f.write("\n")
                f.write(GITIGNORE_BLOCK)
            actions.append(".gitignore: added mailbox exclusion")
    else:
        actions.append(".gitignore: skipped (not a git repo)")

    return actions


def load_projects():
    if not os.path.isfile(PROJECTS_JSON):
        save_projects(SEED_PROJECTS)
        return list(SEED_PROJECTS)
    try:
        with open(PROJECTS_JSON) as f:
            data = json.load(f)
        projects = data.get("projects", [])
        if projects:
            return projects
    except (OSError, json.JSONDecodeError):
        pass
    return list(SEED_PROJECTS)


def save_projects(projects):
    os.makedirs(os.path.dirname(PROJECTS_JSON), exist_ok=True)
    tmp = PROJECTS_JSON + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"projects": projects}, f, indent=2)
        f.write("\n")
    os.replace(tmp, PROJECTS_JSON)


def slugify(name):
    s = re.sub(r"[^a-z0-9]+", "", name.lower())
    return s or "project"


def unique_key(base_key, projects):
    existing = {p["key"] for p in projects}
    if base_key not in existing:
        return base_key
    n = 2
    while f"{base_key}{n}" in existing:
        n += 1
    return f"{base_key}{n}"


def sh(cmd, **kw):
    """Run a command, return (rc, stdout+stderr combined)."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=kw.pop("timeout", 30), **kw)
        return r.returncode, (r.stdout or "") + (r.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, "(timed out)"


def pid_alive(pid):
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    try:
        os.kill(pid, 0)
    except (ProcessLookupError, PermissionError):
        return False
    except OSError:
        return False
    return True


def read_pidfile(identity, name):
    p = f"{COORD_DIR}/.watch-state/{identity}/{name}"
    if not os.path.isfile(p):
        return None
    try:
        with open(p) as f:
            return f.read().strip()
    except OSError:
        return None


def parse_presence(path):
    """Best-effort parse of a coord/<id>.md presence header (key: value lines
    up to the first '---')."""
    d = {}
    try:
        with open(path, errors="replace") as f:
            for line in f:
                line = line.rstrip("\n")
                if line.strip() == "---":
                    break
                m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", line)
                if m:
                    d[m.group(1)] = m.group(2)
    except OSError:
        pass
    return d


MSG_HEADER_RE = re.compile(r"^### (\S+) — .*$")


def last_activity(path):
    """Scan a coord/<identity>.md file for its LAST '### <ts> — ...' message
    header and return (timestamp_str, seconds_ago, subject). Cheap enough to
    run every refresh tick — these files are a few KB, not the multi-MB
    archives — but reads only the last ~64KB to stay cheap even on an
    outbox that's grown past its hygiene trip point before the cron catches
    it. seconds_ago is None if no header or the timestamp doesn't parse
    (never crashes the UI over a malformed/legacy line)."""
    if not os.path.isfile(path):
        return None, None, None
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            if size > 65536:
                f.seek(-65536, os.SEEK_END)
            tail = f.read().decode("utf-8", errors="replace")
    except OSError:
        return None, None, None

    last_ts, last_line = None, None
    for line in tail.splitlines():
        m = MSG_HEADER_RE.match(line)
        if m:
            last_ts, last_line = m.group(1), line
    if not last_ts:
        return None, None, None

    seconds_ago = None
    try:
        ts = datetime.datetime.strptime(last_ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
        seconds_ago = (datetime.datetime.now(datetime.timezone.utc) - ts).total_seconds()
    except ValueError:
        pass

    subject = None
    if last_line:
        brackets = re.findall(r"\[([^\]]*)\]", last_line)
        if brackets:
            subject = brackets[-1]
        else:
            tagm = re.search(r"— ([^\s].*?)$", last_line)
            if tagm:
                subject = tagm.group(1)
    return last_ts, seconds_ago, subject


def format_ago(seconds):
    if seconds is None:
        return "?"
    seconds = max(0, int(seconds))
    if seconds < 60:
        return f"{seconds}s ago"
    if seconds < 3600:
        return f"{seconds // 60}m ago"
    if seconds < 86400:
        return f"{seconds // 3600}h ago"
    return f"{seconds // 86400}d ago"


def discover_seats(zone):
    """Return seats whose presence `zone:` field matches (or is nested under)
    the given project zone, excluding orchestrator/board/queue files."""
    seats = []
    for path in sorted(glob.glob(f"{COORD_DIR}/*.md")):
        base = os.path.basename(path)[:-3]
        if NON_SEAT_BASENAMES.match(base):
            continue
        info = parse_presence(path)
        z = info.get("zone", "")
        # Presence `zone:` often carries trailing prose ("· branch `x` · lane: ...")
        # or points at a dedicated git worktree sibling (e.g. Sectorwars2102-cursor-lane)
        # rather than the bare repo path — a prefix match groups both correctly
        # under the owning project without requiring exact equality.
        if not z or not z.startswith(zone):
            continue
        hb = read_pidfile(base, "heartbeat.pid")
        wp = read_pidfile(base, "watcher.pid")
        last_ts, seconds_ago, subject = last_activity(path)
        seats.append({
            "identity": base,
            "state": info.get("state", "unknown"),
            "harness": info.get("harness", "?"),
            "component": info.get("component", ""),
            "current_wos": info.get("current_wos", ""),
            "heartbeat_pid": hb,
            "watcher_pid": wp,
            "heartbeat_alive": pid_alive(hb),
            "watcher_alive": pid_alive(wp),
            "starting": seat_is_starting(base, hb),
            "last_ts": last_ts,
            "seconds_ago": seconds_ago,
            "last_subject": subject,
        })
    # Active seats (heartbeat or watcher alive) first, then newest-activity
    # first within each group — a dead seat with no last_ts sorts to the
    # very bottom of the dead group rather than crashing the comparison.
    seats.sort(key=lambda s: (
        0 if (s["heartbeat_alive"] or s["watcher_alive"]) else 1,
        s["seconds_ago"] if s["seconds_ago"] is not None else float("inf"),
    ))
    return seats


def next_headless_identity(key):
    existing = {os.path.basename(p)[:-3] for p in glob.glob(f"{COORD_DIR}/impl-{key}-h*.md")}
    n = 1
    while f"impl-{key}-h{n}" in existing:
        n += 1
    return f"impl-{key}-h{n}"


def start_headless_seat(identity, zone, log):
    """Provision + self-ASSIGN + adopt + launch one headless Cursor-CLI seat.
    Returns (ok, message)."""
    os.makedirs(STATE_DIR, exist_ok=True)
    logf = f"{STATE_DIR}/{identity}.log"

    rc, out = sh([BOOTSTRAP_SH, "--provision", "--dir", COORD_DIR, "--zone", zone])
    if rc != 0:
        return False, f"provision failed: {out.strip()[-400:]}"
    # --provision prints the pending-<uuid> id on its OWN first non-blank line,
    # followed by multi-line human-facing "[bootstrap] ..." arm/adopt guidance —
    # NOT on the last line (a prior version of this parser wrongly assumed
    # last-line and grabbed a guidance fragment instead, discovered live
    # 2026-08-11 when a real add-project attempt failed with "unexpected
    # provision output"). Scan every line for the exact pending-<hex> shape.
    prov_id = None
    for line in out.splitlines():
        line = line.strip()
        if re.fullmatch(r"pending-[0-9a-f]+", line):
            prov_id = line
            break
    if not prov_id:
        return False, f"unexpected provision output: {out.strip()[-400:]}"
    log(f"  provisioned {prov_id}")

    rc, out = sh([COORD_SEND_SH, "--identity", "orchestrator", "--dir", COORD_DIR,
                  "--to", prov_id, "--tag", "🤝 ASSIGN-IDENTITY",
                  "--body", f"{prov_id} -> {identity}"])
    if rc != 0:
        return False, f"ASSIGN-IDENTITY failed: {out.strip()[-400:]}"
    log(f"  assigned {prov_id} -> {identity}")

    rc, out = sh([BOOTSTRAP_SH, "--adopt", "--provisional", prov_id,
                  "--assigned", identity, "--dir", COORD_DIR])
    if rc != 0:
        return False, f"adopt failed: {out.strip()[-400:]}"
    log(f"  adopted as {identity}")

    # Enroll the seat's own pubkey under its assigned identity (PROTOCOL
    # 1.4.0) — without this every message it later signs comes back
    # UNVERIFIED to every peer checking allowed_signers. bootstrap-identity.sh's
    # own printed guidance says the Orchestrator runs coord-keygen.sh --enroll
    # as a second step after ASSIGN-IDENTITY; this tool acts as the
    # Orchestrator's hand here, so it must do that step too — a real gap
    # found live 2026-08-11 (impl-aiclient-h1 ran fully armed, unenrolled,
    # for ~90 minutes; caught only when Max asked why a command had to be
    # run by hand at all). The pubkey line is only ever written into the
    # presence file body (never echoed to --provision's own stdout), so
    # recover it from there rather than re-deriving/regenerating it.
    final_path = f"{COORD_DIR}/{identity}.md"
    pub_line = None
    try:
        with open(final_path, errors="replace") as f:
            for line in f:
                m = re.match(r"^pubkey:\s*(.+)$", line.strip())
                if m:
                    pub_line = m.group(1).strip()
                    break
    except OSError:
        pass
    if not pub_line:
        return False, (f"adopted as {identity} but could not recover its pubkey line from "
                        f"{final_path} — enroll manually: coord-keygen.sh --enroll --identity "
                        f"{identity} --pubkey-line <line-from-file> --dir {COORD_DIR}")
    rc, out = sh(["bash", f"{CLAUDE_DIR}/coord-keygen.sh", "--enroll",
                  "--identity", identity, "--pubkey-line", pub_line, "--dir", COORD_DIR])
    if rc != 0:
        return False, f"adopted as {identity} but enroll failed: {out.strip()[-400:]}"
    log(f"  enrolled {identity} in allowed_signers")

    if not os.path.isfile(CURSOR_SEAT_SH):
        return False, f"{CURSOR_SEAT_SH} not found"
    try:
        with open(logf, "ab") as lf:
            subprocess.Popen(
                ["bash", CURSOR_SEAT_SH, "--identity", identity, "--dir", COORD_DIR],
                cwd=zone, stdout=lf, stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL, start_new_session=True,
            )
    except OSError as e:
        return False, f"launch failed: {e}"
    _write_started_marker(identity)
    return True, f"launched — log at {logf}"


STARTING_GRACE_SECONDS = 240  # provision+ASSIGN+adopt+enroll+cursor-agent cold
                               # priming observed live 2026-08-11 taking ~130s
                               # end-to-end before heartbeat.sh's first pidfile
                               # write — 240s gives headroom without letting a
                               # genuinely-dead seat hide as "STARTING" forever.


def _write_started_marker(identity):
    """Record when this tool launched <identity>, so a seat with no pidfile
    YET can be shown as STARTING (mid-bootstrap) rather than DEAD (actually
    failed/killed) for a grace window — see STARTING_GRACE_SECONDS."""
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(f"{STATE_DIR}/{identity}.started_by", "w") as f:
        f.write(f"implementer-manager.py\n{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}\n")


def seat_is_starting(identity, heartbeat_pid):
    """True iff this tool launched <identity> recently and its heartbeat
    pidfile hasn't appeared yet — i.e. genuinely mid-bootstrap, not dead.
    Once a heartbeat pidfile exists at all (even for a since-dead process)
    this returns False — the grace window covers only the gap before
    heartbeat.sh's first write, never a later crash."""
    if heartbeat_pid:
        return False
    marker = f"{STATE_DIR}/{identity}.started_by"
    if not os.path.isfile(marker):
        return False
    try:
        with open(marker) as f:
            lines = f.read().splitlines()
        started = datetime.datetime.strptime(lines[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    except (OSError, ValueError, IndexError):
        return False
    age = (datetime.datetime.now(datetime.timezone.utc) - started).total_seconds()
    return age < STARTING_GRACE_SECONDS


def restart_seat(identity, zone):
    """Relaunch a headless Cursor-CLI seat for an EXISTING (already-adopted)
    identity — skips provision/ASSIGN-IDENTITY/adopt/enroll entirely, since
    the identity + its enrolled signing key already exist on disk.
    cursor-headless-seat.sh itself supports being pointed at a pre-adopted
    identity (its own startup log says as much: "Using given identity ...
    must already be adopted"). This is the resume path for a seat that shows
    DEAD (its processes died or were stopped) but whose presence file + key
    are still good; 'n' start-new is for a brand-new identity instead."""
    os.makedirs(STATE_DIR, exist_ok=True)
    logf = f"{STATE_DIR}/{identity}.log"
    if not os.path.isfile(CURSOR_SEAT_SH):
        return False, f"{CURSOR_SEAT_SH} not found"
    path = f"{COORD_DIR}/{identity}.md"
    if not os.path.isfile(path):
        return False, f"no presence file for {identity} — use 'n' to start a brand-new seat instead"
    try:
        with open(logf, "ab") as lf:
            subprocess.Popen(
                ["bash", CURSOR_SEAT_SH, "--identity", identity, "--dir", COORD_DIR],
                cwd=zone, stdout=lf, stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL, start_new_session=True,
            )
    except OSError as e:
        return False, f"launch failed: {e}"
    _write_started_marker(identity)
    return True, f"restarted — log at {logf}"


def stop_seat(identity):
    """Kill heartbeat + monitor by recorded PID (never pkill -f) and mark the
    seat's own presence state=Spun-down."""
    lines = []
    for name in ("heartbeat.pid", "watcher.pid"):
        pid = read_pidfile(identity, name)
        if pid and pid_alive(pid):
            try:
                os.kill(int(pid), 15)  # SIGTERM
                lines.append(f"{name}={pid}: sent SIGTERM")
            except OSError as e:
                lines.append(f"{name}={pid}: kill failed ({e})")
        else:
            lines.append(f"{name}: not alive / no pidfile")

    path = f"{COORD_DIR}/{identity}.md"
    if os.path.isfile(path):
        try:
            with open(path, errors="replace") as f:
                content = f.read()
            ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            if re.search(r"^state:\s*.*$", content, re.M):
                content = re.sub(r"^state:\s*.*$",
                                  "state: Spun-down",
                                  content, count=1, flags=re.M)
            if re.search(r"^state_updated:\s*.*$", content, re.M):
                content = re.sub(r"^state_updated:\s*.*$",
                                  f"state_updated: {ts}",
                                  content, count=1, flags=re.M)
            else:
                content = content.replace("state: Spun-down",
                                           f"state: Spun-down\nstate_updated: {ts}", 1)
            note = f"notes: SPUN-DOWN via implementer-manager.py {ts}"
            if re.search(r"^notes:\s*.*$", content, re.M):
                content = re.sub(r"^notes:\s*.*$", note, content, count=1, flags=re.M)
            else:
                content = content.replace(f"state_updated: {ts}",
                                           f"state_updated: {ts}\n{note}", 1)
            tmp = path + ".tmp"
            with open(tmp, "w") as f:
                f.write(content)
            os.replace(tmp, path)
            lines.append("presence: state=Spun-down")
        except OSError as e:
            lines.append(f"presence update failed: {e}")
    return lines


def delete_seat(identity):
    """Remove a DEAD seat from the visible list. Archives (never hard-deletes)
    coord/<identity>.md to coord/archive/, and clears its .watch-state/ dir
    (pidfiles/receipts — no longer meaningful once the seat is gone). Does
    NOT touch allowed_signers: past messages signed by this identity (still
    readable in orchestrator.md / archives / peer files) must stay verifiable,
    so its enrolled pubkey is left in place — deregistering keys is a
    separate, not-yet-built concern, not this button's job.

    Refuses (returns an error line, does nothing) if the seat still looks
    ALIVE — stop_seat() first. This mirrors Max's own observation: stop and
    delete are two different actions with two different blast radii, and
    conflating them risks deleting a presence file out from under a process
    that's still writing to it.
    """
    hb = read_pidfile(identity, "heartbeat.pid")
    wp = read_pidfile(identity, "watcher.pid")
    if pid_alive(hb) or pid_alive(wp):
        return [f"REFUSED — {identity} still has a live process (heartbeat={hb} watcher={wp}); stop it first"]

    lines = []
    path = f"{COORD_DIR}/{identity}.md"
    if os.path.isfile(path):
        archive_dir = f"{COORD_DIR}/archive"
        os.makedirs(archive_dir, exist_ok=True)
        ts = time.strftime("%Y%m%d%H%M%S", time.gmtime())
        dest = f"{archive_dir}/{identity}-deleted-{ts}.md"
        try:
            os.replace(path, dest)
            lines.append(f"presence archived -> {dest}")
        except OSError as e:
            return [f"could not archive presence file: {e}"]
    else:
        lines.append("no presence file (already gone)")

    ws_dir = f"{COORD_DIR}/.watch-state/{identity}"
    if os.path.isdir(ws_dir):
        import shutil
        try:
            shutil.rmtree(ws_dir)
            lines.append("watch-state cleared")
        except OSError as e:
            lines.append(f"watch-state clear failed: {e}")

    started_marker = f"{STATE_DIR}/{identity}.started_by"
    if os.path.isfile(started_marker):
        try:
            os.remove(started_marker)
        except OSError:
            pass

    return lines


# ─────────────────────────── curses UI ──────────────────────────────────────

def prompt_line(stdscr, y, x, prompt, default=""):
    # Auto-refresh (REFRESH_MS getch timeout, see below) must not apply while
    # waiting on typed text — getstr() drives the same underlying getch() the
    # timeout governs, so a still-typing user would see their keystrokes
    # silently truncated every 2s. Block properly for the duration, restore
    # the refresh cadence on the way out (including on the exception path).
    h, w = stdscr.getmaxyx()
    stdscr.move(y, 0)
    stdscr.clrtoeol()
    stdscr.timeout(-1)
    curses.echo()
    curses.curs_set(1)
    stdscr.addstr(y, x, prompt + " ")
    stdscr.refresh()
    try:
        s = stdscr.getstr(y, min(x + len(prompt) + 1, w - 1), 80).decode("utf-8").strip()
    except Exception:
        s = ""
    finally:
        curses.noecho()
        curses.curs_set(0)
        stdscr.timeout(REFRESH_MS)
    return s or default


def confirm(stdscr, y, prompt):
    """Single y/N keypress, blocking (see prompt_line's timeout note — same
    reasoning: a 2s auto-refresh tick must never eat a pending confirmation)."""
    h, w = stdscr.getmaxyx()
    stdscr.addstr(y, 0, prompt[: w - 1].ljust(w - 1))
    stdscr.refresh()
    stdscr.timeout(-1)
    try:
        ans = stdscr.getch()
    finally:
        stdscr.timeout(REFRESH_MS)
    return ans in (ord('y'), ord('Y'))


# ───────────────────────────── color scheme ──────────────────────────────
# One accent hue per meaning, used consistently across both screens rather
# than per-line ad hoc: green=healthy/alive/OK, yellow=in-between/starting/
# partial, red=dead/missing/failed, cyan=titles+identities, magenta=activity
# labels, dim white=secondary/path/timestamp text. Falls back to plain
# black-and-white (HAS_COLOR False) on a terminal with no color support —
# every call site goes through cp(), never curses.color_pair() directly, so
# there's exactly one place that needs to know whether color is available.
COLOR_TITLE = 1
COLOR_GOOD = 2
COLOR_WARN = 3
COLOR_BAD = 4
COLOR_DIM = 5
COLOR_ACCENT = 6
COLOR_SELECTED = 7
COLOR_FOOTER = 8
# COLOR_FADED: a solid dark-grey BACKGROUND box (not just dimmed foreground
# text) for the zero-alive project rows in home_screen() — foreground-only
# dimming (COLOR_DIM/white, or black-on-default) reads as plain/no-color on
# most terminal palettes. A filled background box is unambiguous regardless
# of the terminal's default colors.
COLOR_FADED = 9

HAS_COLOR = False


def init_colors():
    global HAS_COLOR
    try:
        curses.start_color()
        curses.use_default_colors()
    except curses.error:
        return
    HAS_COLOR = curses.has_colors()
    if not HAS_COLOR:
        return
    curses.init_pair(COLOR_TITLE, curses.COLOR_CYAN, -1)
    curses.init_pair(COLOR_GOOD, curses.COLOR_GREEN, -1)
    curses.init_pair(COLOR_WARN, curses.COLOR_YELLOW, -1)
    curses.init_pair(COLOR_BAD, curses.COLOR_RED, -1)
    curses.init_pair(COLOR_DIM, curses.COLOR_WHITE, -1)
    curses.init_pair(COLOR_ACCENT, curses.COLOR_MAGENTA, -1)
    curses.init_pair(COLOR_SELECTED, curses.COLOR_BLACK, curses.COLOR_CYAN)
    curses.init_pair(COLOR_FOOTER, curses.COLOR_WHITE, curses.COLOR_BLUE)
    # Real dark grey (256-color palette index 238) when the terminal supports
    # it; COLOR_BLACK is the best available fallback in 8/16-color terminals.
    grey_bg = 238 if curses.COLORS >= 256 else curses.COLOR_BLACK
    curses.init_pair(COLOR_FADED, curses.COLOR_WHITE, grey_bg)


def cp(n):
    return curses.color_pair(n) if HAS_COLOR else 0


PROTOCOL_COLOR = {"OK": COLOR_GOOD, "PARTIAL": COLOR_WARN, "MISSING": COLOR_BAD, "NO_DIR": COLOR_DIM}


def msg_attr(msg):
    """Heuristic color for a one-line status message — no separate 'was this
    an error' flag is threaded through every *_flow()/action return today, so
    this reads the same failure-shaped words a human would look for."""
    low = msg.lower()
    if any(w in low for w in ("fail", "refused", "cannot", "could not", "aborted", "not added", "not found")):
        return cp(COLOR_BAD) | curses.A_BOLD
    if "cancelled" in low:
        return cp(COLOR_DIM)
    return cp(COLOR_ACCENT) | curses.A_BOLD


def draw_segments(stdscr, y, x, segments, maxw):
    """Draw (text, attr) segments left-to-right from x, clipped to maxw total
    columns — curses only takes one attribute per addstr call, so coloring
    just the status glyph in an otherwise-plain line means splitting the line
    into pieces instead of building one f-string."""
    cx = x
    end = x + maxw
    for text, attr in segments:
        if cx >= end:
            break
        chunk = text[: end - cx]
        if chunk:
            try:
                stdscr.addstr(y, cx, chunk, attr)
            except curses.error:
                pass  # bottom-right-corner write — curses' own long-standing quirk, harmless
        cx += len(chunk)


def draw_footer(stdscr, text):
    h, w = stdscr.getmaxyx()
    attr = cp(COLOR_FOOTER) | curses.A_BOLD
    stdscr.attron(attr)
    stdscr.addstr(h - 1, 0, text[: w - 1].ljust(w - 1))
    stdscr.attroff(attr)


REFRESH_MS = 1000  # auto-redraw cadence — "more or less realtime" per Max, not
                    # a tight poll loop; a getch() timeout, not a sleep, so a
                    # keypress is still handled the instant it arrives. Every
                    # tick re-reads presence files + pidfiles from disk fresh
                    # (discover_seats/check_protocol do no caching) — the
                    # "stale" complaint (2026-08-11) was purely this cadence
                    # being 2s with no on-screen indicator of when the last
                    # redraw happened, not actually-stale data underneath.


def draw_title_bar(stdscr, title):
    """Title left, bold+accent; last-redraw clock right, dim — every call
    site redraws every tick (see REFRESH_MS), so 'now' here really is the
    data's age, not a cached snapshot pretending to be fresh."""
    h, w = stdscr.getmaxyx()
    stdscr.addstr(0, 0, title, curses.A_BOLD | cp(COLOR_TITLE))
    clock = f"updated {time.strftime('%H:%M:%S')} · refresh {REFRESH_MS/1000:g}s"
    x = max(len(title) + 2, w - 1 - len(clock))
    if x + len(clock) <= w - 1:
        try:
            stdscr.addstr(0, x, clock, cp(COLOR_DIM))
        except curses.error:
            pass


# ────────────────────────── work-order stream view ───────────────────────
# Parses queue-<key>.md's markdown table(s) — the per-project WO queue this
# tool never wrote and doesn't own (Orchestrator/CLAUDE.md's territory) — so
# this is read-only, tolerant parsing: column names/order vary a bit per
# file (some use "Claimed by", some "Claimed-by"; some have a "gated"
# column, some don't), and a file can and does contain more than one table
# (prose/## headers between them) — never assume a fixed schema.

def parse_queue(path):
    """Return a list of row dicts (lowercased column-name keys) parsed from
    every markdown table found in <path>. A '|' line is a HEADER only when
    the very next line is a genuine separator row (all cells are '---'-
    shaped) — found by lookahead, not by "a blank/prose line came before
    it". That distinction matters here: queue-aiclient.md groups its rows
    with blank lines and an occasional '<!-- comment -->' WITHIN one
    continuous table (no repeated header between groups) — an earlier
    version of this parser reset the header on any non-'|' line and ended
    up zipping ordinary data rows in as bogus headers the moment a blank
    line preceded them (found live 2026-08-11, garbled ~85% of that file's
    360 rows). Only a real header+separator pair starts a new table; every
    other '|' line is data under whatever header is currently active."""
    if not os.path.isfile(path):
        return []
    try:
        with open(path, errors="replace") as f:
            lines = [ln.rstrip("\n").strip() for ln in f.readlines()]
    except OSError:
        return []
    sep_re = re.compile(r"^:?-{2,}:?$")

    def is_sep_row(line):
        if not line.startswith("|"):
            return False
        cells = [c.strip() for c in line.strip("|").split("|")]
        return bool(cells) and all(sep_re.match(c) or c == "" for c in cells)

    header = None
    rows = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if not line.startswith("|"):
            i += 1
            continue
        if i + 1 < n and is_sep_row(lines[i + 1]):
            cells = [c.strip() for c in line.strip("|").split("|")]
            header = [c.lower() for c in cells]
            i += 2
            continue
        if is_sep_row(line):
            i += 1
            continue
        if header is not None:
            cells = [c.strip() for c in line.strip("|").split("|")]
            if len(cells) >= 2:
                rows.append(dict(zip(header, cells)))
        i += 1
    return rows


def row_get(row, *keys):
    for k in keys:
        v = row.get(k)
        if v:
            return v
    return ""


DONE_STATUS_RE = re.compile(
    r"\bDONE\b|SUPERSEDED|GHOST|MERGED|CLOSED|CANCELLED|WONT-?BUILD|RETIRED|RESOLVED", re.I)


def classify_wo(row):
    """DONE (status reads as shipped/closed/dead) > CURRENT (someone has it
    claimed and it's not done) > PENDING (everything else — READY, gated,
    blocked, unclaimed). Ordering these three buckets top-to-bottom is what
    gives the stream view its 'history above, current in the middle, future
    below' shape."""
    status = row_get(row, "status")
    if DONE_STATUS_RE.search(status):
        return "DONE"
    claimed = row_get(row, "claimed by", "claimed-by").strip()
    if claimed and claimed.lower() not in ("-", "—", "none", "n/a", "unclaimed"):
        return "CURRENT"
    return "PENDING"


BUCKET_GLYPH = {"DONE": "✓", "CURRENT": "▶", "PENDING": "·"}
BUCKET_COLOR = {"DONE": COLOR_GOOD, "CURRENT": COLOR_WARN, "PENDING": COLOR_DIM}


def draw_wo_row(stdscr, y, maxw, bucket, row, highlight=False):
    """One work-order line, shared by the inline preview (project_screen)
    and the full-screen browser (wo_stream_screen) so their formatting can't
    drift apart. 'title' falls back to 'description'/'finding' — some
    queue-file rows use those instead (an alternate column schema found
    live in queue-aiclient.md's canon-draft/reconcile rows)."""
    wo = row_get(row, "wo", "wo-n", "wo-id", "id") or "?"
    title = row_get(row, "title", "description", "finding")
    status = row_get(row, "status")
    claimed = row_get(row, "claimed by", "claimed-by", "owner")
    glyph = BUCKET_GLYPH[bucket]
    if highlight:
        line = f"> {glyph} {wo:<38} {status:<14} {claimed:<16} {title}"
        stdscr.addstr(y, 0, line[:maxw], cp(COLOR_SELECTED) | curses.A_BOLD)
    else:
        draw_segments(stdscr, y, 0, [
            ("  ", curses.A_NORMAL),
            (f"{glyph} ", cp(BUCKET_COLOR[bucket]) | curses.A_BOLD),
            (f"{wo:<38} ", cp(COLOR_ACCENT) if bucket == "CURRENT" else curses.A_NORMAL),
            (f"{status:<14} ", cp(BUCKET_COLOR[bucket])),
            (f"{claimed:<16} ", cp(COLOR_DIM)),
            (title, cp(COLOR_DIM) if bucket == "DONE" else curses.A_NORMAL),
        ], maxw)


def load_wo_stream_cached(path, cache):
    """cache is a dict the caller owns across loop iterations —
    {'mtime': ..., 'ordered': ..., 'n_done':..., 'n_current':..., 'n_pending':...}
    (or {} on first call). Reparses only when the file's mtime changed since
    last call — these files can run 700+ rows on a busy project, and both
    call sites redraw every REFRESH_MS tick, so reparsing unconditionally
    would be wasted work almost every tick."""
    mtime = os.path.getmtime(path) if os.path.isfile(path) else None
    if cache.get("mtime", "__unset__") != mtime:
        rows = parse_queue(path)
        ordered, n_done, n_current, n_pending = build_wo_stream(rows)
        cache.update(mtime=mtime, ordered=ordered, n_done=n_done, n_current=n_current, n_pending=n_pending)
    return cache


def build_wo_stream(rows):
    """Bucket + order: every DONE-ish row (file order preserved within each
    bucket — that's roughly chronological), then every CURRENT (claimed,
    not done) row, then everything PENDING. Returns (ordered_list_of
    (bucket, row), done_count, current_count, pending_count)."""
    buckets = {"DONE": [], "CURRENT": [], "PENDING": []}
    for r in rows:
        buckets[classify_wo(r)].append(r)
    ordered = [(b, r) for b in ("DONE", "CURRENT", "PENDING") for r in buckets[b]]
    return ordered, len(buckets["DONE"]), len(buckets["CURRENT"]), len(buckets["PENDING"])


WO_FIELD_ORDER = ["wo", "wo-n", "wo-id", "id", "title", "description", "finding",
                   "priority", "status", "claimed by", "claimed-by", "owner",
                   "gated", "sig-required", "depends-on", "verified-against",
                   "action", "ruling", "item", "sub-parts", "notes"]


def build_wo_detail_lines(row, width):
    """Flatten a WO row dict into (text, is_heading) lines, word-wrapped to
    <width> — a queue row's 'notes'/'sub-parts' cell routinely runs to
    thousands of characters (full WO-authoring convention per CLAUDE.md:
    rich falsifiable Accept + landmine-rich How), so this always needs
    scrolling, never fits one screen. Known columns first in a stable,
    useful reading order; anything else (a file with an unrecognized
    schema) still gets shown, alphabetically, rather than silently dropped."""
    lines = []
    seen = set()
    wrap_w = max(20, width - 2)

    def emit(label, value):
        if not value:
            return
        lines.append((f"{label}:", True))
        for wline in (textwrap.wrap(value, width=wrap_w) or [""]):
            lines.append(("  " + wline, False))
        lines.append(("", False))

    for k in WO_FIELD_ORDER:
        if k in row and k not in seen:
            seen.add(k)
            emit(k.replace("-", " ").title(), row[k])
    for k in sorted(row):
        if k not in seen:
            seen.add(k)
            emit(k.replace("-", " ").title(), row[k])
    if lines and lines[-1] == ("", False):
        lines.pop()
    return lines


def wo_detail_screen(stdscr, project, bucket, row):
    """Full detail view for one WO row — opened by Enter from either the
    inline preview (project_screen) or the full-screen browser
    (wo_stream_screen). Read-only, scrollable (↑/↓ line, PgUp/PgDn page)."""
    wo = row_get(row, "wo", "wo-n", "wo-id", "id") or "?"
    scroll = 0
    stdscr.timeout(REFRESH_MS)
    while True:
        stdscr.erase()
        maxh, w = stdscr.getmaxyx()
        maxw = w - 1
        draw_title_bar(stdscr, f"{project['name']} — {wo}")
        draw_segments(stdscr, 1, 0, [
            (f"[{BUCKET_GLYPH[bucket]} {bucket}] ", cp(BUCKET_COLOR[bucket]) | curses.A_BOLD),
            (f"{project['name']} · queue-{project['key']}.md", cp(COLOR_DIM)),
        ], maxw)
        lines = build_wo_detail_lines(row, maxw)
        body_top = 3
        body_h = max(1, maxh - body_top - 1)
        scroll = max(0, min(scroll, max(0, len(lines) - body_h)))
        for i, (text, heading) in enumerate(lines[scroll: scroll + body_h]):
            attr = (cp(COLOR_ACCENT) | curses.A_BOLD) if heading else curses.A_NORMAL
            stdscr.addstr(body_top + i, 0, text[:maxw], attr)
        draw_footer(stdscr, " ↑/↓ scroll · PgUp/PgDn page · Home/End jump · b back · q quit ")
        stdscr.refresh()
        k = stdscr.getch()
        if k == -1:
            continue
        if k in (curses.KEY_UP, ord('k')):
            scroll = max(0, scroll - 1)
        elif k in (curses.KEY_DOWN, ord('j')):
            scroll = min(max(0, len(lines) - body_h), scroll + 1)
        elif k == curses.KEY_PPAGE:
            scroll = max(0, scroll - body_h)
        elif k == curses.KEY_NPAGE:
            scroll = min(max(0, len(lines) - body_h), scroll + body_h)
        elif k == curses.KEY_HOME:
            scroll = 0
        elif k == curses.KEY_END:
            scroll = max(0, len(lines) - body_h)
        elif k in (ord('b'), 27, curses.KEY_ENTER, 10, 13):
            return
        elif k == ord('q'):
            sys.exit(0)


def wo_stream_screen(stdscr, project):
    """The WO stream: one scrollable list, DONE on top, CURRENT (claimed,
    in-flight) in the middle, PENDING (READY/gated/blocked/unclaimed) on the
    bottom — opens with the viewport centered on the first CURRENT row (or
    the overall middle if nothing's currently claimed) so you land right on
    'where things are' without having to scroll to find it. Re-parses only
    when the queue file's mtime changes (these files can run 200+ rows on a
    busy project — reparsing on every REFRESH_MS tick regardless would be
    wasted work for data that hasn't moved)."""
    path = f"{COORD_DIR}/queue-{project['key']}.md"
    cached_mtime = "__unset__"  # sentinel: never equals a real mtime (float) or None
    first_load = True
    ordered, n_done, n_current, n_pending = [], 0, 0, 0
    sel = 0
    top = 0
    stdscr.timeout(REFRESH_MS)
    while True:
        mtime = os.path.getmtime(path) if os.path.isfile(path) else None
        if mtime != cached_mtime:
            cached_mtime = mtime
            rows = parse_queue(path)
            ordered, n_done, n_current, n_pending = build_wo_stream(rows)
            if first_load:
                first_load = False
                anchor = next((i for i, (b, _) in enumerate(ordered) if b == "CURRENT"), len(ordered) // 2)
                sel = min(anchor, max(0, len(ordered) - 1))
            else:
                sel = min(sel, max(0, len(ordered) - 1))

        stdscr.erase()
        maxh, w = stdscr.getmaxyx()
        maxw = w - 1
        draw_title_bar(stdscr, f"{project['name']} — work order stream")
        if os.path.isfile(path):
            stdscr.addstr(1, 0, f"{n_done} done · {n_current} current · {n_pending} pending"[:maxw], cp(COLOR_DIM))
        else:
            stdscr.addstr(1, 0, f"no queue-{project['key']}.md for this project"[:maxw], cp(COLOR_DIM))

        list_top_y = 3
        list_h = max(1, maxh - list_top_y - 1)
        if ordered:
            sel = max(0, min(sel, len(ordered) - 1))
            if sel < top:
                top = sel
            if sel >= top + list_h:
                top = sel - list_h + 1
            top = max(0, min(top, max(0, len(ordered) - list_h)))
            for i, (bucket, row) in enumerate(ordered[top: top + list_h]):
                idx = top + i
                draw_wo_row(stdscr, list_top_y + i, maxw, bucket, row, highlight=(idx == sel))
        else:
            stdscr.addstr(list_top_y, 0, "(no work orders found — empty or missing queue file)"[:maxw], cp(COLOR_DIM))
        draw_footer(stdscr, " ↑/↓ move · Enter details · PgUp/PgDn page · Home/End jump · b back · q quit ")
        stdscr.refresh()
        k = stdscr.getch()
        if k == -1:
            continue
        if k in (curses.KEY_UP, ord('k')) and ordered:
            sel = max(0, sel - 1)
        elif k in (curses.KEY_DOWN, ord('j')) and ordered:
            sel = min(len(ordered) - 1, sel + 1)
        elif k == curses.KEY_PPAGE and ordered:
            sel = max(0, sel - list_h)
        elif k == curses.KEY_NPAGE and ordered:
            sel = min(len(ordered) - 1, sel + list_h)
        elif k == curses.KEY_HOME and ordered:
            sel = 0
        elif k == curses.KEY_END and ordered:
            sel = len(ordered) - 1
        elif k in (curses.KEY_ENTER, 10, 13) and ordered:
            bucket, row = ordered[sel]
            wo_detail_screen(stdscr, project, bucket, row)
        elif k in (ord('b'), 27):
            return
        elif k == ord('q'):
            sys.exit(0)


def project_seat_counts(projects):
    """Per project: (project, total seats, alive count, most-recent-activity
    tuple). The most-recent tuple is picked across ALL of that project's
    seats (dead or alive — a just-stopped seat's last WO is still the most
    recent, informative thing to show until something newer happens)."""
    counts = []
    for p in projects:
        seats = discover_seats(p["zone"])
        alive = sum(1 for s in seats if s["heartbeat_alive"] or s["watcher_alive"])
        best = None
        for s in seats:
            if s["seconds_ago"] is None:
                continue
            if best is None or s["seconds_ago"] < best[0]:
                label = s["current_wos"] or s["last_subject"] or "(no subject)"
                best = (s["seconds_ago"], s["identity"], label)
        counts.append((p, len(seats), alive, best))
    return counts


PROTOCOL_GLYPH = {"OK": "✓", "PARTIAL": "⚠", "MISSING": "✗", "NO_DIR": "?"}


def home_screen(stdscr):
    sel = 0
    msg = ""
    stdscr.timeout(REFRESH_MS)
    while True:
        projects = load_projects()
        stdscr.erase()
        maxw = stdscr.getmaxyx()[1] - 1
        draw_title_bar(stdscr, "Samantha Implementer Manager")
        stdscr.addstr(1, 0, "↑/↓ select · Enter manage · a add project · x remove · i install/fix protocol · q quit",
                      cp(COLOR_DIM))
        rows = project_seat_counts(projects)
        # Active-seat projects first, then newest-activity first within each
        # group — mirrors discover_seats()'s per-seat ordering, applied here
        # to the top-level project list (r[2]=alive count, r[3]=best
        # (seconds_ago, identity, label) tuple or None).
        rows.sort(key=lambda r: (
            0 if r[2] > 0 else 1,
            r[3][0] if r[3] is not None else float("inf"),
        ))
        if not rows:
            stdscr.addstr(3, 0, "(no projects yet — press 'a' to add one)", cp(COLOR_DIM))
        sel = max(0, min(sel, len(rows) - 1)) if rows else 0
        for i, (p, total, alive, best) in enumerate(rows):
            y = 4 + i * 3
            proto = check_protocol(p["zone"])
            glyph = PROTOCOL_GLYPH[proto["status"]]
            marker = "> " if i == sel else "  "
            exists = "" if os.path.isdir(p["zone"]) else "  [MISSING DIR]"
            if i == sel:
                line = f"{marker}[{glyph}] {p['name']:<18} seats: {total:<3} alive: {alive:<3}{exists}"
                stdscr.addstr(y, 0, line[:maxw], cp(COLOR_SELECTED) | curses.A_BOLD)
                path_line = f"      zone: {p['zone']}"
                stdscr.addstr(y + 1, 0, path_line[:maxw], cp(COLOR_DIM))
                if best:
                    seconds_ago, identity, label = best
                    draw_segments(stdscr, y + 2, 0, [
                        ("      last: ", cp(COLOR_DIM)),
                        (identity, cp(COLOR_ACCENT)),
                        (f" — {label} ", curses.A_NORMAL),
                        (f"({format_ago(seconds_ago)})", cp(COLOR_DIM)),
                    ], maxw)
                else:
                    stdscr.addstr(y + 2, 0, "      last: (no activity recorded yet)"[:maxw], cp(COLOR_DIM))
            elif alive == 0:
                # A project with zero alive seats gets a solid dark-grey
                # BACKGROUND BOX across all three of its lines — a quiet,
                # currently-unstaffed project should read as visually
                # quieter, not compete with an actively-worked one for
                # attention. Fill the full row width first so there's no
                # default-background gap between text segments, then draw
                # the text on top using the same pair.
                box = cp(COLOR_FADED)
                blank = " " * maxw
                stdscr.addstr(y, 0, blank, box)
                stdscr.addstr(y + 1, 0, blank, box)
                stdscr.addstr(y + 2, 0, blank, box)
                line = f"{marker}[{glyph}] {p['name']:<18} seats: {total:<3} alive: {alive:<3}{exists}"
                stdscr.addstr(y, 0, line[:maxw], box)
                path_line = f"      zone: {p['zone']}"
                stdscr.addstr(y + 1, 0, path_line[:maxw], box)
                if best:
                    seconds_ago, identity, label = best
                    last_line = f"      last: {identity} — {label} ({format_ago(seconds_ago)})"
                else:
                    last_line = "      last: (no activity recorded yet)"
                stdscr.addstr(y + 2, 0, last_line[:maxw], box)
            else:
                draw_segments(stdscr, y, 0, [
                    (marker, curses.A_NORMAL),
                    ("[", cp(COLOR_DIM)),
                    (glyph, cp(PROTOCOL_COLOR[proto["status"]]) | curses.A_BOLD),
                    ("] ", cp(COLOR_DIM)),
                    (f"{p['name']:<18} ", cp(COLOR_TITLE) | curses.A_BOLD),
                    (f"seats: {total:<3} alive: ", cp(COLOR_DIM)),
                    (f"{alive:<3}", cp(COLOR_GOOD)),
                    (exists, cp(COLOR_BAD) | curses.A_BOLD),
                ], maxw)
                path_line = f"      zone: {p['zone']}"
                stdscr.addstr(y + 1, 0, path_line[:maxw], cp(COLOR_DIM))
                if best:
                    seconds_ago, identity, label = best
                    draw_segments(stdscr, y + 2, 0, [
                        ("      last: ", cp(COLOR_DIM)),
                        (identity, cp(COLOR_ACCENT)),
                        (f" — {label} ", curses.A_NORMAL),
                        (f"({format_ago(seconds_ago)})", cp(COLOR_DIM)),
                    ], maxw)
                else:
                    stdscr.addstr(y + 2, 0, "      last: (no activity recorded yet)"[:maxw], cp(COLOR_DIM))
        if msg:
            stdscr.addstr(min(4 + len(rows) * 3 + 1, stdscr.getmaxyx()[0] - 3), 0,
                          msg[:maxw], msg_attr(msg))
        draw_footer(stdscr, " [✓]=protocol OK [⚠]=partial [✗]=missing · ↑/↓ move · Enter select · a add · x remove · i install/fix · q quit ")
        stdscr.refresh()
        k = stdscr.getch()
        if k == -1:
            continue  # timeout tick — just redraw with fresh data, no key was pressed
        msg = ""
        if k in (curses.KEY_UP, ord('k')) and rows:
            sel = (sel - 1) % len(rows)
        elif k in (curses.KEY_DOWN, ord('j')) and rows:
            sel = (sel + 1) % len(rows)
        elif k in (curses.KEY_ENTER, 10, 13) and rows:
            project_screen(stdscr, rows[sel][0])
        elif k == ord('a'):
            msg = add_project_flow(stdscr, projects)
        elif k == ord('i') and rows:
            msg = install_flow(stdscr, rows[sel][0])
        elif k == ord('x') and rows:
            target = rows[sel][0]
            h, w = stdscr.getmaxyx()
            if confirm(stdscr, h - 2,
                       f"Remove {target['name']} from the managed list? Directory/seats untouched. (y/N) "):
                projects = [p for p in projects if p["key"] != target["key"]]
                save_projects(projects)
                msg = f"removed {target['name']} from the managed list"
                sel = 0
            else:
                msg = "cancelled"
        elif k in (ord('q'), 27):
            return


def install_flow(stdscr, project):
    proto = check_protocol(project["zone"])
    h, w = stdscr.getmaxyx()
    if proto["status"] == "NO_DIR":
        return f"cannot install — {project['zone']} does not exist"
    if proto["status"] == "OK":
        return f"{project['name']}: protocol already OK (settings.json + .gitignore both wired)"
    if not confirm(stdscr, h - 2,
                   f"Install/fix coordination protocol for {project['name']} at {proto['settings_path']}? (y/N) "):
        return "cancelled"
    identity_hint = next_headless_identity(project["key"])
    actions = install_protocol(project["zone"], identity_hint)
    return f"{project['name']}: " + " | ".join(actions)


def add_project_flow(stdscr, projects):
    h, w = stdscr.getmaxyx()
    name = prompt_line(stdscr, h - 2, 0, "Project name:")
    if not name:
        return "cancelled — no name given"

    zone = prompt_line(stdscr, h - 2, 0, "Directory (absolute or ~-relative, need not be a git repo):")
    if not zone:
        return "cancelled — no directory given"
    zone = os.path.abspath(os.path.expanduser(zone))

    for p in projects:
        if os.path.abspath(p["zone"]) == zone:
            return f"not added — '{p['name']}' already tracks {zone}"

    if not os.path.isdir(zone):
        if confirm(stdscr, h - 2, f"{zone} does not exist — create it? (y/N) "):
            try:
                os.makedirs(zone, exist_ok=True)
            except OSError as e:
                return f"could not create {zone}: {e}"
        else:
            return f"not added — {zone} does not exist"

    key = unique_key(slugify(name), projects)
    stdscr.addstr(h - 2, 0, f"Adding '{name}' (key: {key}, zone: {zone}) — press any key to confirm".ljust(w - 1))
    stdscr.refresh()
    stdscr.timeout(-1)
    stdscr.getch()
    stdscr.timeout(REFRESH_MS)

    projects.append({"name": name, "key": key, "zone": zone})
    save_projects(projects)

    # Automatic protocol check + install (Max's ask, 2026-08-11): a freshly
    # added project should not sit there un-wired until someone remembers to
    # press 'i' — unless it's already wired (re-adding a project someone set
    # up by hand) or has an unrecognized existing hook we shouldn't clobber.
    proto = check_protocol(zone)
    if proto["status"] == "OK":
        return f"added {name} (key={key}) — protocol already OK"
    if proto["hook_wrong"]:
        return (f"added {name} (key={key}) — NOT auto-installed: settings.json already has "
                f"a PreToolUse Bash hook that isn't ours; press 'i' to review/overwrite manually")
    actions = install_protocol(zone, f"impl-{key}-h1")
    return f"added {name} (key={key}) — auto-installed protocol: " + " | ".join(actions)


def project_screen(stdscr, project):
    sel = 0
    msg = ""
    wo_cache = {}
    wo_path = f"{COORD_DIR}/queue-{project['key']}.md"
    focus = "seats"  # "seats" or "wo" — Tab toggles which list ↑/↓/Enter drive
    wo_sel = 0
    wo_top = None  # None = "recenter on next draw" (first load / file changed)
    stdscr.timeout(REFRESH_MS)
    while True:
        seats = discover_seats(project["zone"])
        proto = check_protocol(project["zone"])
        stdscr.erase()
        maxw = stdscr.getmaxyx()[1] - 1
        draw_title_bar(stdscr, f"{project['name']} — implementer seats")
        stdscr.addstr(1, 0, f"zone: {project['zone']}"[:maxw], cp(COLOR_DIM))
        hook_word = "wired" if proto["hook_wired"] else ("wrong hook" if proto["hook_wrong"] else "missing")
        draw_segments(stdscr, 2, 0, [
            ("protocol [", cp(COLOR_DIM)),
            (PROTOCOL_GLYPH[proto["status"]], cp(PROTOCOL_COLOR[proto["status"]]) | curses.A_BOLD),
            ("] ", cp(COLOR_DIM)),
            (f"settings: {proto['settings_path']} (", cp(COLOR_DIM)),
            (hook_word, cp(COLOR_GOOD) if proto["hook_wired"] else cp(COLOR_BAD)),
            (")", cp(COLOR_DIM)),
        ], maxw)
        gi_note = ("n/a — not a git repo" if not proto["gitignore_applicable"]
                    else ("wired" if proto["gitignore_ok"] else "missing"))
        draw_segments(stdscr, 3, 0, [
            (f"          gitignore: {proto['gitignore_path']} (", cp(COLOR_DIM)),
            (gi_note, cp(COLOR_GOOD) if proto["gitignore_ok"] else cp(COLOR_BAD)),
            (")", cp(COLOR_DIM)),
        ], maxw)
        sel = max(0, min(sel, len(seats) - 1)) if seats else 0
        if not seats:
            stdscr.addstr(5, 0, "(no known seats for this project)", cp(COLOR_DIM))
        for i, s in enumerate(seats):
            y = 5 + i * 2
            if s["heartbeat_alive"] or s["watcher_alive"]:
                live, live_color = "ALIVE", COLOR_GOOD
            elif s["starting"]:
                live, live_color = "STARTING", COLOR_WARN
            else:
                live, live_color = "DEAD", COLOR_BAD
            seat_focused = (i == sel and focus == "seats")
            marker = "> " if seat_focused else "  "
            if seat_focused:
                line = (f"{marker}{s['identity']:<28} {live:<8} state={s['state']:<12} "
                         f"harness={s['harness']:<12} hb={s['heartbeat_pid'] or '-':<7} "
                         f"mon={s['watcher_pid'] or '-'}")
                stdscr.addstr(y, 0, line[:maxw], cp(COLOR_SELECTED) | curses.A_BOLD)
            else:
                draw_segments(stdscr, y, 0, [
                    (marker, curses.A_NORMAL),
                    (f"{s['identity']:<28} ", cp(COLOR_ACCENT)),
                    (f"{live:<8} ", cp(live_color) | curses.A_BOLD),
                    (f"state={s['state']:<12} harness={s['harness']:<12} "
                     f"hb={s['heartbeat_pid'] or '-':<7} mon={s['watcher_pid'] or '-'}", cp(COLOR_DIM)),
                ], maxw)
            label = s["current_wos"] or s["last_subject"] or "(no subject)"
            draw_segments(stdscr, y + 1, 0, [
                ("      last: ", cp(COLOR_DIM)),
                (label, curses.A_NORMAL),
                (f" ({format_ago(s['seconds_ago'])}, {s['last_ts'] or '?'})", cp(COLOR_DIM)),
            ], maxw)

        # Work-order stream preview — shows automatically below the seats,
        # no keypress needed (Max's ask, 2026-08-11: "should show below" /
        # "I shouldn't need to press w"), and is itself navigable: Tab moves
        # keyboard focus between the seats list and this one (both stay
        # visible either way — focus only changes what ↑/↓/Enter drive),
        # Enter on a highlighted WO opens its full detail (wo_detail_screen).
        # Same DONE-on-top / CURRENT-in-middle / PENDING-below ordering as
        # the full-screen 'w' browser; 'w' is still there for a page-at-a-
        # time view when this inline space is too cramped for a long list.
        maxh = stdscr.getmaxyx()[0]
        seats_end_y = (5 + len(seats) * 2) if seats else 6
        wo_header_y = seats_end_y + 1
        wo_list_top_y = wo_header_y + 1
        wo_list_bottom_y = maxh - 3  # row maxh-2 reserved for msg, maxh-1 for footer
        wo_list_h = wo_list_bottom_y - wo_list_top_y + 1

        prev_mtime = wo_cache.get("mtime", "__unset__")
        wo_cache = load_wo_stream_cached(wo_path, wo_cache)
        ordered = wo_cache.get("ordered", [])
        n_done, n_current, n_pending = (wo_cache.get("n_done", 0),
                                         wo_cache.get("n_current", 0), wo_cache.get("n_pending", 0))
        if wo_cache.get("mtime") != prev_mtime:
            wo_sel = next((i for i, (b, _) in enumerate(ordered) if b == "CURRENT"), len(ordered) // 2) if ordered else 0
            wo_top = None  # force recenter on this draw

        if wo_list_h > 0 and wo_header_y < maxh - 2:
            focus_hint = " [Tab: seats]" if focus == "wo" else " (Tab to browse)"
            header_txt = f" Work Orders — {n_done} done · {n_current} current · {n_pending} pending{focus_hint} "
            dash_line = ("─" * 3 + header_txt + "─" * max(0, maxw - 3 - len(header_txt)))[:maxw]
            stdscr.addstr(wo_header_y, 0, dash_line, cp(COLOR_ACCENT) if focus == "wo" else cp(COLOR_DIM))
            if ordered:
                wo_sel = max(0, min(wo_sel, len(ordered) - 1))
                if wo_top is None:
                    wo_top = max(0, min(wo_sel - wo_list_h // 2, max(0, len(ordered) - wo_list_h)))
                else:
                    if wo_sel < wo_top:
                        wo_top = wo_sel
                    if wo_sel >= wo_top + wo_list_h:
                        wo_top = wo_sel - wo_list_h + 1
                    wo_top = max(0, min(wo_top, max(0, len(ordered) - wo_list_h)))
                for i, (bucket, row) in enumerate(ordered[wo_top: wo_top + wo_list_h]):
                    idx = wo_top + i
                    draw_wo_row(stdscr, wo_list_top_y + i, maxw, bucket, row,
                                highlight=(focus == "wo" and idx == wo_sel))
            elif os.path.isfile(wo_path):
                stdscr.addstr(wo_list_top_y, 0, "(queue file has no work-order rows)"[:maxw], cp(COLOR_DIM))
            else:
                stdscr.addstr(wo_list_top_y, 0, f"(no queue-{project['key']}.md for this project yet)"[:maxw], cp(COLOR_DIM))

        if msg:
            stdscr.addstr(maxh - 2, 0, msg[:maxw], msg_attr(msg))
        footer_focus = "WOs" if focus == "wo" else "seats"
        draw_footer(stdscr, f" [focus:{footer_focus}] Tab switch · ↑/↓ move · Enter WO details · n start new · s stop · "
                             f"u restart DEAD · d delete DEAD · w full WO browser · i install/fix · r refresh · b back · q quit ")
        stdscr.refresh()
        k = stdscr.getch()
        if k == -1:
            continue  # timeout tick — just redraw with fresh data
        if k == 9:  # Tab
            focus = "wo" if focus == "seats" else "seats"
        elif k in (curses.KEY_UP, ord('k')):
            if focus == "wo" and ordered:
                wo_sel = max(0, wo_sel - 1)
            elif focus == "seats" and seats:
                sel = (sel - 1) % len(seats)
        elif k in (curses.KEY_DOWN, ord('j')):
            if focus == "wo" and ordered:
                wo_sel = min(len(ordered) - 1, wo_sel + 1)
            elif focus == "seats" and seats:
                sel = (sel + 1) % len(seats)
        elif k == curses.KEY_PPAGE and focus == "wo" and ordered:
            wo_sel = max(0, wo_sel - wo_list_h)
        elif k == curses.KEY_NPAGE and focus == "wo" and ordered:
            wo_sel = min(len(ordered) - 1, wo_sel + wo_list_h)
        elif k == curses.KEY_HOME and focus == "wo" and ordered:
            wo_sel = 0
        elif k == curses.KEY_END and focus == "wo" and ordered:
            wo_sel = len(ordered) - 1
        elif k in (curses.KEY_ENTER, 10, 13) and focus == "wo" and ordered:
            bucket, row = ordered[wo_sel]
            wo_detail_screen(stdscr, project, bucket, row)
        elif k in (ord('b'), 27):
            return
        elif k == ord('q'):
            sys.exit(0)
        elif k == ord('r'):
            msg = "refreshed"
        elif k == ord('w'):
            wo_stream_screen(stdscr, project)
        elif k == ord('n'):
            msg = start_new_flow(stdscr, project)
        elif k == ord('i'):
            msg = install_flow(stdscr, project)
        elif k == ord('s') and seats:
            target = seats[sel]
            h, w = stdscr.getmaxyx()
            if confirm(stdscr, h - 2, f"Stop {target['identity']}? (y/N) "):
                lines = stop_seat(target["identity"])
                msg = f"stopped {target['identity']}: " + " | ".join(lines)
            else:
                msg = "cancelled"
        elif k == ord('u') and seats:
            target = seats[sel]
            h, w = stdscr.getmaxyx()
            if target["heartbeat_alive"] or target["watcher_alive"]:
                msg = f"{target['identity']} is already ALIVE — nothing to restart"
            elif target["starting"]:
                msg = f"{target['identity']} is already STARTING — give it a moment"
            elif confirm(stdscr, h - 2, f"Restart {target['identity']}? (y/N) "):
                ok, note = restart_seat(target["identity"], project["zone"])
                msg = f"{target['identity']}: {'OK' if ok else 'FAIL'} ({note})"
            else:
                msg = "cancelled"
        elif k == ord('d') and seats:
            target = seats[sel]
            h, w = stdscr.getmaxyx()
            still_alive = target["heartbeat_alive"] or target["watcher_alive"]
            if still_alive:
                msg = f"{target['identity']} is still ALIVE — stop it first ('s'), then delete"
            elif confirm(stdscr, h - 2,
                         f"Delete {target['identity']}? Archives its presence file, clears watch-state. (y/N) "):
                lines = delete_seat(target["identity"])
                msg = f"deleted {target['identity']}: " + " | ".join(lines)
                sel = 0
            else:
                msg = "cancelled"


def start_new_flow(stdscr, project):
    h, w = stdscr.getmaxyx()
    if not os.path.isdir(project["zone"]):
        return f"cannot start — {project['zone']} does not exist"
    n_str = prompt_line(stdscr, h - 2, 0,
                         f"How many headless seat(s) to start for {project['name']}? [1]:")
    try:
        n = max(1, min(10, int(n_str))) if n_str else 1
    except ValueError:
        n = 1

    stdscr.addstr(h - 2, 0, " " * (w - 1))
    launched = []
    for i in range(n):
        identity = next_headless_identity(project["key"])
        stdscr.addstr(h - 2, 0, f"[{i+1}/{n}] starting {identity} ...".ljust(w - 1))
        stdscr.refresh()

        def log(m):
            pass  # kept quiet in-UI; full detail goes to the per-seat log file

        ok, note = start_headless_seat(identity, project["zone"], log)
        launched.append(f"{identity}: {'OK' if ok else 'FAIL'} ({note})")
        # Give the provision/adopt handshake a beat before the next one, so
        # concurrent bootstrap-identity.sh invocations don't race on the
        # same pending-uuid poll window.
        time.sleep(1)
    return " | ".join(launched)


def main(stdscr):
    curses.curs_set(0)
    init_colors()
    home_screen(stdscr)


if __name__ == "__main__":
    if "--help" in sys.argv or "-h" in sys.argv:
        print(__doc__)
        sys.exit(0)
    if not os.path.isdir(COORD_DIR):
        print(f"coord dir not found at {COORD_DIR} — run from (or set SAMANTHA_ORCHESTRATOR_ROOT to) your orchestrator workspace.", file=sys.stderr)
        sys.exit(1)
    curses.wrapper(main)
