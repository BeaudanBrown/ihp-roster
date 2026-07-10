---
id: ir-7zq6
status: closed
deps: [ir-xua1, ir-32ax]
links: []
created: 2026-07-10T05:30:28Z
type: bug
priority: 1
assignee: beaudan
parent: ir-zyk3
tags: [agent-loop, area:staff, area:leave, area:live-fragments]
---
# Move staff modal unavailability submit to StaffSurface actor invalidation

Manager/admin staff edit modal unavailability submit currently swaps incorrectly and can return/nest nonsense content.

## Design

After StaffSurface owns the modal, change successful staff unavailability create to save for the selected staff member, emit staff-leave touched resources, actor-invalidate StaffSurface unavailability/form/list fragments, and return toast extras only. Validation failure directly rerenders the staff leave form fragment with field errors. Keep staff id parsing and current-venue authorization total and explicit.

## Acceptance Criteria

Manager/admin can submit staff unavailability from the modal. The form resets to defaults via StaffSurface refetch, the list updates via StaffSurface refetch, the DOM has no nested/duplicate form fragment ids, and no business OOB success fragments are returned. Focused Hspec and E2E cover the flow.

