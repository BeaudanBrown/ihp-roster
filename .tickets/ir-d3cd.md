---
id: ir-d3cd
status: open
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

