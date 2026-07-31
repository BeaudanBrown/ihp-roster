# Export Specification

This file describes implemented export behavior and shared rendering rules.

## Current Contract

- Export generation and download are exposed in the Admin page's Exports
  accordion as admin-only surfaces: venue admins, venue owners, and super admins
  may generate/download exports; managers are denied.
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
  break seconds from those instants rather than flooring to minutes. Staff
  Hours and Hourly Breakdown aggregate exact rational quantities before their
  final output transform. The exact-second `break_seconds` shape was introduced
  in export schema version
  2; the approved-ledger payroll publication contract is schema version 3.
  Payroll hourly quantities aggregate by final output bucket and then round once
  to the nearest quarter hour; exact 7.5-minute ties round up. Commenced-hour
  quantities remain whole units. Rounded hourly line amounts are recomputed from
  output quantity × approved rate and rounded once to cents.

## Payroll

- Staff Hours CSV is one canonical, unfiltered paid-time export for the venue's
  active, non-trial staff. For the supported Tuesday payroll week it uses the
  exact `Employee,Tues Ord,...,Mon 12+` contract and filename
  `staff_hrs_starting-YYYY-MM-DD.csv`. Rows use `Last, First` plus the optional
  approval-pinned calculated pay label, preserve separate labels, and sort by
  last name, first name, then label with the unlabeled row first. Non-worked
  minimum top-ups fall back to that local day's ordinary bucket; fixed and
  missed-break additions never inflate Staff Hours.
- Historical report-definition variants such as `kitchen` are not runtime
  export behavior.
- Staff Hours and Payroll Earnings consume sealed approved paid-time segments
  and earnings components. They do not recalculate from mutable rate tables or
  the legacy SQL pay-result renderer.
- Payroll Earnings records exact and exported quantity/amount, explicit
  `hours`/`commenced_hours` units, rate/source identity, calculation and rate-book
  versions, approval provenance, active calculation ids, and source entry ids.
  Every positive approved component contributes to exactly one final earnings
  bucket.
- Award-rate amounts in exports come from the canonical pay calculation, which
  applies raw FWC/MAPD operative dates through the venue week-start rollover
  rule and does not automatically re-rate already-approved entries.
- Every fixed final export enforces wage calculation and source readiness as one
  strict batch before persisting output. Any included entry failure rejects the
  requested export; no entry is silently omitted. Imported Xero overrides bypass
  FWC/DataVic freshness only when their imported pay item remains valid.

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
