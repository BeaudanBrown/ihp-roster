---
id: ir-lptt
status: closed
deps: [ir-7ylh]
links: []
created: 2026-07-04T01:20:55Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-7jqj
tags: [agent-loop, surfaces, naming]
---
# Final surface naming cleanup

Rename remaining stale live-surface/runtime variables and types to the cleanest final architecture names after compatibility deletion.

## Design

Prefer ergonomic surface-native names over backward compatibility. Evaluate LiveUpdateScope, LiveFragmentKey, LiveUpdateWireFragment, LiveUpdateSubscription, and related variables after stale code is gone. Rename where it improves clarity, update generated DTO names if worthwhile, and refresh docs/tests/guardrails.

## Acceptance Criteria

No stale compatibility names remain in production APIs/docs except deliberate protocol names documented in ticket notes; naming is consistent with FrontendSurface/SurfaceResource/SurfaceInvalidation architecture; full verification passes.

