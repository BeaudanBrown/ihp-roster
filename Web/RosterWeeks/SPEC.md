# Roster Weeks Specification

Exact fields, routes, markup, and mutation details are authoritative in
`Web/RosterWeeks/`, the schema, registered Surface contracts, and focused tests.
This document retains cross-module scheduling and state-transition rules.

## Week And Access Contract

- `anchorDate` in the canonical URL is window-navigation authority.
  `ShowRosterWindowAction { anchorDate }` resolves the configured seven-day
  window containing that date; `RosterWeeksAction` resets from the current
  Operational day. Offset-based roster and Timesheet URLs are unsupported;
  do not add compatibility redirects or persist a last-viewed window.
- Roster data is venue-scoped and may be roster-group-scoped. Missing weeks may
  be materialized only through authorized server behavior; reference browsing
  for templates never materializes a week.
- Managers, venue admins, owners, and unimpersonated founder support receive
  capabilities only through server-side checks. During founder impersonation,
  visibility, controls, self-service, profile gates, and private preferences use
  the effective user's Staff identity and venue role; founder authority does not
  bypass them. Staff cannot edit unpublished weeks and must not see draft detail
  behind the mounted placeholder.
- Publishing is the staff-visibility gate. Returning to draft hides transient
  Timesheet suggestions but never changes an existing Timesheet entry.

## Shift And Time Authority

- Every active roster shift is structurally complete at the database boundary:
  authoritative start/end instants, `Australia/Melbourne` snapshot, shift type,
  valid sparse cell placement, and explicit `staff` or `open` assignment.
  `staff` requires one same-venue staff row; `open` requires none.
- Local date/clock and operational day are projections. A clock before 06:00
  belongs to the following calendar date of its displayed hospitality day.
  Elapsed duration and automatic-break eligibility use instant differences.
- Nonexistent spring clocks are rejected. Ambiguous autumn endpoints require
  explicit occurrence selection. Week/slot copies preserve civil clocks on the
  target date and re-resolve them; timeline moves preserve exact elapsed
  duration from the selected target start instant.
- Staff, shift type, assignment, pay disposition, venue/group scope, and
  authoritative boundaries are revalidated for every save, reassignment, move,
  duplicate, copy, template application, publication, and tampered request.
  Existing invalid shifts remain renderable with a subtle repair indicator and
  standard edit dialog; untrustworthy clocks stay blank. They may only be
  corrected or deleted and cannot be published, copied, projected into payroll,
  or offered as Timesheet suggestions.
- Effective roster-only shifts still require valid boundaries but skip Award
  projected-duration validation. Timesheet-producing shifts use the canonical
  projected-duration/pay boundary.

## Open Shifts And Publication

Complete Open shifts are publishable and visible as `OPEN`, but contribute no
staff counts, conflicts, wage estimates, or Timesheet suggestions. Draft editors
may switch Staff/Open. On a Published roster, only authorized editors may perform one
atomic Open-to-valid-Staff fill; all protected fields remain locked. That fill
touches both Roster and Timesheet resources. Staffed Published shifts and ordinary
staff projections remain read-only.

Publishing never creates Timesheet rows. A complete Published linked-staff shift
becomes a transient Timesheet suggestion; trial staff and Open shifts do not.
Materialized entries are immutable snapshots of their roster source. Later
roster edits expose warnings but never rewrite or delete those entries.

## Roster Notifications

- Only roster editors may deliberately email a Published roster-group window. Draft
  weeks and ordinary staff expose no action. Active runs prevent another send;
  terminal runs may be deliberately repeated without roster-change inference or
  a distinct Resend workflow.
- One immutable run snapshots an explicit `[windowStart, windowEnd)` roster range, eligible recipients, skipped recipients, and actual requester provenance. Legacy week IDs/offsets are optional historical provenance only. Trial, unlinked, inactive, and
  email-less staff are skipped. One durable job per eligible recipient renders
  only that recipient's assigned shifts, all snapshot Open shifts, and the
  authenticated roster link.
- Delivery continues from the snapshot if the roster changes or returns to
  draft. Provider failures retain retry/terminal state and invalidate aggregate
  status without blocking publication or exposing provider details.

Implementation authority is `Application/RosterNotification/` and the focused
controller, mail, and delivery tests.

## Templates

