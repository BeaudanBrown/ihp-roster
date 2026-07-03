---
id: ir-d3cd
status: in_progress
deps: [ir-7x48]
links: []
created: 2026-07-03T11:15:32Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-3b6m
tags: [agent-loop, surfaces, guardrails]
---
# Delete legacy live scope adapters and guard final surface-native runtime

Remove temporary compatibility code and lock the final surface-native live update architecture with docs and guardrails.

## Design

Delete old LiveUpdateScope and LiveFragmentKey ADTs if no longer needed, liveUpdateScopeFromSurface/liveFragmentKeyFromSurface case lists, old registry adapter exports, and any temporary accept-both protocol shims. Update docs to describe active surface-native subscriptions and add guardrails preventing old ADT constructors/case lists from returning.

## Acceptance Criteria

No legacy scope/fragment constructor ADTs or planning adapter case lists remain. Docs describe final runtime. Guardrail scan enforces deletion. Full agreed verification passes and epic closeout note records final state.


## Notes

**2026-07-03T11:47:43Z**

Reached implementation decision point before final cleanup: fully deleting legacy LiveUpdateScope/LiveFragmentKey constructors requires either (a) a big-bang replacement of ~299 constructor call sites with generated/surface-native smart constructors and typed payload helpers, or (b) temporary pattern-synonym compatibility that removes the old ADT definitions but keeps legacy constructor names. User preference says no stale shim/compat/dead code, so option (a) is the consistent path; pausing before making that broad mechanical migration.
