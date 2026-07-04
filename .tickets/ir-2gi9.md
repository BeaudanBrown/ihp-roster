---
id: ir-2gi9
status: open
deps: []
links: []
created: 2026-07-04T04:34:06Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-lnxp
tags: [agent-loop, surfaces, billing, cleanup]
---
# Move Billing checkout-return fragment URL into MountState

Remove the last data-live-update-url production override by representing Billing checkout-return render state with the existing FrontendSurface MountState concept.

## Design

Add a Billing MountState declaration with narrow checkout-return fields needed to derive fragment metadata. Update billing SurfaceImpl handlers so the billing status fragment URL is derived from typed mount state. Remove data-live-update-url from Web/View/Billing/Index.hs and remove target.dataset.liveUpdateUrl fallback from frontend/ts/app-live-updates.ts/static bundle. Update Billing tests to assert generated surface fragment metadata instead of legacy DOM override attrs.

## Acceptance Criteria

Billing status refresh after checkout still uses the correct fragment URL. No production data-live-update-url attr or TS fallback remains. Guardrails/tests fail if data-live-update-url returns outside negative assertions or docs. frontend-check, typecheck, and focused Billing Hspec pass.

