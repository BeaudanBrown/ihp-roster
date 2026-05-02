# Leave And Availability

## Purpose

`Web/LeaveRequests/` owns leave/availability projections and profile
self-service integration. User-facing language is moving toward
availability/unavailable periods for the pilot, while the backing model remains
leave/unavailability history until renamed by a future migration.

## Entry Points

- `Web/Controller/LeaveRequests.hs` - controller actions.
- `Web/LeaveRequests/Projection.hs` - list/read models.
- `Web/LeaveRequests/ProfileSelfService.hs` - profile page fragments.
- `Web/View/LeaveRequests/` - HSX rendering.

## Related Docs

- `SPEC.md`
- `AGENTS.md`
- `docs/workstreams/rooks-pilot.md`
- `docs/workstreams/record-retention.md`
- `docs/archive/plans/30-timesheets-and-leave.md`
