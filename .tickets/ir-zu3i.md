---
id: ir-zu3i
status: in_progress
deps: [ir-f72k]
links: []
created: 2026-07-03T04:17:38Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-7huc
tags: [agent-loop, surfaces, invalidation]
---
# Rebuild invalidation planning on FrontendSurface specs

## Design

Replace old Web.LiveSurfaceRegistry/manifest usage with generated FrontendSurface registry facts. Planning still maps touched LiveResources to active generated surface scopes/fragments and keeps permission checks server-side. Do not keep a parallel legacy registry for migrated production surfaces.

## Acceptance Criteria

Admin, Roster, Timesheets, Leave Requests, Billing, Profile, and Support invalidations plan correctly from generated FrontendSurface facts. No legacy registered live-surface catalog/manifest path remains. Focused Hspec covers representative planning and authorization.