- Week templates are roster-group-scoped detached snapshots with case-insensitively unique trimmed names. Capture reads one exact seven-day date-native roster window, preserves weekday identity, structure, local times, Shift types, and Staff/Open assignments, and never stores publication state.
- Application resolves a submitted ISO anchor to one complete all-Draft window in the same venue and roster group. Saved weekdays map to matching target operational weekdays even when the venue window order rotates. Open/closed state, rows, columns/order, and shifts replace all seven target days; publication remains Draft.
- Preview carries authoritative template, target, calendar, Staff, Shift-type, membership, leave, and pay-reference identity. Confirmation locks and revalidates those facts, the complete target, and relevant Timesheet snapshots before one atomic replacement.
- Approved leave converts only affected target assignments to Open. Durable inactive, archived, wrong-venue, outside-group, or pay-invalid Staff assignments become Open in both target and saved template. Stale Shift types require explicit active same-venue mappings and permanently clean the template; multiple stale identities may share one replacement.
- Replaced shifts are soft-deleted so materialized Timesheet values and source provenance survive. Application resolves repeated Melbourne boundaries to their first occurrence and rejects nonexistent local times.
- Authorized roster editors use one responsive SidePanel Templates tab. It shows a case-insensitive alphabetical Week list with name, shift count, Apply, and Delete only; Save remains in the header and the empty state retains it. Save, Apply, and Delete use generated button forms and shared server-rendered Overlay dialogs. Any Published target day disables Apply with explanatory copy while Save, Delete, and the library remain available. Successful HTMX writes retain the viewed date, group, layout, and selected Templates tab, refresh authoritative fragments in place, and show a toast. Validation and stale confirmation failures rerender the dialog with still-valid inputs preserved.
- The template library fragment/resource identity is shared by roster group, never effective user. Capture, Delete, durable Staff/Shift-type cleanup, and Apply publish typed transactional invalidation so actor, passive, and replayed authorized editor mounts converge. Apply also publishes only the exact affected Roster and Timesheet window resources. Other roster groups do not match the event, and every fragment refetch repeats full Roster editor authorization.

Implementation authority is `TemplateCapture.hs`, `TemplateApplication.hs`, their persistence modules, and focused database/controller tests.

## Staff And Venue Effects

- Venue Admins and Owners may immediately change the **Roster window start day**.
  The mutation serializes on calendar/publication authority, rejects stale
  revisions, advances the calendar revision, and returns only mixed regrouped
  Published windows to Draft. Fully Published regrouped windows remain Published;
  changing back never restores publication. The transition does not rewrite
  shifts, lanes, timestamps, templates, approved payroll calculations, exports,
  or notification snapshots.
- Trial staff are active venue-scoped staff without a user. Adoption links the
  existing row, preserving roster identity; acceptance invalidates affected
  roster and Timesheet scopes.
- Removing an active non-owner staff member requires authorized confirmation and
  cannot remove self or an owner. It archives venue-local staff/membership,
  revokes pending venue links, denies pending unavailability with provenance,
  and soft-deletes current/future roster assignments across groups. Past shifts,
  Timesheets, sealed payroll, other venues, and global passkeys remain intact.
- Staff profile, role, roster-group, and pay-mode changes invalidate every active
  roster/Timesheet scope whose authoritative projection can change.
- Approved leave/unavailability makes affected staff unavailable to roster
  assignment and conflict projections for each covered date. Pending or denied
  requests do not; the leave subsystem's exclusive `end_date` remains the range
  boundary.

## Presentation And Interaction

Registered `RosterSurface` contracts own fragments, resources, roles, action
fields, drag/drop compatibility, overlays, tabs, sorting, SidePanel visibility,
column editing, image export, week overview, and typed request context. Haskell owns
payloads, exact copy/business decisions, and opaque correlation keys. Generic
TypeScript owns only mechanics. Raw IDs, classes, or feature-specific browser
parsers must not become parallel authority.

The row-grid, day-column, and direct timeline URL are projections over the same
direct read model. Timeline lane/overlap geometry is display-only and never
redefines persisted `row_index`. Roster wage estimates use the same canonical
unsealed boundary as a Timesheet suggestion; roster-only shifts contribute
neither totals nor errors. Wage visibility and staff filtering remain
server-authorized and transient.

Managers receive Staff, Templates, and Settings in the shared transient SidePanel.
Feature content and authorization remain roster-owned. Its toggle uses
the shared main-card header location, desktop focus/Escape contract, transient
visibility, and phone stacking used by Timesheets and manager Unavailability. Published rosters
may highlight the effective viewer's own assigned shifts from a global user
preference. A manager's transient hover or pinned staff highlight takes
precedence; draft rosters never apply the own-shift default. Highlight and panel
visibility do not alter URLs or business projections.

## Live Updates

- Server-rendered fragment HTML is authoritative. Actor writes return HTMX/OOB
  responses; passive viewers receive typed resource invalidations and refetch
  under the same authorization as full pages.
- The shell stays subscribed while empty or hidden. Ordinary updates prefer the
  narrowest authoritative child fragments so stable grid/scroll ownership
  survives; structural resources may replace the owning frame.
- Roster publication, draft, slot, and relevant pay changes also touch affected
  Timesheet week resources.
- Fragment containment suppresses overlapping descendants only when their
  parameter values match. Viewer fragment GETs return plain target fragments,
  not actor-style OOB wrappers.

## Extension Rules

Do not add feature-specific JavaScript for shared Surface behavior or infer
business state from DOM presentation. Preserve stable IDs from `Dom.hs`. For
broad fanout, intersect possible historical scopes with active subscriptions
before querying.

## Verification

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "RosterWeeks"
bash ./bin/in-env e2e e2e/roster-live-fragments.spec.ts e2e/roster-mobile.spec.ts
```
