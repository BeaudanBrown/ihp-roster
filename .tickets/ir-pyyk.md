---
id: ir-pyyk
status: closed
deps: []
links: []
created: 2026-07-07T03:24:30Z
type: bug
priority: 1
assignee: Beaudan Brown
parent: ir-vw5m
tags: [agent-loop, lazy-loading, frontend-surface, roster]
---
# Fix lazy fragment root shell and canonical attrs

Restore the user-visible staff-panel lazy loading layout and align the active Haskell lazy renderer with canonical UI-region attrs.

## Design

Replace or evolve renderFrontendSurfaceLazyFragment to accept a config with root/slot classes, placeholder/chrome classes if needed, accessible label/defaults, retry enabled, and trigger override/default. Emit canonical generated UI-region attrs. Update the roster staff panel call site to pass rosterStaffPanelFragmentClasses while keeping renderRosterStaffPanelPlaceholder as the server-owned placeholder body.

## Acceptance Criteria

Staff panel lazy placeholder root has col-12 col-xl-4 col-xxl-3 roster-layout-side. Placeholder root keeps id=roster-staff-panel-fragment. Placeholder uses data-bepis-fragment="true" and data-bepis-lazy-surface="true". No data-bepis-surface-lazy* attrs remain in the active renderer. Existing lazy fetch still swaps outerHTML with the authoritative fragment.


## Notes

**2026-07-07T03:36:31Z**

Implemented in one cleanup pass. Summary: added canonical FrontendSurface lazy fragment config/renderer with feature-owned root classes and generated UI-region attrs; wired roster staff panel slot classes; derived lazy load policy, trigger, and placeholder defaults from existing Lazy/Trigger/Placeholder options; deleted stale Application.Helper.View.LazySurface; updated all mounted fragment constructors/call sites; added Hspec/guardrail/docs coverage. Verification: typecheck, frontend-contracts-check, frontend-test, hspec-test --match FrontendSurface, hspec-test --match lazy, frontend-surface-compile-fail-check, frontend-surface-guardrails, and frontend-check passed. Note: attempted old command name surface-compile-fail-check, but project command is frontend-surface-compile-fail-check.
