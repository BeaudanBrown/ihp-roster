---
id: ir-4vza
status: closed
deps: [ir-32ax]
links: []
created: 2026-07-10T05:30:28Z
type: bug
priority: 1
assignee: beaudan
parent: ir-zyk3
tags: [agent-loop, area:staff, area:preferences, area:live-fragments]
---
# Move staff modal profile and preferences saves to StaffSurface actor invalidation

Staff edit modal Save Profile and Save Shift Preferences should persist via HTMX while keeping the modal open on the submitted section and refreshing through StaffSurface.

## Design

On profile save, persist staff changes, emit staff-profile/staff-preferences resources as appropriate, actor-invalidate the staff details fragment, keep the modal open on Profile Details, and return toast extras only. On preferences save, persist shift preferences, emit staff-preferences resource, actor-invalidate the preferences fragment, keep the modal open on Shift Preferences, and return toast extras only. Roster-dependent invalidations continue through touched resources/active-scope expansion. Validation failures remain local.

## Acceptance Criteria

Save profile details works and refreshes through StaffSurface with the modal open on Profile Details. Save shift preferences works and refreshes through StaffSurface with the modal open on Shift Preferences. Validation failures still render errors locally. No authoritative business OOB success fragments are returned where StaffSurface refetch is available.

