---
name: coordinate-star
description: "Arm star coordination mode (formerly dual): orchestrator + implementer seats on a file mailbox STAR bus. Use when multi-process seats, durable work orders, multi-project hub, or the human says star mode / dual mode / arm the coord monitor."
user-invocable: true
---

# COORDINATE-STAR — Star protocol

**Activation banner (REQUIRED — first output).** Emit these three lines with a blank line between each:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📡 **SKILL · COORDINATE-STAR** — star mode

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

**Prerequisite:** load **`coordinate`** (substrate) for harness bridging + shared grammar.

**Canon:** `.samantha/references/coordination-protocol/README.md` (PROTOCOL 1.3.0+).

## What star is

- Topology: **STAR** — hub outbox + spoke outboxes; orchestrator sees all projects.
- **Project scope:** spokes watch hub + **same-project** peers; hub-outbox filtered so other projects do not wake you.
- Scripts print `PROTOCOL_VERSION` from `PROTOCOL-VERSION` (must match the README stamp).

## Arm checklist (Orchestrator)

1. `cwd` = workspace / hub root → role orchestrator.
2. Ensure `<coord-dir>/` exists; write `orchestrator.md` from ROSTER-template; M4 read-back.
3. Arm monitor (Cursor: `notify_on_output` on `┃ COORD|┃ IDLE-KICK`; Claude: Monitor persistent).
4. Start `heartbeat.sh --identity orchestrator --role orchestrator --dir <coord-dir>` (optional `--schedule-file`).
5. Catch up: read spoke files; post HEADS-UP readiness.
6. Unicast within a project; `ALL` only for true broadcasts.

## Arm checklist (Implementer)

1. Identity `impl-<project>` or `impl-<project>-<lane>`; set `project:` (or `--project`).
2. Write presence file; M4 read-back.
3. Arm monitor as implementer — confirm arm banner shows `project=<your project>` and watches hub + same-project peers only.
4. Start heartbeat (optional schedule file / idle-policy; weak seats: `--weak-seat` + explicit policy).
5. ACK to orchestrator.

## Multi-project shared hub

`impl-sectorwars` / `impl-sectorwars-ui` share project `sectorwars` and see each other. `impl-aiclient` does not wake them. Orchestrator still sees everyone.

## After arming

Follow Disaster Rules 1–6; read mailbox before commit (precommit hook); hub-mediated deploy windows.

$ARGUMENTS
