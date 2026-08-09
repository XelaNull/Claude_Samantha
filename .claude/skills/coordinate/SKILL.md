---
name: coordinate
description: "Common substrate for Samantha coordination modes (solo and star): seat identity, mailbox grammar, disaster rules that apply in both modes, harness wake bridging, and idle-kick/scheduler concepts. Use when arming coordination, choosing solo vs star, or when coordinate-solo / coordinate-star need shared protocol."
user-invocable: true
---

# COORDINATE — Shared substrate

**Activation banner (REQUIRED — first output).** Emit these three lines with a blank line between each:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📡 **SKILL · COORDINATE** — shared substrate

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This skill is the **common substrate**. Mode-specific arming lives in:

| Skill | Mode |
|-------|------|
| `coordinate-solo` | One session; workers = in-session subagents |
| `coordinate-star` | Multi-process STAR (orchestrator + implementers; file mailbox) |

**One install of the Reference Pack.** Mode is chosen when a skill arms — not by copying vs skipping scripts at install time.

## Shared canon (read, don't reinvent)

| Topic | Where |
|-------|--------|
| Star topology + scripts | `.samantha/references/coordination-protocol/README.md` |
| Message grammar / tags | `MAILBOX-template.md` |
| Disaster rules 1–6 | coordination-protocol README |
| Project-scoped awareness (1.3.0) | README § Project-scoped awareness; `coord-address-filter.sh` |
| Presence sidecar | `coord-presence.sh` · `.presence/<id>` |
| Idle schedule | `IDLE-SCHEDULE-template.md` |
| Parallel safety (PAR) | `PARALLEL-SAFETY.md` |
| Safety gates | `.samantha/references/safety-carveouts.md` |

## Harness wake bridge (both modes that use scripts)

| Host | Arm monitor |
|------|-------------|
| **Claude Code** | `Monitor` tool, `persistent:true`, on `coord-monitor.sh …` |
| **Cursor Agent** | `Shell` with `notify_on_output` matching `┃ COORD` / `┃ IDLE-KICK`; keep process backgrounded |

Arm **once per session**. On heartbeat `exit 42` (WATCHER-DOWN): re-arm **monitor first**, then heartbeat.

## Seat scheduler (IDLE-KICK family)

Every seat (orchestrator *and* implementer) may run `heartbeat.sh` with an `--idle-policy` (later: structured activity schedule). A kick means: wake this seat and run due idle work — not "stand by." Hub self-nudge is addressed to self so spokes do not wake (1.2.1).

## When to escalate to a mode skill

- Need only in-session workers → engage **`coordinate-solo`**
- Need durable mailbox / multi-seat / multi-project hub → engage **`coordinate-star`**

$ARGUMENTS
