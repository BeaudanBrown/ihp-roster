# Export Specification

This file describes implemented export behavior and shared rendering rules.

## Current Contract

- Export generation and download are admin-only surfaces: venue admins, venue
  owners, and super admins may generate/download exports; managers are denied.
- `export_jobs` records venue scope, requested fixed export, file metadata,
  requestor, expiry/download lifecycle, and audit-adjacent details.
- The request surface exposes exactly four fixed formats: Approved Timesheets
  CSV, Staff Hours CSV, Hourly Breakdown ZIP, and Payroll Earnings CSV.
- Runtime export generation does not load, bootstrap, or filter through report
  definitions. The legacy report-definition tables remain unused by the app
  runtime until a dedicated data-preserving schema-retirement change removes
  them.
- Plain CSV exports use `file_encoding = "utf8"`.
- ZIP payloads stored in text-backed `file_contents` use base64 with
  `file_encoding = "base64"` and are decoded only in the download path.

## Rendering

- CSV cells must go through `Render.csvCell` or a higher-level renderer that
  uses it.
- `csvCell` owns CSV quoting and spreadsheet formula neutralization for leading
  `=`, `+`, `-`, `@`, tab, carriage return, newline, and whitespace-prefixed
  formulas.
- Export filenames and content-disposition values must be treated as output
  boundaries and encoded safely.
- Timesheet dates and clocks are projected from authoritative instants and their
  stored timezone snapshot. Duration and hourly-breakdown overlap use exact
  instant elapsed time: a repeated autumn hour contributes twice and a skipped
  spring hour contributes zero. Approved Timesheets CSV renders exact elapsed
  break seconds from those instants rather than flooring to minutes. This
  `break_seconds` shape is export schema version 2.

## Payroll

- Staff Hours CSV is one canonical, unfiltered `staff_hours`-style export for
  the venue's active, non-trial staff.
- Historical report-definition variants such as `kitchen` are not runtime
  export behavior.
- Payroll exports must use approved timesheet facts and pay-version context as
  the pay-config-versioning workstream lands.
- Award-rate amounts in exports come from the canonical pay calculation, which
  applies raw FWC/MAPD operative dates through the venue week-start rollover
  rule and does not automatically re-rate already-approved entries.

## Extension Rules

- Do not hand-roll CSV endpoints in controllers.
- Add formats explicitly to the fixed catalog and keep them on the shared
  export-job audit, expiry, and download lifecycle.
- Keep detailed payroll-number validation in Hspec/golden tests.
- Use browser tests only to prove the export workflow still functions.

## Verification

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Exports"
bash ./bin/in-env hspec-test --match "Fixed export goldens"
bash ./bin/in-env e2e e2e/exports-payroll-downloads.spec.ts
```
