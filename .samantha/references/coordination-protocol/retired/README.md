# Retired Scripts — Tombstones Only

This directory **does not ship executable scripts**. The retired watchers/hooks
were deleted from the tree because keeping them on disk caused a live footgun:
on 2026-07-18 a fresh instance armed the retired one-shot watcher after reading
a stale reference pack that still presented it as canonical.

History (full file bodies) lives in **git**. Do not resurrect these into the pack.

| Former path | Superseded by | Why retired |
|-------------|---------------|-------------|
| `watch-coordination.sh` | `../coord-monitor.sh` | Echo-and-terminate left a deaf gap between exit and re-arm; missed handoffs. Persistent monitor closes that by construction. |
| `git-pre-commit.sh` | `../coordination-precommit-hook.sh` | Stale fork under an old filename; missing JSON-stdin + Cursor `beforeShellExecution` fixes that the live hook carries. |

## Do not arm

If you find a copy of either script in an old deployment or chat transcript:

1. **Stop.** Do not copy it back into this pack.
2. Arm `coord-monitor.sh` + `heartbeat.sh` (see `../README.md`).
3. Confirm with `coord-status.sh` → BOTH ALIVE.

`heartbeat.sh` still accepts a process whose cmdline contains `watch-coordination.sh`
as PID-compat evidence only — that is for leftover deployments mid-cutover, not
permission to reintroduce the script.
