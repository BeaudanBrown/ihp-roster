# Timesheets

## Purpose

`Web/Timesheets/` owns timesheet week paths, direct read models (including
transient roster-derived suggestions), materialization mutations, validation,
FrontendSurface metadata, and response helpers. The controller remains
responsible for request orchestration, authorization, params, and
redirects/fragments.

## Entry Points

- `Web/Controller/Timesheets.hs` - controller actions.
- `Web/Timesheets/Paths.hs` - canonical week/day routes.
- `Web/Timesheets/Projection.hs` - entry and roster-suggestion read-model construction.
- `Web/Timesheets/Suggestion.hs` - suggestion value and snapshot conversion.
- `Web/Timesheets/Mutations.hs` - entry persistence, provenance, idempotency, and invalidation.
- `Web/Timesheets/FrontendSurface.hs` - FrontendSurface contract/runtime bridge.
- `Web/Timesheets/Responses.hs` - HTMX/OOB response helpers.
- `Web/Timesheets/Validation.hs` - input validation helpers.
- `Web/View/Timesheets/` - HSX rendering.

## FrontendSurface Boundary

Timesheets is the marker-indexed runtime pilot. `Web/Timesheets/FrontendSurface.hs`
builds its scope, mount state, fragment params, and canonical scope key through
exact `SurfaceFields`; it must not use phantom JSON field carriers or required
field fallbacks. Views resolve action and field metadata with owning Surface and
marker type applications rather than scanning the reflected registry by names.

Week navigation and filter requests declare the typed HTMX sync recipe
`closest #timesheet-week-shell:replace` in the Surface spec. The shell DOM ID and
action metadata come from marker-indexed accessors; views do not hand-author the
sync attribute or a custom-HTMX substitute. Fragment URL, target, and protection
values remain local server-rendered mount data.

## Related Docs

- `SPEC.md`
- `AGENTS.md`
- `docs/workstreams/rooks-pilot.md`
- `docs/workstreams/pay-config-versioning.md`
- `docs/archive/plans/30-timesheets-and-leave.md`
