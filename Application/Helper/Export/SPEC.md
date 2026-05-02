# Export Specification

This file describes implemented export behavior and shared rendering rules.

## Current Contract

- Export generation and download are admin-only surfaces: venue admins, venue
  owners, and super admins may generate/download exports; managers are denied.
- `export_jobs` records venue scope, requested report, file metadata,
  requestor, expiry/download lifecycle, and audit-adjacent details.
- Payroll report selection is separate from export-job lifecycle. Report
  definitions decide which report a venue can request; export jobs represent
  concrete generated files.
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

## Payroll

- The active product target is one canonical `staff_hours`-style CSV for the
  primary/only venue staff group.
- Historical filtered variants such as `kitchen` are regression behavior, not
  the first-class current requirement.
- Payroll exports must use approved timesheet facts and pay-version context as
  the pay-config-versioning workstream lands.

## Extension Rules

- Do not hand-roll CSV endpoints in controllers.
- Do not let a report definition bypass export-job audit and expiry handling.
- Keep detailed payroll-number validation in Hspec/golden tests.
- Use browser tests only to prove the export workflow still functions.

## Verification

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Exports" --match "Payroll export parity"
bash ./bin/in-env e2e e2e/exports-payroll-downloads.spec.ts
```
