# Roster Weeks Specification

Exact fields, routes, markup, and mutation details are authoritative in
`Web/RosterWeeks/`, the schema, registered Surface contracts, and focused tests.
This document retains cross-module scheduling and state-transition rules.

## Week And Access Contract

- `weekOffset` in the URL is viewed-week authority.
  `ShowRosterWeekAction { weekOffset }` is explicit navigation and
  `RosterWeeksAction` resets to this week. Do not persist a last-viewed week.
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
  Existing invalid shifts may only be corrected or deleted.
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
- One immutable run snapshots roster content, eligible recipients, skipped
  recipients, and actual requester provenance. Trial, unlinked, inactive, and
  email-less staff are skipped. One durable job per eligible recipient renders
  only that recipient's assigned shifts, all snapshot Open shifts, and the
  authenticated roster link.
- Delivery continues from the snapshot if the roster changes or returns to
  draft. Provider failures retain retry/terminal state and invalidate aggregate
  status without blocking publication or exposing provider details.

Implementation authority is `Application/RosterNotification/` and the focused
controller, mail, and delivery tests.

## Templates

- Day/Week templates are roster-group-scoped immutable versions with
  case-insensitively unique trimmed names. One private recoverable draft exists
  per effective user; optimistic conflicts offer reload-latest or save-as-new.
- Reference creation reads only confirmed Published/Draft source content. Proof is
  session-bound to source and occupied-draft revisions; stale or replayed proof
  fails before mutation. Source roster rows are never changed.
- Saved templates contain complete shifts explicitly assigned Staff/Open.
  Unavailable or pay-invalid staff become Open with warnings in a new version;
  stale shift types fail atomically.
- Application targets an explicit Draft window in the same group. Day replaces
  one day while preserving unrelated days; Week replaces all seven days and
  column order. Preview carries authoritative revisions, resolved boundaries,
  destructive scope, assignment cleanup, Timesheet warnings, and touched
  resources.
- Confirmation locks and revalidates template, target, relevant Timesheet,
  Shift-type, Staff, and membership state, then applies atomically. Replaced
  shifts are soft-deleted so Timesheet provenance survives. Melbourne DST rules
  apply to target clocks.

Implementation authority is `TemplateDesigner.hs`, `TemplateApplication.hs`,
and their tests; browser drag, keyboard, and touch paths converge on the same
server confirmation.

## Staff And Venue Effects

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

Managers receive Staff and Settings in the shared transient SidePanel; Template
functionality remains implemented but is intentionally hidden for the next release.
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
