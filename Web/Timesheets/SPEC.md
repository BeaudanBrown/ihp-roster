# Timesheets Specification

Exact fields, routes, markup, and calculation outputs are authoritative in the
schema, `Web/Timesheets/`, registered Surface contracts, and focused/golden
tests. Future payroll behavior belongs in `docs/workstreams/`.

## Terms And Authority

- A **roster shift** is the current roster definition.
- A **suggestion** is a transient server projection of an eligible roster shift;
  it is neither persisted nor a status.
- A **Timesheet entry** is the persisted work record used for review, approval,
  export, and payroll.
- Entries are venue- and staff-scoped. Staff manage their own visible entries;
  managers act only within their authorized venue staff scope. During founder
  impersonation, authority uses the effective user and linked Staff; entry-version
  actors retain the founder plus effective-user/session provenance. Filters never
  grant authority.

## Time Contract

- Entries persist authoritative start/end instants, paired nullable break
  instants, and an `Australia/Melbourne` timezone snapshot. Worked date, clocks,
  break duration, and paid duration are projections from those values.
- Nonexistent spring clocks are rejected. Ambiguous autumn endpoints require the
  relevant first/second occurrence, including equal repeated-clock intervals.
- Input precision and picker range follow venue configuration. Existing values
  outside the current picker range remain valid and displayable.
- Generated TimePicker, Toggle, and Overlay contracts own browser mechanics.
  Haskell owns options, defaults, boolean transport, break-field activation, and
  validation; feature JavaScript must not recreate those rules.

## Roster Suggestions

A suggestion exists only while its roster group/week/slot is active and live,
the shift is complete and explicitly Staff-assigned, linked staff and shift type
are eligible for Timesheets, and no active entry owns that source slot. Open,
trial, roster-only, deleted, incomplete, or already-materialized shifts do not
produce suggestions.

Suggestions are derived on every projection with no background rows or grace
period. Their week/day follows the authoritative projected start date. Staff see
only their own; managers see their normal venue scope. `Show suggestions` is a
URL-scoped presentation filter and defaults on.

## Materialization And History

- Materialization locks and revalidates the source slot, then snapshots staff,
  instants, timezone, shift type, automatic break, and immutable source ID.
  The partial source-slot uniqueness constraint and lock make concurrent retries
  idempotent.
- Staff creation and ordinary Save create unapproved entries. Authorized
  managers may atomically materialize and approve; failed approval rolls back
  the new entry completely.
- Roster edits never mutate an existing Timesheet snapshot. Soft-deleting the
  entry may make the current source eligible for a new snapshot while retaining
  deleted history. Ad-hoc entries remain unrelated to suggestions.
- Staff cannot reassign roster-derived entries. Managers may correct staff in
  scope, but source identity and worked date remain immutable.

## Approval And Payroll

- Approval status, actor, timestamp, staff pay version, and shift-type pay
  version change consistently. Fixtures and migrations must never assert only an
  approval boolean.
- Approval enters the shared strict wage-source boundary and is all-or-nothing.
  Approved/final reads consume sealed immutable ledger facts and never
  recalculate mutable rates.
- Xero and exports consume approved locked facts; no subsystem may introduce a
  parallel payroll calculation path.

## Live Updates

Server-rendered projection HTML remains authoritative. Mutations return actor
fragments and publish typed touched resources for passive viewers. Roster
publication, relevant slot changes, pay-mode changes, and trial adoption touch
the affected Timesheet week resources. Date moves refresh old and new visible
scopes. Week/filter requests use the Surface-declared shell synchronization.

Legacy automatic roster-to-Timesheet jobs remain retired: publication creates no
entry, the compatibility toggle stays false, and historical jobs remain audit
history. The cutover requires legacy workers to stop before migration; exact
preflight and recovery are in
`Application/Migration/roster-timesheet-suggestion-cutover-runbook.md`.

## Verification

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Timesheets"
bash ./bin/in-env e2e e2e/live-fragment-multiview.spec.ts
```
