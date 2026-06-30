---
id: ir-cg2x
status: closed
deps: [ir-hnpv]
links: []
created: 2026-05-29T03:16:08Z
type: task
priority: 2
assignee: beaudan
parent: ir-5v0t
tags: [agent-loop, admin, low-risk]
---
# Migrate venue settings invites and exports fragments

Move the simplest admin single-fragment surfaces to shared OOB actor responses.

## Design

For venue settings, invites, and exports: keep existing fragment contracts, set successful HTMX forms/toggles to hx-swap=none where appropriate, and respond with OOB fragment plus toast/errors using the shared helper.

## Acceptance Criteria

Controller/config specs show OOB fragment responses; direct successful hx-target outerHTML paths are removed for these sections; focused checks pass.


## Notes

**2026-06-30T02:01:33Z**

Implemented. Venue settings, invites, and exports now render successful HTMX actor responses as OOB single-fragment refreshes and set HX-Reswap=none. Their forms/toggles now use hx-swap=none where appropriate, while fragment GET endpoints still return plain target nodes. Added WithSwap render variants for the three simple admin fragments and updated focused admin specs to assert HX-Reswap/OOB response shape. Shift types and roster groups remain deferred as planned because of focus/row-editing constraints. Verification passed: bash ./bin/in-env typecheck; bash ./bin/in-env hspec-test --match 'AdminController'.
