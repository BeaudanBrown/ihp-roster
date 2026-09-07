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
  configured Payroll Workbooks for one URL-selected roster week. Payroll Earnings
  CSV generation is hidden pending a later retirement decision. Export history is
  not shown. Legacy Staff Hours/hourly generators remain callable
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
  families. Version 1 supports Summary, employee/pay-bucket Hours, shift-type
  Hours, employee/pay-bucket Wages, and shift-type Wages. The standard Payroll
  Workbook contains every supported family in that order but is persisted as an
  ordinary venue configuration that users may edit or delete.
- Venues may persist named definitions with whitespace-normalized, non-empty,
  case-insensitively unique names and contiguous ordered family selections.
  Persistence accepts only supported definition versions and family keys and at
  least one presentation family. Admins, owners, and unimpersonated founder
  support with a real current venue may create, list, read, and delete saved
  definitions; managers and cross-venue identifiers are denied. The Admin
  exports surface provides included-sheet summaries, per-definition download
  actions, and an explicit two-step delete confirmation; stale or foreign
  identifiers produce controlled errors. Creation and editing share one
  catalog-driven dialog that always renders Included sheets and Excluded sheets.
  Server-rendered Add, Remove, Up, and Down controls transform only the unsaved
  overlay draft; Save is the sole persistence action. Configuration-facing copy
  names the families Hours/Wages by Staff or Shift Type without changing stable
  family keys or XLSX worksheet names. There is no storage-level family-count
  ceiling; revisions reject stale overwrites. All configurations appear once in
  the normal exports list and may be deleted, including the venue's final one.
  Payroll Earnings CSV generation is hidden while its backend and historical
  downloads remain available pending a later retirement decision. Deletion
  cascades only to the saved family rows. Export jobs retain the stable
  definition key, version, and ordered family snapshot independently of future
  configuration changes or deletion.
- Every valid definition automatically appends the deterministic typed Data
  worksheet. Data is implementation-owned, hidden by default, and cannot be
  selected or omitted as a presentation family. Daily Staff Hours and Wages
  sheets render hour slots down rows and deterministic staff/pay-bucket
  combinations across columns, leave zero details blank, and calculate row,
  column, and day totals with formulas. Their visible headings use first name,
  last name, and the approval-pinned pay-bucket label, compact `Level n` to
  `LVL n`, and suffix display collisions without merging authority. Exactly
  three hidden columns map each visible staff column to its Excel column
  reference, Staff ID, and stable pay-bucket key. Each roster-week Summary has
  no title or totals. Its formulas aggregate paid-hour Data facts directly, so
  Summary remains valid when the Staff Hours family is omitted.
  Weekdays use Ord/7-12/12+ buckets; Saturday and Sunday use Ord/12+, with every
  next-day hour in 12+. Shift-type sheets transpose hourly facts into ordered
  approval-pinned shift-type columns, aggregate repeated civil-hour occurrences,
  preserve skipped hours as visible zero totals, leave zero detail cells blank,
  and use formulas for row, column, and day totals. Hours display six decimals;
  Wages remain numeric AUD dollars at two decimals.
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
