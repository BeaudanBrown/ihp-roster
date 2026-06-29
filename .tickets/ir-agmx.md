---
id: ir-agmx
status: closed
deps: [ir-fp76, ir-vgwk, ir-5dd9, ir-a02h]
links: []
created: 2026-06-29T13:12:16Z
type: feature
priority: 2
assignee: beaudan
parent: ir-21jr
tags: [agent-loop, frontend, ui-regions, pilot]
---
# Pilot one additional low-risk region transition

Apply the region transition system to one low-risk non-roster region.

## Design

Choose during implementation from Admin Xero secondary panel, profile/leave content, or admin settings/invites fragment. Do not combine this with major live-fragment migration work.

## Acceptance Criteria

One non-roster region demonstrates opt-in transition attrs; no feature-specific TypeScript is added; unsuitable candidates are documented with reasons.


## Notes

**2026-06-29T13:44:42Z**

Piloted Admin Invites live fragment as the low-risk non-roster region with fade transition attrs rendered by shared Haskell uiRegionTransitionAttrs. Deferred Admin Xero/profile/leave candidates because they have broader multi-fragment/validation-local behavior better handled by future migration tickets. Verification: typecheck, focused hspec UI region attr test, frontend-contracts-check, frontend-check passed.
