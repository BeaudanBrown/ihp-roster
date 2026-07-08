# Pay Engine Specification (Mixed Architecture)

## Architecture decision

Canonical pay math is implemented in PostgreSQL functions; application-layer orchestration/reporting is implemented in Haskell.

## Why mixed

- SQL functions provide deterministic, centralized calculations near data.
- Haskell layer provides composable workflow orchestration, presentation shaping, and easier UI/report integration.

## Canonical calculation rules

## Input constraints

- Time values use exact 15-minute increments.
- Break is deducted from shift duration before applying rate rules.

## Day/window model

- Weekday windows:
  - Ordinary: 07:00-19:00
  - Evening: 19:00-00:00
  - After-midnight: 00:00-07:00
- Weekend behavior:
  - Weekend multiplier applies,
  - and **stacks** with configured penalties/additions.

## Pay level resolution

For each calculable segment:

1. Use `shift_types.override_award_level_id` when the entry's shift type has an override.
2. Otherwise fall back to `staff.default_award_level_id`.
3. Resolve monetary values from `award_level_base_rates` and `award_level_penalty_rates` for the effective award level and staff employment basis.

## FWC/MAPD rate rollover

Raw FWC/MAPD `operative_from` dates are preserved as imported facts, but Bepis
applies refreshed award rates from the first venue operational week that starts
on or after the raw operative date. For the current implementation,
`venue_config.roster_week_starts_on` is the pay-period proxy. For example, if a
venue week starts Monday and FWC publishes a Wednesday operative date, unapproved
calculations, current dropdown labels, roster wage predictions, exports, and
Xero managed pay-item keys use the new rate from the following Monday.

Approved entries are not automatically re-rated. They continue to use their
stored staff/shift pay-version context and only consider award-rate rows that
existed at approval time; if a later import closes an old row, approved
calculation remains anchored to the pre-import rate rather than mutating history.
A provider-neutral payroll calendar/frequency model and support bulk re-rate
workflow are future work.

The SQL payloads and helper names still use "pay level" in some places for
legacy compatibility, but the current schema-backed concept is an award level.
There is no current `pay_level_day_rules` table; day-specific award-level
overrides are future work if the product needs them again.

## Historical reproducibility requirements

- Past pay results must remain explainable even after later changes to award levels, rates, shift types or venue configuration.
- The historical stability model is snapshot/version based:
  - venue admin bulk config edits create a new immutable pay/config version on save
  - approved records and exports store the version reference used
- Exported pay data must include a schema or calculation version that lets the result be interpreted later.
- Recalculation of historical periods must use the applicable historical rule set, not whatever configuration happens to be current at request time.
- Draft and unapproved calculations may use the venue's current editable config, but approved/exported outputs must use their stored snapshot version.

## Suggested PostgreSQL function surface (v1)

- `calculate_timesheet_pay(entry_id uuid) returns jsonb`
  - Returns breakdown (segments, rates, penalties, totals).
- `calculate_timesheet_pay_range(staff_id uuid, from_date date, to_date date) returns setof ...`
  - Batch reporting support.
- `resolve_effective_pay_level(staff_id uuid, shift_type_id uuid, day_of_week int) returns uuid`
  - Shared helper for precedence logic.

These functions should be pure/read-only from perspective of business state (no side effects besides computation).
They should also resolve pay logic against an explicit historical rule context rather than implicitly trusting only current live config.

## Haskell orchestration responsibilities

- Validate user intent and permissions.
- Call SQL functions for canonical numbers.
- Compose API/view models for roster/timesheet/report screens.
- Generate CSV/report payloads from SQL results.
- Create or reference the correct pay/config version when venue admin bulk-save actions publish new config snapshots.

## Pros/cons reference

## SQL-first pros

- Single source of truth.
- Strong for set-based batch pay reporting.
- Easier parity across screens using same DB function.

## SQL-first cons

- Harder unit testing ergonomics compared with pure Haskell.
- Business logic can become opaque if function surface is not well documented.

## Haskell-first pros

- Easier pure-function testing and refactoring.
- More familiar debugging for app developers.

## Haskell-first cons

- Risk of drift if multiple query paths recalculate differently.
- Potentially less efficient for heavy aggregate/batch computations.

## Mixed tradeoff (selected)

- Keep canonical math in SQL to avoid drift.
- Keep workflow/report composition in Haskell for maintainability and test ergonomics.
