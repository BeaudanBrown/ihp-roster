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

## Presentation Preferences And Side Panel

- `Show approved`, `Show suggestions`, and (where authorized) `Show wage estimates`
  are global per-user preferences and default on when Timesheets preferences are
  first initialized. They do not enter Bepis-generated Timesheets URLs, fragment
  requests, or mutation envelopes. The viewed week and authorized manager staff
  and roster-group filters are URL state; additional query fields are ignored
  rather than interpreted as compatibility state. Filters never grant authority.
  The roster-group filter is available only when at least two active current-venue
  groups exist; otherwise roster-group URL state canonicalizes to All roster groups.
  Selecting one
  retains only entries linked to a source slot in that group and transient
  suggestions from that group; ad-hoc entries have no group and appear only
  under All roster groups.
- Timesheets uses the shared transient SidePanel and the same main-card header,
  desktop focus/Escape behavior, and phone stacking as Roster and manager
  Unavailability. Managers receive Staff and Settings; ordinary staff receive Settings only. The manager Staff inventory
  contains every active Timesheet-eligible staff member independently of card
  filters. Its counts exclude transient suggestions, ignore the staff card
  filter, and reflect the selected roster group.
- Manager row hover/focus highlights matching persisted and suggestion cards;
  pinning keeps that presentation relationship. Keyboard row activation opens
  the existing staff profile dialog. Highlight and pin state never alter URLs or
  query results.

## Roster Suggestions

A suggestion exists only while its roster group/week/slot is active and live,
the shift is complete and explicitly Staff-assigned, linked staff and shift type
are eligible for Timesheets, and no active entry owns that source slot. Open,
trial, roster-only, deleted, incomplete, or already-materialized shifts do not
produce suggestions.

Suggestions are derived on every projection with no background rows or grace
period. Their week/day follows the authoritative projected start date. Staff see
only their own; managers see their normal venue scope.

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

## Wage Estimates, Approval And Payroll

- Wage estimates are an independent global per-user preference, enabled when
  Timesheets preferences are first initialized. Workers may view their own estimates; venue admins and owners may
  view authorized staff estimates; supervisors and managers do not receive the
  control or amounts.
- The week summary and each day summary aggregate only currently visible cards,
  so staff and roster-group filtering, Show approved, and Show suggestions all
  change the total.
  Approved entries consume sealed immutable ledger facts; unapproved entries
  and transient suggestions use canonical draft evaluation. Failed calculations
  remain unavailable and are excluded from the clearly partial total rather
  than becoming zero. Only platform super admins see draft source warnings.
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
