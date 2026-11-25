# Leave And Availability Specification

## Domain Contract

- Records are venue- and staff-scoped. Backing status is `pending`, `approved`,
  or `denied`; lifecycle transitions append event/audit provenance rather than
  erasing reviewed history. Staff may soft-delete their own current or upcoming
  requests at any status from Profile. Managers may also soft-delete current or
  upcoming requests for staff in their venue from Staff Edit or Unavailability.
  Deleting an approved request removes its availability block, not assigned shifts.
- `end_date` is exclusive. A one-day unavailable period is `[day, day + 1)`.
  A request is past once its exclusive end date is on or before the venue-local
  calendar day. Profile and Staff Edit show no past requests. The manager
  Unavailability page alone shows them in its read-only Archive.
- Staff-facing copy uses **Unavailability**, **Unavailable period**, and **Add
  unavailable time** while the backing schema retains leave terminology.
- Staff self-service, manager review, and support behavior remain server-authorized.
  During founder impersonation, authority uses the effective user and linked Staff;
  event actors retain the founder plus effective-user/session provenance. Profile
  and roster use the same self-service form/action/validation contract; Profile
  additionally mounts history.
- Approved-state changes are the roster-availability boundary. Pending creation
  does not fan out to roster viewers. Staff removal denies pending requests
  through the normal provenance path and retains approved/denied history.
- Manager request sections use shared expanding header tabs: Pending, Approved,
  Denied, Archive. Inactive tabs show icon and live count; the active tab also
  shows its label. Pending is the normal initial selection, even when empty;
  archive links open Archive. Selection stays local to page interactions and is
  retained through fragment refreshes, without storage or tab-selection URLs.
  The two server-declared fixed-default tab-set variants honour normal/archive
  entry points through the existing generic runtime; only one is rendered per page.
  Availability warnings stay outside the panes, and Archive retains pagination.
- The manager page uses the shared transient Staff/Settings SidePanel with the
  same main-card header, desktop focus/Escape behavior, and responsive tools shelf as
  Roster and Timesheets. Its Staff
  inventory remains complete regardless of main-list filters; hover/focus and
  pinning only highlight matching server-rendered requests and never alter query
  authority. Ordinary staff continue through the shared self-service Surface.

## Venue Policies

- Admins, owners, and founder support may manage venue-wide blackout periods;
  managers may only view them. Blackout dates are inclusive, venue-local,
  non-overlapping, and at most 366 days. Their normalized reason is visible to
  staff. Blackout validation replaces only the submitted form, retaining its
  surrounding open editor and other unfinished forms. A successful save returns
  the saved period to its collapsed summary.
- A blackout intersection or a newly exceeded daily maximum blocks the whole
  draft. Staff receive affected dates but no other staff identities. Managers
  and above can go back to edit or confirm one exception for any scoped target,
  including themselves. This never changes the blackout. Existing requests remain
  valid when a later blackout is added.
- The optional maximum per day (1–100) is independent of warnings; when both
  are set, warning cannot exceed maximum. Count distinct eligible people per
  venue-local date from today, not forms. A person already counted on a date
  consumes no additional place. Approval of a denied request can require a
  capacity exception, but never a blackout exception.
- Confirmations bind actor, venue, target, operation, draft and conflicts.
  Reauthorize and recompute under the venue policy lock; new or worse conflicts
  require another confirmation. One accepted confirmation commits one audited
  submission or review; preview, Back to edit and replay add no requests.
- The optional unavailable-staff warning threshold is 1–100; `NULL` disables it.
  Warnings count distinct active, unarchived staff with pending or approved
  requests per calendar date, never block submission, and are manager-visible
  only when the threshold is met. Warnings cover today onward in the venue's
  timezone; past dates are excluded before counting and grouping, including
  the past portion of requests spanning today. Request history is preserved.

Exact normalization, overlap, grouping, and projection behavior is authoritative
in `Blackouts.hs`, `AvailabilityWarnings.hs`, the schema, and focused tests.

## Live And Privacy Rules

- Server-rendered fragments remain authoritative. Typed blackout, warning, and
  staff-request resources invalidate only dependent fragments. SidePanel tab and
  valid pin state reconcile across authoritative fragment replacement.
- The self-service form is resync-only for passive updates so remote changes do
  not erase focused input; validation failures may replace the local form.
- Do not add medical details or sensitive free-text reasons without dedicated
  product/compliance review.

## Verification

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "LeaveRequests"
bash ./bin/in-env e2e e2e/live-fragment-multiview.spec.ts
```
