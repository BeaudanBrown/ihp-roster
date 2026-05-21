---
id: ir-bdvn
status: closed
deps: [ir-6thh, ir-l089]
links: [ir-dk24]
created: 2026-05-21T08:31:17Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-xyzw
tags: [agent-loop, area:roster, area:performance]
---
# Optimize direct roster fragment read costs before projection cleanup

After the rollback/parity fixes land, the SQL/direct roster read path needs performance tuning. Local baseline repeats staff option-state and conflict builders on warm fragments, making row/day/staff-panel reads slower than projection-cache hits. Tune the direct path or narrow fragment reads before deleting the projection rollback.

## Design

Start only after ir-6thh restores a true projection baseline and ir-l089 aligns conflict semantics. Profile and reduce roster_direct_build_staff_option_states and roster_direct_build_slot_conflicts for fragment GETs. Prefer set-based/narrow reads or request-local reuse, not a new cross-request cache.

## Acceptance Criteria

Focused roster baseline timings compare against the restored projection baseline and show warm row/day/staff-panel fragment regressions are materially reduced or explicitly accepted with updated rationale; focused roster tests and typecheck pass.


## Notes

**2026-05-21T11:56:52Z**

Adjusted after code review: performance tuning should wait until rollback/parity is real and multi-preference conflict semantics are aligned; this ticket now depends on ir-6thh and ir-l089.

**2026-05-21T12:44:54Z**

HANDOFF: Narrowed direct roster fragment reads so staff-panel skips option/conflict builders and row/day render payloads build option/conflict output only for requested slots while preserving week-wide facts; updated baseline timing coverage/docs; verification passed: typecheck, focused direct baseline, focused row conflict regression, full RosterWeeks Hspec; remaining risk is larger-roster/browser timing variance, so keep projection rollback seam until adoption decision.
