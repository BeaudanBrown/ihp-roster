# Export Helpers

## Ownership

`Application/Helper/Export/` owns the fixed export catalog, venue-scoped read
models, payload construction, safe rendering, export-job persistence, expiry,
download authorization, and controller-facing orchestration.

## Start Here

- `Service.hs` — controller-facing generation and download boundary.
- `Types.hs` and `Definitions.hs` — fixed catalog and date/week rules.
- `ReadModel.hs` and `Payloads.hs` — authoritative export inputs and payloads.
- `PayrollWorkbook.hs` — versioned ordered definitions for Summary, hourly-row Staff and shift-type Hours/Wages families; collision-safe Staff/pay-bucket columns with hidden identity mappings; the implementation-owned hidden Data worksheet; formulas, typed XLSX cells, formatting, and worksheet primitives.
- `PayrollWorkbookModel.hs` — authoritative entry × Operational-date × hourly-occurrence facts, presentation projection, DST slots, approval-pinned identities, and exact Hours/Wages reconciliation.
- `PayrollWorkbookConfiguration.hs` — venue-scoped named definition persistence, ordered family hydration, optimistic edits, validation, authorization, and venue-safe deletion. The Admin exports surface presents one unified list and uses the same scalable Included/Excluded sheet dialog with server-rendered Add, Remove, Up, and Down draft controls for creation and editing. The former built-in default is provisioned as an ordinary editable and deletable venue configuration.
- `Render.hs` — CSV/ZIP formatting and output safety.
- `Persistence.hs` — job lifecycle, authorization, and audit.
- `Application/Helper/Export.hs` — compatibility facade only.
- [Web export workflows](../../../Web/Exports/README.md) — saved-configuration request adaptation and completion; Application persistence remains free of HTTP/view dependencies.

## Spreadsheet Compatibility Verification

The Payroll Workbook formula gate runs through pinned, headless LibreOffice Calc
with an isolated profile. Use the repository wrapper; LibreOffice is a dev-shell
verification dependency and is intentionally absent from the production app
closure.

For the required Google Sheets smoke test, materialize the reviewed formula
fixture, then import it with **File → Import → Upload**:

```bash
PAYROLL_WORKBOOK_COMPATIBILITY_DIRECTORY=.pi/tmp/payroll-workbook-compatibility \
    bash ./bin/in-env hspec-pure --match "recalculates default and representative configured variants"
```

Import both `payroll_workbook-default.xlsx` and
`payroll_workbook-wages-summary.xlsx`. Confirm that Summary and daily Total
formula cells display numeric values without an import or formula error; the
configured workbook proves Summary remains valid without an employee Hours
presentation sheet. Formatting need not be pixel-identical. Record the import
date, Google Sheets result, and any caveat on the implementing GitHub issue; do
not commit transient verification reports.

## Related Docs

- `SPEC.md` — durable authorization, payroll, and rendering contracts.
- `AGENTS.md` — editing and verification rules.
- `docs/workstreams/record-retention.md` — unresolved protected-record work.
