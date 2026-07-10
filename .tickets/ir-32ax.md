---
id: ir-32ax
status: open
deps: [ir-g9m6]
links: []
created: 2026-07-10T05:30:28Z
type: feature
priority: 1
assignee: beaudan
parent: ir-zyk3
tags: [agent-loop, area:staff, area:live-fragments, area:frontend-contracts]
---
# Mount and complete StaffSurface for staff edit modal

The staff edit modal currently uses generated staff surface action metadata without being a coherent mounted StaffSurface owner. Make the modal a real StaffSurface before moving its mutations to actor-local invalidation.

## Design

Render the staff edit modal body inside a real StaffSurface mount with scope {venueId, staffId}. Complete/refine StaffSurface fragments for staff details, staff shift preferences, and staff unavailability (including form/list as appropriate). Add fragment GET/render paths returning plain target nodes. Preserve modal open-section state via mount state, query/hidden field, or fragment-level rendering so saves keep the relevant accordion open. Authorization must be manager/current-venue scoped for manager modal access, not self-service-only.

## Acceptance Criteria

Staff edit modal includes data-bepis-surface="staff" and valid data-bepis-surface-config. StaffSurface has all fragments needed for profile, preferences, and unavailability modal workflows. Generated staff actions live inside the mounted staff surface. Fragment GET endpoints are authorized and return plain target nodes. Tests cover mount config, target ids, routes, and auth.

