---
name: coordinate-solo
description: "Arm solo coordination mode: one agent session, in-session subagents as workers, optional local idle scheduler. Use when staying in one context window, or when the human says solo mode / in-session workers / no peer seats."
user-invocable: true
---

# COORDINATE-SOLO — Solo protocol

**Activation banner (REQUIRED — first output).** Emit these three lines with a blank line between each:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📡 **SKILL · COORDINATE-SOLO** — solo mode

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

**Prerequisite:** engage shared rules from **`coordinate`** (substrate) if not already loaded.

## What solo is

- **One** agent session (Samantha as orchestrator-of-self).
- Workers = **in-session subagents** (`Task` / Agent), not peer mailbox seats.
- Durable trail = plans, MEMORY, commits — not a multi-seat STAR bus (unless you optionally arm a local heartbeat for self idle-kick).

## Arm checklist

1. Confirm star mode is **not** required (see star threshold in coordination-protocol README).
2. Do **not** start `coord-monitor` against a shared multi-project hub unless this session is intentionally a star seat.
3. Dispatch workers with zone/path scope; one committer serializes commits (PAR method still applies inside the session).
4. Optional: arm local `heartbeat.sh --identity <self> --role orchestrator --dir <local-coord>` only if you want IDLE-KICK self-scheduling without peer spokes.

## Protocol stub

Full star novel is **not** required reading for solo. Inherit from substrate:

- Disaster rules that apply inside one tree (explicit paths, no `git add -A`, read before commit when a mailbox exists)
- Generator ≠ evaluator (Samantha reviews Monk)
- Pause triggers / safety carveouts

Skip: spoke watch sets, deploy-window hub broadcast, identity bootstrap, multi-project `queue-*.md` — until you switch to **`coordinate-star`**.

$ARGUMENTS
