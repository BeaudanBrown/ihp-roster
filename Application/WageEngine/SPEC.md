# Hospitality Award wage engine

## Ownership

`Application.WageEngine` is the provider-neutral, pure calculation module for one
independent timesheet. It owns the typed calculation interface, complete effective
rate-book validation, paid-time/component separation, stable calculation version,
and the currently unchanged Award rule subset. It performs no database or HTTP work.
`Application.VenueTime` is its sole Melbourne civil-time authority.

`Application.WageEngine.Adapter` bulk-loads projected database facts into that
interface. The existing `Application.Helper.Pay.fetchTimesheetPay` and
`fetchTimesheetPayResultsForEntries` SQL seam remains authoritative until cutover
issue #239; no production caller uses the Haskell result yet.

## Validated rate book

Callers construct `ValidatedRateBook` only through `mkValidatedRateBook`; its data
constructor is hidden. A valid MA000009 book has one common effective period and:

- Introductory and Levels 1–6 only (`242`, `243`, `246`, `257`, `268`, `276`, `282`);
- part-time and casual ordinary, Saturday, Sunday, and public-holiday
  rates for every classification;
- Award-wide clause 29.2 evening and early-morning additions;
- positive values, non-empty source identities, and source ownership matching the
  classification or Award.

Value-identical duplicate semantic keys normalize. Any conflict, missing category,
unsupported classification, inconsistent period, invalid value, identity, or owner
returns a named `RateBookError`. Candidate order never selects a conflicting value.
The adapter carries each projection row ID and its exact persisted `fwc_mapd_*`
source-row ID into `RateSourceIdentity`; the rate-book version fingerprints those
identities together with normalized semantic keys and values. The separate
calculation version remains stable across source refreshes. Provider-specific MAPD
retrieval and curation remain in `Application/FwcMapd/`.

## Pure calculation interface

`WageCalculationInput` contains:

- opaque `AwardSegment` values from `Application.VenueTime`, carrying authoritative
  instants and derived Melbourne local date/day/window context;
- a validated Melbourne timezone and VIC statewide public-holiday jurisdiction;
- supported employment arrangement; the stored `permanent` enum is retained for
  database compatibility but means MA000009 part-time exclusively and is displayed
  to customers as “Part-time”;
- an optional `AwardRateContext` that bundles one resolved classification with a
  `ValidatedRateBook` and is required only for Award calculation;
- statewide holiday dates and shift/staff imported-pay-item override context;
- explicit unsupported-feature facts.

The engine never converts civil time to an instant and callers cannot forge UTC/local
segment metadata. `Application.VenueTime` resolves and positively bounds each segment;
the engine additionally requires a non-empty, non-overlapping segment list. The input
remains generic; there is no quarter-hour invariant.

Each result carries `hospitality-award-v1`, separate `PaidTimeSegment` and
`EarningsComponent` lists, exact rational quantities/amounts, source condition, and
`HospitalityAward` or `ExternalImportedPayItem` calculation source. Shift imported
items override staff items and bypass Award conditions and Award-rate-book
availability.

The implemented arithmetic subset is ordinary part-time/casual, Saturday, Sunday,
public holiday, and imported flat-rate parity. Public holiday takes precedence over
weekend. Commenced-hour additions are represented by the component contract but are
rejected as pending instead of copying the legacy hourly/stacked SQL behavior; #231
owns their aggregation and final-line rounding. Minimum payments and meal-break
components remain with #233 and #232 respectively.

## Database adapter

The adapter accepts many entry requests, calls seven bounded bulk-loader phases at
most once each, and builds in-memory indexes for contexts, imported items, Award
levels, rates, additions, holidays, and effective books. The database adapter uses
at most 12 QueryBuilder reads regardless of entry count (fewer when no stored pay
versions or imported items are present). Projection queries are restricted
to the requested active Award levels and effective worked-date window; statewide
holidays are restricted to the requested date span plus the next local date. It
performs no per-entry database query. Partial projected books return
`InvalidProjectedRateBook` for Award calculation, while explicit imported overrides
need no Award book; an unvalidated book can never reach `calculateTimesheetPay`.
Callers attach `Application.VenueTime` Award segments through
`calculationInputFromLoadedContext`. Issue #274 owns persistence and controller/UI
integration of this implemented pure authority.

## Verification

```bash
bash ./bin/in-env hspec-pure --match "Melbourne civil-time authority"
bash ./bin/in-env hspec-pure
bash ./bin/in-env hspec-test --match "database wage-engine adapter"
bash ./bin/in-env hspec-test --match "FWC MAPD"
bash ./bin/in-env typecheck
```
