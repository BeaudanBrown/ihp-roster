# Roster Weeks Specification

This file describes implemented roster-week behavior. Future roster-group,
pilot, or payroll prediction work belongs in `docs/workstreams/` until it
lands.

## Current Contract

- `weekOffset` in the URL is the source of truth for the viewed week.
- `RosterWeeksAction` resets to the current week.
- `ShowRosterWeekAction { weekOffset }` is the canonical explicit week route.
- HTMX week navigation swaps the stable roster shell and pushes canonical URLs.
- Missing weeks may be materialized when an authenticated venue member visits
  them; staff see hidden/unpublished draft shells when appropriate.
- Staff users cannot edit unpublished roster weeks.
- Managers, venue admins, venue owners, and support-mode super admins can use
  manager/admin roster controls according to the controller capability checks.
- Admin-and-up users may enable compact roster wage totals in roster chrome:
  the week total in the right-side toolbar area and per-day totals in day labels
  or day-column headers. Managers and staff do not receive wage controls or
  markup. The wage toggle is independent of the venue-wide roster end-time
  display setting because shift end times are always collected.
- Publishing a roster is the visibility gate for staff-facing roster content.
- Staff-facing draft roster pages keep the week shell and day column mounted for
  live updates, but hide slot rows, closed-day state, and other draft roster
  details behind a non-live placeholder.
- Full pages, standard rows, day columns, month overview, timeline URLs, and
  roster fragment endpoints all use the canonical direct SQL read model. There
  is no fallback projection query or alternate conflict evaluator.
- Trial staff placeholders are active venue-scoped `staff` rows with no linked
  `user_id`. They are rosterable when active and not archived, can be assigned
  to selected roster groups, and appear beside linked staff in roster assignment
  options and the manager staff panel. Managers can send a worker-only adoption
  invitation for a trial staff row; accepting the invitation links the existing
  `staff` row to the new `user` rather than creating a replacement staff row, so
  existing roster slots remain attached to the same staff identity.
- The roster staff panel uses the existing role column for trial placeholders and
  renders their role as `TRIAL`; linked staff continue to show their venue
  membership role labels.
- Publishing requires every staffed shift to have a start time, valid end time,
  and shift type. Shift end times are always collected; the venue setting only
  controls whether end times are rendered in the roster grid/cards.
- Publishing an auto-timesheet-enabled roster queues `roster_timesheet_creation`
  app jobs for complete linked-staff slots using the slot state and calculated
  run time at the moment of publishing. Complete trial-staff slots are valid for
  roster publishing but are roster-only and do not queue timesheet creation jobs.
- Moving a live roster week back to draft cancels that week's not-started and
  retry `roster_timesheet_creation` jobs by marking them succeeded with result
  `{status: "cancelled", reason: "roster_week_moved_to_draft"}`. Running jobs
  are not force-cancelled; they rely on their execution-time live-week checks and
  may remain active until the worker finishes them.
- Republishing after draft edits creates fresh roster-timesheet jobs from the
  current complete slot state and recalculated run times after older active jobs
  for those slots have been cancelled or finished.
- Roster forms must submit full cell payloads so single-field edits do not
  clear sibling slot fields.
- Roster conflict warning highlights are manager-controlled display chrome. They
  default off, can be enabled by managers from roster settings, and only affect
  visual highlighting; conflict messages remain rendered on the affected staff
  cells.

## Scheduling Data

- Roster weeks are venue-scoped and may be roster-group-scoped as the group
  model lands.
- Roster days group slots by day offset.
- Roster days store their visible open-day row count independently of slots.
- Roster slots are sparse positioned data records. Blank editable cells are
  rendered from the day row count and active slot definitions; active blank
  slots should not be stored.
- Slot rows use `row_index` to align early/mid/late-style visual rows in the
  default table layout.
- Day-column layout renders actual slots compactly in column-major order,
  sorted top-to-bottom by start time within each day, and ignores holes in the
  default table layout.
- Day-column draft/editable and live/read-only cards use the same compact shift
  type badge shape. Editable badges remain select controls; read-only badges do
  not present interactive affordance.
- In editable day-column layout, each open day column is the drag/drop target.
  Hovering a compatible dragged shift highlights the whole day column using the
  add-shift success visual style; the `+ Add shift` card remains a create-dialog
  launcher but is not the drop target owner.
- Dropping a shift onto an open day-column target moves the shift to that day.
  The server chooses the first available backing slot cell, grows the day row
  count when all existing cells are occupied, and the compact day-column render
  then sorts visible cards by the normal day-column order.
- Dropping a shift onto its own day-column target is a silent no-op. Holding the
  platform-native copy modifier duplicates instead: Ctrl on Windows/Linux and
  Option/Alt on macOS. Copying onto the same day is allowed and creates a new
  copied shift in the first available/grown backing cell.
- In editable draft rosters, manager staff-panel rows are draggable staff
  sources. Dropping staff onto an existing editable shift immediately replaces
  that shift's assigned staff after server-side venue, roster-group, draft/open
  day, active-staff, and eligibility validation, then refreshes roster fragments
  and shows a toast. Dropping staff onto an empty row-grid create cell or the
  day-column bottom `+ Add shift` card opens the new-shift dialog with that staff
  member preselected; required time and shift-type fields still need user input.
  Day-column whitespace/gaps are not staff-create targets, even though the whole
  day column remains a shift-move target for dragging existing shifts. Shift
  drags in day-row layout target row-grid `shift-slot-dropzone` slots; shift
  drags in day-column layout target the whole day column, not the green `+`
  create card. Empty day-row create wrappers are one shared full-span drop target
  for both shift and staff drags. Empty row targets, whole day-column targets,
  and existing-shift staff targets use the same disposable green affordance with
  a strong border and shaded interior. Dropping a shift on the roster toolbar
  opens the existing delete confirmation dialog instead of deleting immediately.
