# Timesheets Specification

This file describes implemented timesheet behavior. Future roster automation,
pay locking, and Xero submission work belongs in `docs/workstreams/` until it
lands.

## Current Contract

- Timesheet entries are venue-scoped and staff-scoped.
- Trial staff placeholders (`staff.user_id IS NULL`) are roster-only in V1. They
  are excluded from manual timesheet staff selectors and manager staff filters,
  and tampered create/update requests that target trial staff are rejected.
- Time inputs must be exact 15-minute increments.
- Timesheet start/end/break pickers use the venue-configured time-picker window.
  New manual entries default to the venue picker start time and an 8-hour end
  time clamped to the configured picker end when the window is shorter than 8
  hours. Existing saved times outside the picker window remain valid/displayed;
  picker +/- buttons stay unavailable until the field is changed to an
  in-window option.
- Leave `end_date` style conventions do not apply to timesheet worked dates;
  each entry has a concrete worked date and start/end/break data.
- Managers/admins can review and approve according to controller role checks.
- Staff edit behavior is constrained by approval state and controller rules.
- Approved entries carry approval provenance and pay-version locking fields as
  required by the current schema.
- Staff comments and manager/internal notes are part of the pilot UX direction;
  keep the living contract here updated as those fields settle.

## Approval And History

- Approval writes must keep approval status, actor, timestamp, and pay context
  consistent.
- Do not seed approved entries by setting only `isApproved`; tests and fixtures
  must set the associated required fields together.
- Payroll-adjacent changes should preserve provenance through version/event
  helpers rather than silent destructive overwrite.

## Live Updates

- Timesheet week pages use declarative live surfaces when open pages can become
  stale from another actor, another tab, or an async job.
- The Timesheets mount is built from exact marker-indexed scope, mount-state, and
  fragment values. Required scope fields have no runtime fallback, and action
  metadata is not discovered through protocol-name scans.
- Week navigation and filter actions serialize through the closest
  `#timesheet-week-shell` with the typed HTMX `replace` sync strategy.
- Actor-local mutations should return the smallest practical updated fragment.
- Date moves must refresh both old and new day/week fragments when both can be
  mounted.

## Roster Automation

- Roster-to-timesheet automation is venue opt-in and job-backed through
  `roster_timesheet_creation`; it is not a generic app-job cancellation feature
  or a normal form shortcut.
- Trial-staff roster slots are ignored by roster-to-timesheet automation. They
  do not create jobs when publishing and are skipped quietly if a stale queued
  job later sees a slot reassigned to trial staff.
- A live-to-draft roster rollback cancels only not-started and retry
  roster-timesheet creation jobs for slots in that week, recording result
  `{status: "cancelled", reason: "roster_week_moved_to_draft"}`.
- Running roster-timesheet jobs are not force-cancelled during rollback. They
  must re-check venue opt-in, live roster-week state, slot deletion, slot
  completeness, and existing generated timesheets when they execute, and they may
  remain active until the worker finishes them.
- Republishing a draft-edited roster week queues new jobs from the current
  complete roster slot state with recalculated run times after older active jobs
  for those slots have been cancelled or finished.
- Generated timesheet entries are authoritative timesheet records. Later roster
  draft rollbacks, edits, or republishing do not mutate or delete them; users
  must edit the timesheet entry directly when corrections are needed.

## Extension Rules

- Xero submission must use approved, locked timesheet facts; do not introduce a
  parallel payroll calculation path.
- Keep detailed payroll correctness in Hspec/golden tests, not only browser
  tests.

## Verification

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Timesheets"
bash ./bin/in-env e2e e2e/live-fragment-multiview.spec.ts
```
