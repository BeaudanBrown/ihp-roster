---
id: ir-zyk3
status: closed
deps: []
links: [ir-2d9a]
created: 2026-07-10T05:30:27Z
type: epic
priority: 1
assignee: beaudan
tags: [agent-loop, area:staff, area:leave, area:roster, area:live-fragments, area:frontend-contracts]
---
# Move staff/unavailability mutations to surface-owned actor-local invalidation

Fix roster quick-view and staff edit modal unavailability/save regressions by making affected UI properly surface-owned and moving successful mutations to actor-local invalidation-first responses. Validation failures remain local form rerenders.

## Design

Successful mutations should save/commit data, report touched resources, return actor-local invalidation instructions plus extras such as toasts/dialog clears, and let the same plain fragment GET/refetch pipeline update actor and passive viewers. Staff edit modal must be a real StaffSurface mount; staff modal forms must not borrow staffSurfaceAction metadata outside a mounted surface. Direct business HTML/OOB on success is legacy/temporary only. No schema changes are expected.

## Acceptance Criteria

Generated HTMX attrs are valid (outerHTML, not outer-html). Staff edit modal is a mounted StaffSurface with refetchable details, preferences, and unavailability fragments. Successful staff modal profile/preferences/unavailability mutations return actor-local invalidation instructions plus toast extras, not authoritative business HTML. Roster quick-view unavailability reset happens through a refetched surface fragment. Actor and passive updates use the same fragment GET renderers wherever practical. Focused Hspec and E2E coverage verifies the reported regressions.

