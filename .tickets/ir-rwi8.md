---
id: ir-rwi8
status: open
deps: [ir-dhbc]
links: []
created: 2026-07-03T02:45:01Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-rjfp
tags: [agent-loop, haskell, frontend, admin, surfaces]
---
# Add Admin page composed FrontendSurface pilot

Use surface containment in production by making the Admin config page a page-level composed surface.

## Design

Add AdminPageSurface with venue scope and an AdminPageContent fragment declaring ContainsSurface edges to AdminVenueSettings, AdminInvites, AdminExports, AdminShiftTypes, and AdminRosterGroups. Render AdminAction as a parent mount containing the existing child surface mounts, preserving existing child behavior.

## Acceptance Criteria

Admin page emits an Admin page data-bepis-surface mount; generated topology shows Admin page content contains Admin child surfaces; Admin controller/config tests pass; nested runtime coverage includes Admin page or equivalent fixture.

