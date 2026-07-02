# Roster Weeks

## Purpose

`Web/RosterWeeks/` owns the roster-week feature modules that keep
`Web/Controller/RosterWeeks.hs` focused on controller orchestration.

## Entry Points

- `Web/Controller/RosterWeeks.hs` - controller actions.
- `Web/RosterWeeks/Projection.hs` - read model/projection construction.
- `Web/RosterWeeks/RenderData.hs` - view-facing render data.
- `Web/RosterWeeks/Responses.hs` - HTMX/OOB response helpers.
- `Web/RosterWeeks/FrontendSurface.hs` - FrontendSurface contract/runtime bridge, fragment metadata, live dependencies, and interaction shell helpers.
- `Web/RosterWeeks/Paths.hs` - canonical route/query helpers.
- `Web/RosterWeeks/Dom.hs` - stable DOM ids/selectors.
- `Web/RosterWeeks/Conflicts.hs` - conflict presentation helpers.
- `Web/RosterWeeks/Service.hs` - roster workflow/domain service helpers.
- `Web/View/RosterWeeks/` - HSX rendering.

## Row-Grid Rendering Contract

Editable row-grid shifts are rendered as one interactive shift launcher per
shift. The visual Start/End/Staff/Role cells remain separate child elements and
align via CSS `subgrid`; modal launcher `hx-*`/`data-*` attributes belong on the
shift wrapper, not on each visual cell. Editable create slots follow the same
single-wrapper shape, keep unmerged empty visual cells by default, and show a
centered merged `+` affordance only on hover/focus/highlight.

Read-only row-grid shifts intentionally use separate non-launcher cells and must
not emit edit/create launcher attributes.

## Related Docs

- `SPEC.md` - implemented roster behavior.
- `AGENTS.md` - local editing and verification rules.
- `docs/workstreams/rooks-pilot.md`
- `docs/workstreams/roster-groups.md`
- `docs/archive/plans/20-roster-and-conflicts.md`
- `docs/archive/plans/49-roster-groups-and-venue-bootstrap.md`
- `docs/archive/plans/52-roster-mobile-refactor.md`
