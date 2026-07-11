# Roster Weeks

## Purpose

`Web/RosterWeeks/` owns the roster-week feature modules that keep
`Web/Controller/RosterWeeks.hs` focused on controller orchestration.

## Entry Points

- `Web/Controller/RosterWeeks.hs` - controller actions.
- `Web/RosterWeeks/DirectReadModel.hs` - canonical direct database/read-model construction for every roster layout and fragment.
- `Web/RosterWeeks/RenderData.hs` - view-facing render data and fragment rendering helpers.
- `Web/RosterWeeks/Responses.hs` - HTMX/OOB response helpers.
- `Web/RosterWeeks/FrontendSurface.hs` - FrontendSurface contract/runtime bridge, fragment metadata, live dependencies, and interaction shell helpers for the week grid and single-day timeline surfaces.
- `Web/RosterWeeks/Paths.hs` - canonical route/query helpers.
- `Web/RosterWeeks/Dom.hs` - stable DOM ids/selectors.
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

## Drag/Drop Interaction Contract

The roster `FrontendSurface` declares distinct source/dropzone refs so the
generic pointer runtime can filter compatible targets without roster-specific
JavaScript:

- `shift-drag-source` can drop onto row-grid `shift-slot-dropzone` targets,
  whole open day-column `day-column-dropzone` targets, and the toolbar
  `delete-shift-dropzone`. The default intent moves; the copy modifier submits
  the duplicate intent, with delete targets still opening delete confirmation.
- `staff-drag-source` can drop onto existing shift cards or explicit
  `staff-create-dropzone` targets only. Existing-shift drops assign/replace
  staff immediately with a toast; create-target drops open the new-shift dialog
  with staff preselected.
- Day-column gaps/whitespace are not staff-create targets. Only the bottom
  `+ Add shift` card is a staff-create target in day-column layout. Shift drags
  do not target that create card in day-column layout.

All rendered keys remain opaque (`existing:<slot-id>`, `staff:<staff-id>`,
`new:<day-id>:<slot-definition-id>:<row-index>`); controllers parse and validate
venue, roster-group, draft/open-day, active staff, and eligibility before any
mutation or dialog render.

## Day Timeline Rendering Contract

The single-day timeline is selected on the normal roster week page via
`rosterView=timeline&dayOffset=<0-6>`. The roster controls and staff side panel
remain mounted; only the main roster frame swaps from week grid to the selected
single-day timeline. The timeline keeps a contained `roster-day-timeline`
FrontendSurface for its drag/drop refs and intent form.

Time is rendered horizontally across the operational day, outer lanes are active
slot definitions, and inner overlap tracks are computed for display only.
Timeline drag/drop uses the same generic source/dropzone runtime as the roster
grid: Haskell renders opaque `existing:<slot-id>` source keys and
`time:<day-id>:<slot-definition-id>:<operational-minute>` target keys, while the
controller owns all parsing, validation, row-index placement, and mutation.

## Related Docs

- `SPEC.md` - implemented roster behavior.
- `AGENTS.md` - local editing and verification rules.
- `docs/workstreams/rooks-pilot.md`
- `docs/workstreams/roster-groups.md`
- `docs/archive/plans/20-roster-and-conflicts.md`
- `docs/archive/plans/49-roster-groups-and-venue-bootstrap.md`
- `docs/archive/plans/52-roster-mobile-refactor.md`
