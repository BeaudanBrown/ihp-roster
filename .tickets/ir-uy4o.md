---
id: ir-uy4o
status: closed
deps: [ir-4gm9, ir-p81g, ir-dvoi, ir-hreg]
links: []
created: 2026-07-08T04:59:57Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-5146
tags: [frontend-contracts, guardrails, htmx]
---
# Remove raw HTMX helper escape hatches

Remove helper APIs that expose arbitrary app-owned request-side HTMX after their callers have migrated.

## Design

Remove raw appToggleHx* fields or make them private/transitional only, replace remaining users with generated Surface/AppShell attrs, remove legacy raw OverlayFormAction, and tighten raw HTMX guardrails.

## Acceptance Criteria

No production helper exposes arbitrary request-side HTMX fields; guardrails catch raw request-side hx-* in app views/helpers; generated/custom-declared HTMX remains allowed.


## Notes

**2026-07-08T06:08:24Z**

Removed remaining raw request-side HTMX helper escape hatches: ToggleButton no longer exposes appToggleHx* fields, Overlay DialogFormAction no longer renders HTMX request attrs, and Billing's retry action uses the narrowed native dialog form constructor. Tightened guardrails to reject raw request-side hx-* in app view/helper Haskell and to keep appToggleHx* deleted. Verified with: bash ./bin/in-env typecheck; bash ./bin/in-env frontend-contracts-check; bash Config/nix/scripts/frontend/surface-guardrails; bash ./bin/in-env hspec-test --match "Billing" --match "SurfaceGuard".
