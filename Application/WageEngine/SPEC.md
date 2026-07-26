# Hospitality Award wage engine

## Ownership

`Application.WageEngine` is the provider-neutral, pure calculation module for one
independent timesheet. It owns the typed calculation interface, complete effective
rate-book validation, paid-time/component separation, final-line derivation, and
stable calculation version. It performs no database or HTTP work.
`Application.VenueTime` is its sole Melbourne civil-time authority.

The facade is the sole caller-facing module. Internally, `Types` owns stable
calculation facts, `RateBook` owns the opaque validated rate book and its validation,
`Rules` evaluates intervals, `Components` constructs exact components, and `Rounding`
derives final buckets/lines.

Draft Timesheets calculations preserve each successful preview and attach source warnings
without preventing saves; calculation failures remain entry-local. Approval, fixed exports,
and Xero readiness/preview/submission all call the shared strict enforcement boundary, so
one failing included entry rejects the complete requested final operation. Imported Xero
overrides bypass FWC/DataVic freshness only after their persisted imported pay item resolves.
Legacy approved-ledger backfill continues to ignore source age while requiring complete
rate and holiday calculation facts.

`Application.WageEngine.Adapter` bulk-loads projected database facts into that
interface. Approval persists the Haskell result through
`Application.Helper.TimesheetPayLedger`; approved exact facts can be reconstructed
without consulting mutable rate sources. Final workflows use
`loadApprovedTimesheetPayCalculations`, which reads calculations, paid-time segments,
and earnings components in three bounded queries regardless of entry count; the
single-entry helper delegates to that bulk seam. Draft callers calculate through the adapter and pure engine. Approved/final callers
load sealed ledger facts; cutover #239 retired the legacy SQL calculator and decoder
seam.

## Wage-source policy

`Application.WageSourcePolicy` is the pure provider-neutral boundary for draft and
final source-readiness decisions. Callers inject the current UTC time, venue pay-week
boundary, applicable DataVic target years, and candidate metadata. Only complete
successes from the validated MAPD snapshot boundary at or before the injected clock
count for FWC freshness. DataVic candidates count only when they represent authoritative
statewide Victoria coverage for the target year. Award calculations warn in draft and
block final use when the latest FWC success is older than 8 days, the first full venue
week beginning on/after 1 July lacks a success on/after 1 July, or an applicable
DataVic year is missing or older than 45 days. Exact 8-day and 45-day boundaries remain
valid. Failed, incomplete, unvalidated, and non-statewide candidates never displace a
last complete authoritative success, while imported Xero overrides bypass both source
checks.

The same module compares canonical Award document and structural fingerprints. A
document checksum/version, classification, or category change emits a deterministic
deduplication key scoped to a non-blocking platform-super-admin signal. Rate-only and
unchanged-structure refreshes emit no drift signal. The pure policy performs no persistence
or network work. `Application.WageSourceEnforcement` adapts persisted source facts and
entry calculations into per-entry draft outcomes and strict final batches. Successful MAPD
publication compares the latest two fingerprints and enqueues permanently deduplicated
notifications for active platform super admins only; drift remains non-blocking.

## Validated rate book

Callers construct `ValidatedRateBook` only through `mkValidatedRateBook`; its data
constructor is hidden. A valid MA000009 book has one common effective period and:

- Introductory and Levels 1–6 only (`242`, `243`, `246`, `257`, `268`, `276`, `282`);
- part-time and casual ordinary, Saturday, Sunday, and public-holiday
  rates for every classification;
- Award-wide clause 29.2 evening and early-morning additions;
- positive values, non-empty source identities, and source ownership matching the
  classification or Award.

MAPD annual projection rows can remain open-ended after a newer annual snapshot is
published. For a worked date, the adapter selects the snapshot with the latest applicable
`operative_from` before constructing the candidate; it preserves every historical source
row and still rejects conflicts within the selected snapshot. Value-identical duplicate
semantic keys normalize. Any conflict, missing category, unsupported classification,
inconsistent period, invalid value, identity, or owner returns a named `RateBookError`.
Candidate order never selects a conflicting value.
The adapter carries each projection row ID and its exact persisted `fwc_mapd_*`
source-row ID into `RateSourceIdentity`; the rate-book version fingerprints those
identities together with normalized semantic keys and values. The separate
calculation version remains stable across source refreshes. Provider-specific MAPD
retrieval and curation remain in `Application/FwcMapd/`.

## Pure calculation interface

`WageCalculationInput` contains:

- a non-empty, contiguous full-shift sequence of opaque `AwardSegment` values from
  `Application.VenueTime`, carrying authoritative instants and derived Melbourne
  local date/day/window context;
- an optional opaque `ResolvedInterval` for the recorded unpaid meal break;
- a validated Melbourne timezone and VIC statewide public-holiday jurisdiction;
- supported employment arrangement; the stored `permanent` enum is retained for
  database compatibility but means MA000009 part-time exclusively and is displayed
  to customers as “Part-time”;
- an optional `AwardRateContext` that bundles one resolved classification with a
  `ValidatedRateBook` and is required only for Award calculation;
- statewide holiday dates and shift/staff imported-pay-item override context;
- explicit unsupported-feature facts.

