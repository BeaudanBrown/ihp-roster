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
  Staff Hours CSV, Hourly Breakdown ZIP, and Payroll Earnings CSV for one
  URL-selected roster week. Legacy report-definition tables are not runtime
  authority.
- A generation failure or empty Staff Hours result does not persist a misleading
  export. ZIP bytes are base64 only at the text-backed persistence boundary.

## Output Safety

- Every CSV cell passes through `Render.csvCell`, including spreadsheet-formula
  neutralization. Filenames and content-disposition values are encoded as output
  boundaries.
- Times and dates project from authoritative instants plus the stored timezone.
  Elapsed duration uses instant differences, so repeated and skipped DST hours
  remain exact.
- Aggregation retains exact quantities until the format's final transform.
  Published CSV and Xero precision, units, cent rounding, headers, filenames,
  and schema versions are executable contracts in renderers and golden tests.

## Payroll Authority

- Staff Hours and Payroll Earnings consume sealed approved paid-time segments
  and earnings components; they never recalculate from mutable rates or the
  retired SQL pay renderer.
- Every positive approved component contributes to exactly one final earnings
  bucket. Payroll Earnings retains actual component dates, including overnight
  spill beyond the selected range. Staff Hours keeps in-range dates and places
  out-of-range overnight spill in the selected report's matching weekday and
  clock-category column. Approval and calculation provenance remain attached to
  exported facts.
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
