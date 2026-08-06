# Leave And Availability

## Ownership

`Web/LeaveRequests/` owns venue-scoped leave/unavailability read models,
blackouts, warning projections, mutations, and the shared self-service Surface
used by Profile and roster contexts. Controllers retain request orchestration
and authorization response choices; views live under `Web/View/LeaveRequests/`.

## Start Here

- `SelfService.hs` — shared form/history rendering and mounts.
- `ReadModel.hs` — request projections.
- `Blackouts.hs` and `AvailabilityWarnings.hs` — venue policy projections.
- `Mutations.hs` — writes and typed invalidation.
- `FrontendSurface.hs` — manager and self-service Surface contracts.

See `SPEC.md` for durable date, lifecycle, blackout, and privacy rules and
`AGENTS.md` for local editing constraints.
