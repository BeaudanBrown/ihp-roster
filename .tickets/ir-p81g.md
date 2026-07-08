---
id: ir-p81g
status: closed
deps: [ir-83ct]
links: []
created: 2026-07-08T04:59:57Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-5146
tags: [frontend-contracts, app-shell, chrome]
---
# Migrate app chrome partial navigation to AppShellAction

Move app shell partial navigation request metadata out of handwritten HTMX and into AppShellAction.

## Design

Migrate Application/Helper/View/Chrome.hs partial navigation. Verify page-content swaps continue to reconcile mounted FrontendSurface instances/subscriptions. Add or adjust guardrails/tests for chrome HTMX.

## Acceptance Criteria

Chrome partial navigation renders through AppShell helpers; no raw request-side HTMX in Chrome.hs; surface lifecycle after page-content swaps remains covered.


## Notes

**2026-07-08T05:32:48Z**

Migrated Application/Helper/View/Chrome.hs partial navigation to AppShellAction PartialNavigate with a declared CustomHtmx marker for route-specific target/swap/select/push-url/sync attrs. Added guardrails that Chrome no longer hand-authors request HTMX attrs and updated AppShell manifest expectations. Verified with: bash ./bin/in-env typecheck; bash ./bin/in-env frontend-check; bash ./bin/in-env hspec-test --match "Frontend contract".
