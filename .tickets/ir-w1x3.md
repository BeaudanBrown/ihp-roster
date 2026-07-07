---
id: ir-w1x3
status: closed
deps: [ir-pyyk, ir-u6dp]
links: []
created: 2026-07-07T03:24:30Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-vw5m
tags: [agent-loop, lazy-loading, frontend-surface]
---
# Apply unified lazy renderer to all relevant fragments

Audit and migrate current lazy placeholder mounts to the canonical lazy renderer/config path.

## Design

Audit current lazy call sites and mounted fragments, including roster staff panel, frontend surface lab, and lazy roster/timesheet fragments that may participate in initial placeholder rendering. Ensure every actual lazy placeholder mount uses the canonical renderer/config. For lazy fragments that are only lazy in live/resync metadata but not initially placeholder-rendered, document why no placeholder render is needed.

## Acceptance Criteria

All renderFrontendSurfaceLazyFragment usages are canonical/configured. No feature-specific lazy HTMX wrapper exists outside the runtime helper. Existing lab coverage still demonstrates generic behavior. Roster staff panel, lab, and any other initial lazy placeholder behavior are consistent.


## Notes

**2026-07-07T03:36:31Z**

Implemented in one cleanup pass. Summary: added canonical FrontendSurface lazy fragment config/renderer with feature-owned root classes and generated UI-region attrs; wired roster staff panel slot classes; derived lazy load policy, trigger, and placeholder defaults from existing Lazy/Trigger/Placeholder options; deleted stale Application.Helper.View.LazySurface; updated all mounted fragment constructors/call sites; added Hspec/guardrail/docs coverage. Verification: typecheck, frontend-contracts-check, frontend-test, hspec-test --match FrontendSurface, hspec-test --match lazy, frontend-surface-compile-fail-check, frontend-surface-guardrails, and frontend-check passed. Note: attempted old command name surface-compile-fail-check, but project command is frontend-surface-compile-fail-check.
