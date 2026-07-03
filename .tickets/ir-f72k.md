---
id: ir-f72k
status: closed
deps: [ir-vdwn]
links: []
created: 2026-07-03T04:17:38Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-7huc
tags: [agent-loop, live-updates, runtime]
---
# Replace Haskell live-update runtime with surface-native transport

## Design

Replace feature-specific LiveUpdateScope and LiveFragmentKey constructors with generated/generic surface-native scope and fragment representations. Update active subscription tracking, broadcast, coalescing, source-client suppression, version handling, JSON encoding/decoding, and tests while preserving actor/passive behavior.

## Acceptance Criteria

Live bus tests pass with surface-native scopes/fragments. Scope keys are deterministic generated kebab-case. Old snake-case scope/fragment transport names are removed from live transport. Actor-local refresh and passive websocket invalidation behavior is preserved.

