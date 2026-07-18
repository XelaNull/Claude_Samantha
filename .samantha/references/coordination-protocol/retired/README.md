# Retired Scripts

This directory holds retired coordination-protocol scripts, kept for historical
reference only. Neither is part of the current suite; the rest of this
reference pack no longer describes them.

## watch-coordination.sh

**Status: RETIRED.** Do not arm this script.

### What it was

A directory-based, identity-aware, **echo-and-terminate** watcher: it polled the
coord-dir, and the moment it saw a new message addressed to its identity, it
printed the message and **exited**. Waking the agent required re-arming the
watcher from scratch after every single message.

### Why it was retired

The echo-and-terminate design leaves a structural **deaf gap**: the window
between a watcher exiting (message delivered) and the agent noticing and
re-arming it is a window during which the agent is not listening at all. In
practice this produced missed handoffs whenever the agent was slow to re-arm,
and it scaled poorly — every message cost a full relaunch cycle instead of a
continuous listen.

It was replaced by the persistent suite:

- **`coord-monitor.sh`** — runs forever under the harness's Monitor tool
  (or equivalent output→chat bridge) instead of exiting on each message.
  Event-driven via `fswatch` when available (with a poll-loop fallback, and a
  `--force-poll` mode for network-mounted coord-dirs where filesystem events
  don't cross machines). No re-arm between messages — the deaf gap is closed
  by construction.
- **`coord-send.sh`** — the publish half; posts a correctly-formatted,
  read-back-verified message to your own outbox instead of hand-crafting
  headers.
- **`coord-status.sh`** — read-only liveness check for the watcher +
  heartbeat pair.

`heartbeat.sh` and `bootstrap-identity.sh` were updated in place to recognize
the new watcher (both now accept `coord-monitor.sh`'s `watcher.pid` as valid
liveness evidence) rather than being retired themselves.

### Incident context

A fresh Claude instance armed this retired script by mistake on 2026-07-18,
having read a stale copy of the coordination-protocol reference pack that
still presented it as the canonical watcher. This reference pack (and its
`Nebuspace` counterpart) was subsequently synced to the live tooling to
prevent a repeat.

## git-pre-commit.sh

**Status: RETIRED.** Stale fork of the live PreToolUse hook under an old
filename — superseded by `coordination-precommit-hook.sh` (the name actually
wired in `.claude/settings.json`), which carries fixes this fork never
received (JSON-stdin tool-input parsing, the Cursor `beforeShellExecution`
permission contract). Found stale during the same 2026-07-18 sync pass that
retired `watch-coordination.sh`.
