---
id: ir-u6dp
status: open
deps: [ir-pyyk]
links: []
created: 2026-07-07T03:24:30Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-vw5m
tags: [agent-loop, lazy-loading, frontend-surface, contracts]
---
# Derive lazy defaults from existing fragment options

Make existing FrontendSurface Lazy, Trigger, Placeholder, and Eager options drive lazy render defaults where feasible.

## Design

Add runtime/type-level helpers that inspect known fragment options enough to derive eager vs lazy, default trigger from Trigger, and default placeholder kind from Placeholder. Avoid new primitives. Keep layout classes explicit in render config. Reduce or wrap hand-written mountedFragmentLoadPolicy lazy/eager usage where the spec already knows the decision.

## Acceptance Criteria

Lazy primitive options are reflected into lazy render defaults. Lab Trigger Load / Placeholder Panel semantics are preserved or explicitly mapped. Feature code no longer needs open-text lazy/eager decisions where the spec already knows them. Compile-failure or Hspec coverage catches missing/incorrect option reflection.

