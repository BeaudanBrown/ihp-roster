# Roster Weeks

## Purpose

`Web/RosterWeeks/` owns the roster-week feature modules that keep
`Web/Controller/RosterWeeks.hs` focused on controller orchestration.

## Entry Points

- `Web/Controller/RosterWeeks.hs` - controller actions.
- `Web/RosterWeeks/Projection.hs` - read model/projection construction.
- `Web/RosterWeeks/RenderData.hs` - view-facing render data.
- `Web/RosterWeeks/Responses.hs` - HTMX/OOB response helpers.
- `Web/RosterWeeks/LiveUpdates.hs` - live invalidation refs and fanout helpers.
- `Web/RosterWeeks/Paths.hs` - canonical route/query helpers.
- `Web/RosterWeeks/Dom.hs` - stable DOM ids/selectors.
- `Web/RosterWeeks/Conflicts.hs` - conflict presentation helpers.
- `Web/RosterWeeks/Service.hs` - roster workflow/domain service helpers.
- `Web/View/RosterWeeks/` - HSX rendering.

## Related Docs

- `SPEC.md` - implemented roster behavior.
- `AGENTS.md` - local editing and verification rules.
- `docs/workstreams/rooks-pilot.md`
- `docs/workstreams/roster-groups.md`
- `docs/archive/plans/20-roster-and-conflicts.md`
- `docs/archive/plans/49-roster-groups-and-venue-bootstrap.md`
- `docs/archive/plans/52-roster-mobile-refactor.md`
