# Timesheets

## Purpose

`Web/Timesheets/` owns timesheet week paths, direct read models, validation,
FrontendSurface metadata, and response helpers. The controller remains
responsible for request orchestration, authorization, params, and
redirects/fragments.

## Entry Points

- `Web/Controller/Timesheets.hs` - controller actions.
- `Web/Timesheets/Paths.hs` - canonical week/day routes.
- `Web/Timesheets/Projection.hs` - direct timesheet week read-model construction.
- `Web/Timesheets/FrontendSurface.hs` - FrontendSurface contract/runtime bridge.
- `Web/Timesheets/Responses.hs` - HTMX/OOB response helpers.
- `Web/Timesheets/Validation.hs` - input validation helpers.
- `Web/View/Timesheets/` - HSX rendering.

## Related Docs

- `SPEC.md`
- `AGENTS.md`
- `docs/workstreams/rooks-pilot.md`
- `docs/workstreams/pay-config-versioning.md`
- `docs/archive/plans/30-timesheets-and-leave.md`
