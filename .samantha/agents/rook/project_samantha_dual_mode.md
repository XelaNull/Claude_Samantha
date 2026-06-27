---
name: samantha-dual-mode-architecture
description: Verdict on Samantha Prime two-mode design (MODE A subagent dialogue vs MODE B peer instance with file protocol)
metadata:
  type: project
---

Rook verdict (2026-06-27): SIMPLIFY — delete MODE B until MODE A demonstrably fails under real workload.

**Why:** The skill-hat lifecycle (put-on / stays-on / re-don / take-off) requires stateful orchestration — watchers, ROSTER, heartbeat — to survive context compaction. A bootstrap checklist is not a reliable reconstruction mechanism. The expected failure mode is a wedged peer that looks alive on ROSTER but has lost coordination state. That's infrastructure debt, not software work.

**The counter conceded:** Context bloat in long SendMessage threads is real for sustained multi-day autonomous work. MODE B is architecturally correct for that case — just unearned.

**On persona:** "The Implementer should be Samantha, not Monk" conflates instance-class with persona. Two Samanthas = correlated blind spots = collapsed adversarial separation. Keep Monk thin as generator. The Opus/Sonnet asymmetry is the design.

**How to apply:** When MODE B is proposed again, demand evidence of MODE A failure first. When the time comes to build MODE B, recommend a simpler protocol: single shared work-order file, no heartbeat, no ROSTER, no watcher loop — file-read on demand.
