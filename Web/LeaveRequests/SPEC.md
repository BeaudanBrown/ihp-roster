# Leave And Availability Specification

## Domain Contract

- Records are venue- and staff-scoped. Backing status is `pending`, `approved`,
  or `denied`; lifecycle transitions append event/audit provenance rather than
  silently deleting reviewed history.
- `end_date` is exclusive. A one-day unavailable period is `[day, day + 1)`.
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
- The manager page uses the shared transient Staff/Settings SidePanel with the
  same main-card header, desktop focus/Escape behavior, and phone stacking as
  Roster and Timesheets. Its Staff
  inventory remains complete regardless of main-list filters; hover/focus and
  pinning only highlight matching server-rendered requests and never alter query
  authority. Ordinary staff continue through the shared self-service Surface.

## Venue Policies

- Admins, owners, and founder support may manage venue-wide blackout periods;
  managers may only view them. Blackout dates are inclusive, venue-local,
  non-overlapping, and at most 366 days. Their normalized reason is visible to
  staff.
- Any new unavailable range overlapping a blackout is rejected in full, with no
  role override. Existing requests remain valid when a later blackout is added.
- The optional unavailable-staff warning threshold is 1–100; `NULL` disables it.
  Warnings count distinct active, unarchived staff with pending or approved
  requests per calendar date, never block submission, and are manager-visible
  only when the threshold is met.

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