- The single-day timeline remains a URL-scoped view mode of the normal roster
  week page (`rosterView=timeline&dayOffset=<0-6>`), but visible roster entry
  links are hidden for the release candidate. When accessed directly, the roster
  controls and staff side panel remain visible while only the main roster frame
  swaps. It uses the venue-configured valid shift window for its horizontal time
  axis and editable 15-minute dropzones, with outer lanes based on active
  `roster_week_slot_definitions` sorted by roster-week order. Existing shifts
  outside the current window remain renderable and are clamped into the visible
  timeline track rather than being deleted or rejected solely because of the
  window.
- Timeline overlap tracks are display-only. They are computed from rendered shift
  intervals within a slot-definition lane and do not persist or redefine
  `row_index`.
- Editable draft timelines render 15-minute server-owned dropzones per
  slot-definition lane within the venue picker window. Dragging an existing staffed shift to a timeline target
  preserves its duration, changes start/end times, and changes
  `roster_week_slot_definition_id` when dropped in another lane.
- Timeline drag persistence preserves the source `row_index` when the target
  slot-definition cell is free, otherwise it uses the first free row. Invalid
  targets, live weeks, closed days, unstaffed shifts, and shifts without complete
  start/end times are rejected server-side.
- New roster shift dialogs default to the venue picker start time and an
  8-hour end time clamped to the configured picker end when the window is
  shorter than 8 hours. Existing saved shift times outside the picker window
  remain valid/displayed; picker +/- buttons stay unavailable until the field is
  changed to an in-window option.
- Timeline resize handles, creating shifts, deleting shifts, configurable
  slot-definition titles, staff reassignment, and live-roster editing are not
  part of the implemented timeline contract.
- Shift type badges show the assigned shift type name. Shift types with a
  palette colour key render a small persisted colour marker; blank colour keys
  render without a colour highlight. Unassigned shifts show `Role`; staffed
  shifts without a shift type show `Role required` with warning/dashed styling.
- Slot names and shift types are venue configuration, not free-form authority.
- Shift type colour keys are optional reusable labels. Blank (`''`) means no
  roster colour highlight; palette keys (`palette-1` through `palette-10`) opt a
  shift type into highlighting. Multiple shift types may share the same palette
  key.
- Admin shift type configuration exposes the optional colour directly. New shift
  types default to blank, so using colours is an opt-in highlighting workflow.

## Standard Grid Rules

- Standard day-row layout preserves clear day boundaries across the whole grid:
  each day section ends with a strong separator, and the first row of each next
  day gets a strong top border across all slot cells.
- Standard day-row shift type cells retain the existing cell format; shift type
  colour may be used only as a subtle internal accent and must not override
  conflict or issue highlighting.

## Conflict And Availability Rules

- Late-to-early conflict uses start-to-start gap.
- The threshold is venue-level configuration.
- Staff shift preferences are recurring weekday availability windows; the current schema enforces one active row per staff member and weekday, and conflict evaluation treats multiple supplied same-day windows as matching when any window contains the rostered start time.
- Leave/unavailability conflicts affect roster availability according to the
  approved-state rules in the leave subsystem.

## Live Updates

- The roster shell stays subscribed even when a week is empty or hidden so
  create/copy/publish transitions can update passive viewers.
- Actor browser responses return HTMX fragments or OOB swaps.
- Passive viewers receive websocket invalidations containing semantic fragment keys; each browser resolves them through its local roster mount descriptors.
- Fragment GET routes must enforce the same venue/visibility rules as the full
  page.
- Roster live fragments refresh immediately; discrete autosaved controls should
  commit on change instead of relying on blur-deferred protection.
- `#roster-content` owns only the main roster column, header, and grid. It does
  not render `#roster-staff-panel-fragment`.
- `#roster-staff-panel-fragment` is a sibling side-panel fragment. Broad roster
  week refreshes may request content and staff panel together because their
  containment paths are siblings.
- The manager staff panel is eagerly rendered in the full roster shell for the
  release candidate. Its fragment endpoint remains the same permission-checked
  source of truth for live/actor refreshes and must keep returning the root node
  with id `roster-staff-panel-fragment`.
- Day and row fragments remain descendants of `#roster-content`; when a parent
  content refresh is selected, actor/passive planning drops overlapping day or
  row refs.

## Extension Rules

- Do not store last-viewed week in the database without a new product decision.
- Do not add feature-specific JavaScript for generic live-surface behavior.
- If a mutation fans out across many possible weeks, intersect with active live
  subscriptions before querying cold historical scopes.
- Preserve stable DOM ids from `Web/RosterWeeks/Dom.hs` when changing views or
  responses.

## Verification

Use focused checks for roster work:

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "RosterWeeks"
bash ./bin/in-env e2e e2e/roster-live-fragments.spec.ts
bash ./bin/in-env e2e e2e/roster-mobile.spec.ts
```
