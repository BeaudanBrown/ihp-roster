# Hospitality Award wage compliance

Status: active

Parent issue: [#227](https://github.com/BeaudanBrown/ihp-roster/issues/227)

Contract matrix:
[`specs/hospitality-award-wage-compliance-matrix.md`](../../specs/hospitality-award-wage-compliance-matrix.md)

## Tickets

- [#228](https://github.com/BeaudanBrown/ihp-roster/issues/228) — compliance matrix and deterministic source fixtures
- [#229](https://github.com/BeaudanBrown/ihp-roster/issues/229) — pure Haskell engine and typed contract
- [#230](https://github.com/BeaudanBrown/ihp-roster/issues/230) — authoritative Melbourne instants and DST
- [#231](https://github.com/BeaudanBrown/ihp-roster/issues/231) — earnings components and final-line rounding
- [#232](https://github.com/BeaudanBrown/ihp-roster/issues/232) — unpaid-meal-break rules and precedence
- [#233](https://github.com/BeaudanBrown/ihp-roster/issues/233) — casual/public-holiday minimum payments
- [#234](https://github.com/BeaudanBrown/ihp-roster/issues/234) — immutable approved-pay ledger
- [#235](https://github.com/BeaudanBrown/ihp-roster/issues/235) — source freshness and Award drift notifications
- [#236](https://github.com/BeaudanBrown/ihp-roster/issues/236) — supported per-shift roster limits
- [#237](https://github.com/BeaudanBrown/ihp-roster/issues/237) — CSV/Xero component publication
- [#238](https://github.com/BeaudanBrown/ihp-roster/issues/238) — property, performance, migration and workflow verification
- [#239](https://github.com/BeaudanBrown/ihp-roster/issues/239) — Haskell cutover and SQL retirement
- [#241](https://github.com/BeaudanBrown/ihp-roster/issues/241) — Staff Hours CSV contract
- [#264](https://github.com/BeaudanBrown/ihp-roster/issues/264) — complete, deterministic and atomic MAPD refresh snapshots
- [#240](https://github.com/BeaudanBrown/ihp-roster/issues/240) — overtime stretch; explicitly on hold

GitHub native blockers and sub-issue state are the implementation tracker; this
file does not duplicate ticket status.

## Intended contract

- Every supported MA000009 wage branch has a stable `HIGA-*` scenario ID,
  exact source, expected paid-time/component result, owner and output evidence.
- Rule arithmetic is pure and uses synthetic rates. Dated FWC MAPD and DataVic
  fixtures exercise ingestion/projection independently of current dollar values.
- One independent timesheet is the base calculation unit. Paid-time segments
  and earnings components are distinct.
- Authoritative elapsed instants determine quantities; Melbourne civil time
  determines Award dates/windows.
- Approved calculations are immutable ledger facts. Drafts calculate from the
  effective rate book.
- Staff Hours reports paid time. Detailed CSV and Xero conserve every positive
  earnings component exactly once.
- Missing/stale authoritative source data fails closed at approval/final output.
  Award document/category drift creates a notification signal, not an automatic
  mandatory-review gate.
- Overtime remains outside the immediate contract until #240 is explicitly
  authorized.

## Integration points

- FWC MAPD ingestion/projection: `Application/FwcMapd/`
- Public-holiday ingestion: `Application/PublicHolidays/`
- Current SQL/helper seam: `Application/Schema.sql`, `Application/Helper/Pay.hs`
- Timesheet approval: `Web/Controller/Timesheets.hs`
- CSV exports: `Application/Helper/Export/`, export controllers
- Xero requirements/preview/submission: `Application/Xero/`
- Roster validation: roster controller/helper boundaries
- Tests: `Test/PaySpec.hs`, source sync specs, fixed export/Xero suites, and the
  target modules named by the compliance matrix

## Living docs to update as tickets land

- `Application/FwcMapd/SPEC.md`
- `specs/06-pay-engine.md`
- `specs/hospitality-award-pay-calculation-verification.md`
- `Web/Timesheets/SPEC.md`
- `Application/Helper/Export/SPEC.md`
- `Application/Xero/SPEC.md`
- nearest roster living spec for #236
- nearest subsystem `AGENTS.md` when a reusable implementation rule emerges

## Exit criteria

- Every immediate matrix row has named executable evidence and no unclassified
  production branch.
- The pure Haskell engine and approved ledger are authoritative.
- SQL calculation functions and SQL-only decoder evidence are retired through
  #239 without rewriting migration history.
- CSV/Xero conservation, source freshness, migrations, property coverage,
  performance structure and critical workflows pass the full verification gate.
- Remaining future behavior is limited to separately authorized work such as
  overtime #240, and durable implemented facts have moved into living docs.
