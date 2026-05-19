---
id: ir-omzt
status: closed
deps: []
links: []
created: 2026-05-08T04:22:29Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9u78
tags: [area:xero, area:payroll, api]
---
# Add Xero Pay Runs API and selectable payroll periods

Add first-class Xero Payroll AU Pay Runs support and use it to build selectable pay-period options for draft-timesheet preparation.

## Design

Extend `Application.Helper.Xero` with `XeroPayRunRef`, response parsing, request builders, `fetchPayRuns`, pagination, and strict contract/mock coverage. Persist/surface synced Xero pay runs enough for the admin read model to build selectable period options.

Period options are derived from synced payroll calendars plus fetched pay runs. Each option must carry the Xero payroll calendar id/name, pay-period start/end, payment date when known, pay-run id/status when known, whether the option came from Xero pay-run data or derived calendar cadence, and whether a POSTED pay run blocks submission. The option key must be stable and include calendar id plus period start/end so later steps can reject tampering.

Do not introduce local staff-to-calendar assignment. Employee calendar membership comes from synced Xero employee reference data in later tickets.

## Acceptance Criteria

Pay runs can be fetched through the Xero client boundary and persisted/read for the current venue. Period options include all calendar/period/pay-run fields required by preparation and clearly label weekly/fortnightly/etc from Xero calendar data. POSTED periods are marked blocked at option-build time. Existing contract tests cover request shape and response decoding, including date wrappers and pagination.


## Notes

**2026-05-19T05:22:26Z**

Verified Xero Pay Runs API/client contract, persistence/read-model period options, posted-run blocking, and focused Xero Hspec coverage; acceptance criteria are satisfied.
