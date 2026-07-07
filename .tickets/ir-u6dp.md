---
id: ir-u6dp
status: closed
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


## Notes

**2026-07-07T03:36:31Z**

Implemented in one cleanup pass. Summary: added canonical FrontendSurface lazy fragment config/renderer with feature-owned root classes and generated UI-region attrs; wired roster staff panel slot classes; derived lazy load policy, trigger, and placeholder defaults from existing Lazy/Trigger/Placeholder options; deleted stale Application.Helper.View.LazySurface; updated all mounted fragment constructors/call sites; added Hspec/guardrail/docs coverage. Verification: typecheck, frontend-contracts-check, frontend-test, hspec-test --match FrontendSurface, hspec-test --match lazy, frontend-surface-compile-fail-check, frontend-surface-guardrails, and frontend-check passed. Note: attempted old command name surface-compile-fail-check, but project command is frontend-surface-compile-fail-check.
