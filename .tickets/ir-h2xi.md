---
id: ir-h2xi
status: closed
deps: []
links: []
created: 2026-05-22T06:52:44Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [area:live-fragments, area:architecture]
---
# Typed live surface golden pathway

Unify live-surface fragment declarations so resources, refs, containment, and request pathways are expressed through typed contracts.

## Design

Implement in staged chunks: consolidate fragment refs and dependencies into one FragmentContract, make dependency choices explicit, then harden endpoint/transport escape hatches.

## Acceptance Criteria

Typed live surfaces derive actor, passive, resync, and projection refs from one fragment contract. Missing fragment declarations fail compilation where constructors are exhaustive. Existing live-update tests and focused e2e pass after each chunk.


## Notes

**2026-05-22T07:22:19Z**

Implemented all staged child tickets. Final verification: typecheck; focused controller/live-surface Hspec (255 examples); e2e/live-update-declarative-adapter.spec.ts (10 passed); e2e/roster-live-fragments.spec.ts (5 passed). Pattern now: surfaces declare one FragmentContract per fragment; dependencies are explicit via DependsOnLiveResources or ResyncOnlyFragment; live-fragment endpoints must pass through serveTypedLiveFragment.
