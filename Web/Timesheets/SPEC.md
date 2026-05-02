# Timesheets Specification

This file describes implemented timesheet behavior. Future roster automation,
pay locking, and Xero submission work belongs in `docs/workstreams/` until it
lands.

## Current Contract

- Timesheet entries are venue-scoped and staff-scoped.
- Time inputs must be exact 15-minute increments.
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
- Actor-local mutations should return the smallest practical updated fragment.
- Date moves must refresh both old and new day/week fragments when both can be
  mounted.

## Extension Rules

- Roster-to-timesheet automation is not a normal form shortcut. Treat it as an
  async/job-backed feature with idempotency, auditability, and explicit venue
  opt-in.
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