The engine never converts civil time to an instant and callers cannot forge UTC/local
segment metadata. `Application.VenueTime` resolves and positively bounds each segment
and break; the engine additionally requires a non-empty, contiguous segment sequence
and a break contained in that shift. It subtracts the recorded unpaid break exactly
once before constructing paid segments. The input remains generic; there is no
quarter-hour invariant.

Each result carries `hospitality-award-v1`, separate `PaidTimeSegment` and
`EarningsComponent` lists, exact rational quantities/amounts, source condition, and
`HospitalityAward` or `ExternalImportedPayItem` calculation source. Shift imported
items override staff items and bypass Award conditions and Award-rate-book
availability.

The implemented arithmetic subset is ordinary part-time/casual, Saturday, Sunday,
public holiday, imported flat-rate parity, weekday clause 29.2 additions, clauses
16/29.3 recorded unpaid-meal-break rules, and per-entry minimum payments. Public
holiday takes precedence over weekend; weekday additions never stack with
weekend/public-holiday base rates. Eligible evening and early-morning worked intervals
are grouped separately by local date/window before their exact elapsed hours are
rounded up to whole `commenced_hours`; a split, break, or six-hour boundary cannot
duplicate a unit. The addition is a separate fixed-rate component and never adds paid
time.

Award-calculated casual entries receive at least two paid elapsed hours. If short, the
engine uses `Application.VenueTime` to segment a hypothetical continuation from the
actual shift end, emits `casual_minimum_engagement_top_up` paid-time segments, and
selects each hourly condition from that continuation. When a paid actual interval in an
entry falls on a statewide public holiday, the public-holiday minimum wins instead:
four paid hours for part-time and two for casual. All paid actual time in that entry,
including immediately before or after the holiday, counts toward that one threshold;
the shortfall is a `public_holiday_minimum_top_up` segment with a public-holiday-rate
hourly component. The two minimum kinds never stack. Both kinds are explicitly
non-worked paid time, and weekday commenced-hour additions still derive only from
actual worked intervals.

For a gross shift longer than six exact elapsed hours, a recorded break qualifies when
it lasts at least 30 exact elapsed minutes and starts inclusively from two through six
hours after shift start. An untimely/absent break emits one separate
`missed_meal_break_addition` component from the six-hour instant to shift end; a
30-minute break beginning after six hours stops that addition when it begins. The
component uses the resolved level's part-time ordinary rate × 50%, including for
casuals, and remains cumulative with the one selected base condition and any weekday
fixed addition. Imported overrides still deduct a recorded unpaid break but bypass all
Award conditions, additions, missed-break pay, and minimum payments.

`deriveFinalEarnings` groups exact components by a stable key containing their unit,
condition, source, rate, and source identity. It preserves exact quantities/amounts,
rounds each grouped monetary line once to cents, then sums those rounded lines. Its
`FinalEarningsSummary` remains provider-neutral and exact-quantity based.
`Application.WagePublication` owns the payroll-output transform shared by detailed
CSV and Xero: aggregate by final bucket, round hourly quantities once to the nearest
quarter hour with exact ties up, keep commenced-hour units whole, and recompute the
exported amount from transformed quantity × rate without mutating approved facts.
It also adapts sealed paid-time segments into Staff Hours local clock buckets.

## Database adapter

The adapter accepts many entry requests, calls seven bounded bulk-loader phases at
most once each, and builds in-memory indexes for contexts, imported items, Award
levels, rates, additions, holidays, and effective books. Its per-entry result form
retains successful draft contexts beside deterministic entry-local failures, so
bulk draft diagnostics do not reintroduce per-entry loading or discard valid previews. The database adapter uses
at most 12 QueryBuilder reads regardless of entry count (fewer when no stored pay
versions or imported items are present). Projection queries are restricted
to the requested active Award levels and effective worked-date window; statewide
holidays are restricted to the requested date span plus the next local date. It
performs no per-entry database query. Partial projected books return
`InvalidProjectedRateBook` for Award calculation, while explicit imported overrides
need no Award book; an unvalidated book can never reach `calculateTimesheetPay`.
Callers attach gross `Application.VenueTime` Award segments and the optional opaque
recorded-break interval through `calculationInputFromLoadedContext`. Issue #234 owns immutable approval persistence, lifecycle, and deployment
backfill. Approval serializes on one narrow `SELECT ... FOR UPDATE` seam because
IHP QueryBuilder has no row-lock combinator; all wage/source loading remains
QueryBuilder-based. All approved export/read models use this exact ledger after cutover #239.

## Verification

HPC reports the `Application.WageEngine` facade as `0/0` because it only re-exports
focused modules. The remaining unticked pure `Rules` expressions are defensive
failure mappings behind opaque, positively bounded `VenueTime` segments and the
second unsupported-employment guard after `validateCalculationContext`; callers
cannot construct those states. Supported rule branches have named matrix evidence.

```bash
bash ./bin/in-env hspec-pure --match "WageSourcePolicy"
bash ./bin/in-env hspec-pure --match "Melbourne civil-time authority"
bash ./bin/in-env hspec-pure --match "WageEngine components"
bash ./bin/in-env hspec-pure --match "WageEngine unpaid meal breaks"
bash ./bin/in-env hspec-pure
bash ./bin/in-env hspec-test --match "database wage-engine adapter"
bash ./bin/in-env hspec-test --match "FWC MAPD"
bash ./bin/in-env typecheck
```
