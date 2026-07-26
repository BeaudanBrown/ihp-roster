# Pay Engine Specification

## Architecture decision

`Application.WageEngine` is the sole production wage calculator. It is pure,
provider-neutral, and consumes authoritative Melbourne-time segments plus a validated
effective rate book. Its complete contract is documented in
[`Application/WageEngine/SPEC.md`](../Application/WageEngine/SPEC.md) and the executable
MA000009 envelope is defined by
[`hospitality-award-wage-compliance-matrix.md`](hospitality-award-wage-compliance-matrix.md).

PostgreSQL does not calculate wages. The former `calculate_timesheet_pay` and
`calculate_timesheet_pay_range` functions were retired by cutover #239. Historical
migration files remain unchanged as deployment history.

## Draft and final authority

- Draft/unapproved entries are calculated by the Haskell engine from current effective,
  validated source facts. Source-policy diagnostics warn on draft previews.
- Approval calculates through the same engine and atomically persists exact paid-time
  segments and earnings components in the immutable approved-pay ledger.
- Approved/final exports and Xero workflows read only sealed ledger facts. They do not
  recalculate from mutable rates, holidays, or venue configuration.
- Final publication groups exact components into provider-neutral buckets, rounds output
  quantities/amounts once at the documented boundary, and never mutates ledger facts.
- Imported Xero pay-item overrides remain explicit external flat-rate calculations and
  bypass Award arithmetic/source freshness only after the imported item resolves.

## Effective facts and reproducibility

Raw FWC/MAPD operative dates are preserved. Bepis applies a rate from the first venue
week boundary on or after that date. Draft calculations use the applicable effective
book; approved calculations retain exact source identities, calculation/rate-book
versions, pay-version references, approval metadata, segments, and components.

Historical approved entries were backfilled all-or-nothing through the Haskell engine.
That reconstruction ignores source-age thresholds but requires complete effective rates
and statewide holiday facts. Any failure reports the affected entry IDs and rolls back
the batch.

## Supported envelope

The engine supports the matrix-defined MA000009 part-time/casual ordinary, weekend,
public-holiday, weekday addition, recorded unpaid-meal-break, per-entry minimum-payment,
and imported flat-rate branches. Exact elapsed seconds determine quantities; Melbourne
civil time determines Award dates/windows. The stored `permanent` value means MA000009
part-time, not full-time.

Unsupported arrangements and features fail through typed errors. Regional holidays,
overtime, allowances, annualised salaries, leave, superannuation, termination,
guaranteed-hours top-ups, and cross-entry engagement grouping remain outside this
engine unless separately authorized.
