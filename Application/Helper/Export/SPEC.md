# Export Specification

Implemented formats, fields, and exact bytes are authoritative in
`Application/Helper/Export/` and export golden tests. This document retains only
cross-module safety and payroll contracts.

## Access And Lifecycle

- Export generation and download are venue-scoped admin capabilities for venue
  admins, owners, and founder super admins. Managers are denied.
- Every format uses the shared `export_jobs` persistence, expiry, authorization,
  download, and audit lifecycle. Controllers must not hand-roll export endpoints.
- The fixed backend catalog is defined in `Types.hs`; the current UI exposes
  Payroll Workbook and Payroll Earnings CSV for one URL-selected roster week.
  Export history is not shown. Legacy Staff Hours/hourly generators remain callable
  and historical jobs remain downloadable through their authorized direct links,
  but have no visible generation controls.
  Legacy report-definition tables are not runtime authority.
- A generation failure or empty Staff Hours result does not persist a misleading
  export. ZIP bytes are base64 only at the text-backed persistence boundary.

## Output Safety

- Every CSV cell passes through `Render.csvCell`, including spreadsheet-formula
  neutralization. Filenames and content-disposition values are encoded as output
  boundaries.
- Times and component dates project from authoritative instants plus the stored
  timezone. Operational date selects the export window and keeps the complete
  entry in that window. Elapsed duration uses instant differences, so repeated
  and skipped DST hours remain exact.
- Hourly Staff Hours and Hourly Wage Totals share one Operational-day window. The
  current venue picker window is the minimum, approved entry boundaries expand
  it, and both ends round outward to clock hours. Every selected Operational date
  is emitted and owns its complete overnight entries.
- Hourly Wage Totals consumes sealed earnings. Base earnings follow their paid
  intervals; minimum top-ups spread across actual worked seconds; commenced-hour
  additions spread across their qualifying worked seconds; missed-break
  additions follow the penalised interval. Per-entry rounded cents are allocated
  deterministically and every visible row, column, and daily total reconciles.
- Payroll Workbook authority is one normalized fact per approved entry,
  Operational date, and report-window hourly occurrence. Facts retain stable
  entry, staff, shift-type, pay-bucket, pay-version, and calculation identities,
  actual worked hours, allocated paid hours, and server-sealed wage cents.
  Employee/pay-bucket presentations are projections of those facts, never a
  second payroll calculation. One outward-rounded range applies to every date;
  repeated civil hours retain first/second occurrences and skipped hours remain
  zero. Net worked time plus minimum top-up is allocated over actual worked
  seconds, Hours reconcile at six decimals, and Wages reconcile exactly to sealed
  cents. Empty batches or any included-entry authority/timing/wage failure reject
  the complete workbook.
- Payroll Workbook presentation is selected by a versioned definition with a
  stable key and an ordered, duplicate-free, non-empty list of available sheet
  families. Version 1 supports Summary, employee/pay-bucket Hours, and
  employee/pay-bucket Wages; shift-type Hours/Wages keys are reserved and reject
  generation until their presentations are implemented. The built-in default
  contains every currently available family in that order. Export jobs retain
  the definition key, version, and ordered family snapshot independently of
  future configuration changes.
- Every valid definition automatically appends the deterministic typed Data
  worksheet. Data is implementation-owned, hidden by default, and cannot be
  selected or omitted as a presentation family. Daily sheets share hour columns,
  retain hidden
  staff/pay-bucket keys, and calculate all totals with formulas. Each roster-week
  Summary has no title or totals and joins Hours sheets by those stable keys.
  Weekdays use Ord/7-12/12+ buckets; Saturday and Sunday use Ord/12+, with every
  next-day hour in 12+. Zero values display blank, Hours display six decimals,
  and Wages remain numeric AUD dollars at two decimals.
- Aggregation retains exact quantities until the format's final transform.
  Published CSV and Xero precision, units, cent rounding, headers, filenames,
  and schema versions are executable contracts in renderers and golden tests.

## Payroll Authority

- Staff Hours and Payroll Earnings consume sealed approved paid-time segments
  and earnings components; they never recalculate from mutable rates or the
  retired SQL pay renderer.
- Every positive approved component contributes to exactly one final earnings
  bucket. Payroll Earnings exposes both sealed Operational date and Component
  date; Staff Hours retains in-window clock buckets and assigns any period-end
  spill to the entry's Operational-day position so no paid time is omitted.
  Approval and calculation provenance remain attached to exported facts.
- The complete requested batch passes the shared strict wage-source boundary
  before output is persisted. Any included-entry failure rejects the whole
  export; entries are never silently omitted.
- Imported Xero overrides bypass external Award-source freshness only while the
  approval-pinned imported item remains valid.

## Extension Rules

Add formats explicitly to the fixed catalog and shared lifecycle. Keep exact
numbers and byte contracts in Hspec/golden tests; browser tests prove only the
workflow.

## Verification

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Exports"
bash ./bin/in-env hspec-test --match "Fixed export goldens"
bash ./bin/in-env e2e e2e/exports-payroll-downloads.spec.ts
```
