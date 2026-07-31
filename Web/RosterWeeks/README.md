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

## Linked-Highlight Contract

The roster Surface declares generated staff-highlight source/member/pin roles
and an ordered-member state. Staff-panel rows are sources, locate controls are
optional pin controls, and assigned row-grid cells or day-column cards are
members. Membership keys (`staff:<staff-id>`) and order keys
(`existing:<slot-id>`) are opaque browser correlation values. The generic
linked-highlight runtime owns hover, focus, keyboard/pin activation,
`aria-pressed`, ordered bounds, mount isolation, and transient
`is-linked-highlight-*` effect classes.

Editable roster shift launchers also carry generated shift-group source/member
roles so their existing hover/focus appearance uses the same generic runtime.
The contained day-timeline Surface declares its own shift-group roles; it does
not reach through its mount boundary to reuse outer-roster elements. Views and
tests consume generated role names rather than raw staff/slot ID attributes or
feature-specific highlight selectors.

## Staff-Panel Sort And Tab Contract

`Surface.Roster` declares the staff panel's complete-set sort and tab-set
capabilities. `Surface.Roster.StaffPanel` is the curated Haskell rendering API:
it emits generated root/control/tab roles and one exact JSON row payload with an
opaque staff-row key, name, role, assigned-shift count, and ideal-shift count.
The view does not expose parallel per-field `data-roster-staff-*` attributes.

The generic complete-set sort runtime owns mount-local name/role/shifts ordering,
ascending/descending toggles, deterministic opaque tie-breaking, and
`aria-sort`. The generic tab-set runtime remembers a valid Staff/Settings key
across panel replacement while Bootstrap owns tab activation. Both discover only
generated roles, validate generated registries/payload parsers, and leave
server-rendered markup authoritative. Roster-specific browser parsers,
comparators, defaults, and compatibility aliases are prohibited.

## Fullscreen And Column-Edit Contract

`Surface.Roster` declares generated fullscreen root/toggle/label roles, column
editor/start/done roles, and closed fullscreen/column-editing states.
`Surface.Roster.Chrome` is the marker-indexed Haskell rendering boundary. The
fullscreen adapter changes only the nearest root, synchronizes replacement
toggles, retains native `aria-pressed`, and owns icon/focus/Escape mechanics.
The column-edit adapter changes only the nearest editor, preserves delayed blur
for autosave, reconciles replaced day-rail controls, and cancels pending timers
when HTMX removes an editor. Raw `data-roster-fullscreen*` and
`data-roster-column-*` contracts and presentation-class discovery are
prohibited.

## Image Export Contract

Live manager row-grid rosters expose a generated JPG trigger with a
Haskell-resolved filename and exact format/copy policy. Day-column and timeline
layouts omit the trigger because they do not render the row-grid export
projection. The projection, rows, and every visual cell carry generated Surface
roles; each cell carries exact Haskell-rendered export text. The browser adapter
may measure that projection, read computed styles, render SVG/Canvas, encode JPG,
and download it, but it must not infer cell meaning from classes/positions or
read conflict metadata.

## Dormant Week Overview Contract

The retained month/week overview endpoint renders generated panel/day/detail-slot
roles and exact Haskell-built day payloads. Availability, closure, and calendar
status use generated closed state, while selection uses `aria-pressed`.
Malformed day payloads are diagnosed and skipped without replacing server HTML.
The active roster header intentionally renders only the static week label, so
this capability remains disabled and is not fetched during normal navigation.

## Week Toolbar Contract

`Application.Helper.View.WeekToolbar` renders each supplied control exactly
once. Its wrappers are layout slots only; `static/css/components/week-toolbar.css`
repositions the same primary, reset, navigation, auxiliary, and settings nodes
at responsive breakpoints. In particular, the roster live switch has one form,
one input id, and one generated form-local transport on every viewport.

## Drag/Drop Interaction Contract

The roster `FrontendSurface` declares distinct source/dropzone refs so the
generic pointer runtime can filter compatible targets without roster-specific
JavaScript:

- `shift-drag-source` can drop onto row-grid `shift-slot-dropzone` targets,
  whole open day-column `day-column-dropzone` targets, and the toolbar
  `delete-shift-dropzone`. The default intent moves; the copy modifier submits
  the duplicate intent, with delete targets still opening delete confirmation.
- `staff-drag-source` can drop onto existing shift cards, shared row-grid
  `shift-slot-dropzone` targets, or explicit day-column
  `staff-create-dropzone` targets. Existing-shift drops assign/replace staff
  immediately with a toast; valid create-target drops open the new-shift dialog
  with staff preselected. Pay-invalid assignments and create drops leave the
  roster unchanged and return an error toast.
- Day-column gaps/whitespace are not staff-create targets. Only the bottom
  `+ Add shift` card is a staff-create target in day-column layout. Shift drags
  do not target that create card in day-column layout.

Every compatible shift-modifying target receives the same disposable green
highlight with a strong border and shaded interior. Row-grid create targets own
the dropzone on their complete shift wrapper, so staff and shift drags highlight
the full Start/End/Staff/Role span rather than a nested visual cell.

All rendered keys remain opaque (`existing:<slot-id>`, `staff:<staff-id>`,
`new:<day-id>:<slot-definition-id>:<row-index>`); controllers parse and validate
venue, roster-group, draft/open-day, active staff, and eligibility before any
mutation or dialog render. Every slot persistence boundary also resolves the
selected staff and shift type through `Web.RosterWeeks.Service`; malformed,
unavailable, archived, or venue-invalid pay configuration is rejected even when
a request bypasses rendered selector options. Effective roster-only shifts skip
Award duration checks but still require authoritative boundaries.

## Shift Time Picker Contract

Roster shift dialogs use the shared generated TimePicker capability. Haskell
supplies the venue range, quarter-hour step, empty-state/accessibility copy, and
canonical value/label option payloads. Roster views do not own picker selectors
or browser fallback data; the generic adapter owns only mechanical modal,
selection, clear, and step behavior.

HTMX shift dialogs opt into the generated Overlay keyboard mode. Initial focus
is Start while Tab follows cyclic visual form order and excludes dialog chrome.
The generic picker treats each time as one tab stop, steps and wraps valid
quarter-hour options with either arrow-key pair, and accepts buffered whole-hour
24-hour input only when that exact option is in the Haskell-rendered range.
Enter saves outside multiline fields and the open picker; Escape cancels the
picker first and then the workflow dialog. Full-page fallback dialogs do not opt
into this mode.

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
