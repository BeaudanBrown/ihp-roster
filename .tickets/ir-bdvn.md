---
id: ir-bdvn
status: open
deps: []
links: [ir-dk24]
created: 2026-05-21T08:31:17Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-xyzw
tags: [agent-loop, area:roster, area:performance]
---
# Optimize direct roster fragment read costs before projection cleanup

The SQL/direct roster read path passed parity but local baseline repeats staff option-state and conflict builders on warm fragments, making row/day/staff-panel reads slower than projection-cache hits. Tune the direct path or narrow fragment reads before deleting the projection rollback.

## Design

Profile and reduce roster_direct_build_staff_option_states and roster_direct_build_slot_conflicts for fragment GETs. Prefer set-based/narrow reads or request-local reuse, not a new cross-request cache.

## Acceptance Criteria

Focused roster baseline timings show warm row/day/staff-panel fragment regressions are materially reduced or explicitly accepted with updated rationale; focused roster tests and typecheck pass.

