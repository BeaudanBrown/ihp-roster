# Pipeline 45 — Payroll Report Exports

Read after `IMPLEMENTATION_PLAN.md` and `plans/40-pay-config-and-admin.md`.

## Goal

Replicate the legacy Go payroll/report exports inside `ihp-roster` using the existing `export_jobs` lifecycle, while moving the app toward venue-owned, configurable report definitions instead of hardcoded report endpoints.

## Current Product Focus

The historical port introduced multiple legacy report variants, but the current product focus is narrower:

- one canonical payroll CSV for the primary/only venue staff group is the active target
- legacy filtered variants such as `kitchen` are not first-class requirements right now
- hourly ZIP parity is not the active target right now
- future multiple staff-group or roster-group exports should be handled by a dedicated later lane rather than by treating `kitchen` as a special current concept

Treat the broader legacy inventory below as implementation history and future compatibility context, not as the active acceptance target for the current testing lane.

## Scope

- legacy report parity inventory
- SQL pay-engine fit assessment
- venue-scoped report definition model
- first staff-pay CSV export
- hourly breakdown ZIP parity
- admin/report configuration surface
- regression coverage for report shape and snapshot provenance

## Legacy Report Inventory

The old Go app currently exposes two report engines and three concrete venue reports:

1. `hourly_breakdown_zip`
   - Legacy slug: `wage`
   - Download filename: `<slug>-<week-start>.zip`
   - Payload: ZIP containing one CSV per configured venue day
   - Per-day CSV filename: `<day-name>.csv`
   - Columns: `Time` plus active shift type names ordered by shift-type sort order
   - Rows: hourly windows from `08:00` through `03:00+1`
   - Data: approved entry overlap hours per shift type per hour bucket

2. `staff_pay_csv`
   - Legacy slug: `staff_hours`
   - Download filename: `<slug>-<week-start>.csv`
   - Columns: `Name`, `Type`, configured venue day names, `Total`
   - Rows: one row per staff member per effective pay level
   - Data source: approved weekly entries only

3. `staff_pay_csv` with shift-type filter
   - Legacy slug: `kitchen`
   - Download filename: `<slug>-<week-start>.csv`
   - Same day-column shape as `staff_hours`
   - Filter: `filter_shift_types = ["Kitchen"]`
   - Rows collapse to one row per staff member with a blank `Type` column

## Legacy Semantics That Must Be Preserved

- Reports are selected by venue-local slug, not by one global export type alone.
- Access is manager/admin-only.
- Default scope is the current week offset; the old app accepts an explicit `week` query parameter.
- Staff-pay CSV excludes unapproved entries and trial staff.
- Staff-pay CSV uses three pay windows for hours:
  - ordinary `07:00-19:00`
  - evening `19:00-00:00`
  - after-midnight `00:00-07:00` on the next day
- Staff-pay CSV resolves pay level from shift-type defaults plus day-specific overrides.
- Hourly ZIP uses approved entries only and buckets overlap by shift type across `08:00-03:00+1`.

## Current New-System Fit

The current `ihp-roster` architecture is directionally correct but not sufficient for legacy parity yet.

### What already fits

- `export_jobs` is the right lifecycle boundary for request, generation, expiry, download, and audit.
- Snapshot-pinned provenance is the right stability model for payroll-adjacent exports.
- `calculate_timesheet_pay` and `calculate_timesheet_pay_range` already encode the old day windows:
  - `after_midnight 00:00-07:00`
  - `ordinary 07:00-19:00`
  - `evening 19:00-00:00`
- Haskell-side export shaping is already centralized in `Application/Helper/Export.hs`.

### Gaps that block parity

1. The current SQL pay engine does not resolve against the entry's actual shift type.
   - `calculate_timesheet_pay` currently derives pay level from `first_shift_type` instead of `timesheet_entries.shift_type_id`.
   - That makes current output unsuitable for pay-level-based payroll reports.

2. The current pay-config model does not match the old report model closely enough.
   - Legacy behavior uses `shift_type + day_offset -> pay_level` overrides.
   - The new schema currently models `pay_level_day_rules` as `pay_level + day_name -> multiplier`.
   - That supports multiplier stacking, but it does not express "this shift type becomes a different pay level on Friday/Saturday/Sunday".

3. The current SQL pay output is only a partial scaffold.
   - `baseRate`, `amount`, and `totals.totalAmount` are all hard-coded to `0`.
   - No effective pay-level identifier/label is exposed in the decoded Haskell type.
   - No shift-type identifier is carried in the payload.

4. The current export surface is range-based, not report-definition-based.
   - The existing export UI only supports one global `approved_timesheets_csv`.
   - Legacy parity requires venue-scoped report definitions with slug, label, engine type, and optional shift-type filters.

5. The current range helper is not enough by itself for weekly payroll reports.
   - `calculate_timesheet_pay_range` is staff/date-range oriented.
   - The staff-pay CSV needs week-scoped aggregation across all approved entries in the current venue, grouped by staff and effective pay level.

## Architecture Decision

Use a mixed model:

- SQL remains the canonical source for pay-segment math and snapshot-aware pay resolution.
- Haskell remains responsible for week/report orchestration, grouping, CSV/ZIP formatting, and export-job lifecycle.
- Report variants become a first-class venue-scoped definition model rather than additional hardcoded controller branches.

## Concrete Implementation Order

1. Add a venue-scoped report definition read/model layer.
   - Fields: `slug`, `name`, `description`, `engine`, `sort_order`, `is_active`
   - Optional shift-type filters for report variants such as `kitchen`
   - Seed/read the current legacy definitions before building admin editing

2. Fix the SQL/Haskell pay engine for report use.
   - Resolve pay level from the entry's actual `shift_type_id`
   - Carry effective pay-level and shift-type identifiers through the result
   - Replace placeholder amount/rate fields with real values if the first export needs them
   - Reconcile the current multiplier model with the old pay-level-override model

3. Implement the first `staff_pay_csv` export on top of `export_jobs`.
   - Report selected by venue report definition slug
   - Week-scoped generation
   - Legacy filename and CSV shape
   - Approved-only, trial-staff exclusion, snapshot metadata, and audit

4. Implement `hourly_breakdown_zip` on the same report-definition model.

5. Add admin/report configuration UI and regression coverage.

## Acceptance Checks

- The canonical `staff_hours` payroll CSV can be represented without controller hardcoding.
- The first payroll CSV uses the same day/time-window semantics and filename convention as the old report.
- Export jobs remain venue-scoped, audited, expiring, and snapshot-pinned.
- At least one golden-style test proves the new staff-pay CSV matches the intended row/column shape for a representative week.
- Legacy filtered variants and future multi-group exports remain possible through the generic report-definition model, but they are not required to land as first-class current product behavior.
