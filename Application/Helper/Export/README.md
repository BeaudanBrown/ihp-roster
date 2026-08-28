# Export Helpers

## Ownership

`Application/Helper/Export/` owns the fixed export catalog, venue-scoped read
models, payload construction, safe rendering, export-job persistence, expiry,
download authorization, and controller-facing orchestration.

## Start Here

- `Service.hs` — controller-facing generation and download boundary.
- `Types.hs` and `Definitions.hs` — fixed catalog and date/week rules.
- `ReadModel.hs` and `Payloads.hs` — authoritative export inputs and payloads.
- `PayrollWorkbook.hs` — locked Summary/Hours/Wages presentation plus the normalized Data worksheet, formulas, typed XLSX cells, formatting, and worksheet primitives.
- `PayrollWorkbookModel.hs` — authoritative entry × Operational-date × hourly-occurrence facts, presentation projection, DST slots, approval-pinned identities, and exact Hours/Wages reconciliation.
- `Render.hs` — CSV/ZIP formatting and output safety.
- `Persistence.hs` — job lifecycle, authorization, and audit.
- `Application/Helper/Export.hs` — compatibility facade only.

## Spreadsheet Compatibility Verification

The Payroll Workbook formula gate runs through pinned, headless LibreOffice Calc
with an isolated profile. Use the repository wrapper; LibreOffice is a dev-shell
verification dependency and is intentionally absent from the production app
closure.

For the required Google Sheets smoke test, materialize the reviewed formula
fixture, then import it with **File → Import → Upload**:

```bash
PAYROLL_WORKBOOK_COMPATIBILITY_ARTIFACT=.pi/tmp/payroll-workbook-compatibility/payroll_workbook-sheets-smoke.xlsx \
    bash ./bin/in-env hspec-pure --match "recalculates daily and accountant Summary formulas"
```

Confirm that Summary and daily Total formula cells display numeric values without
an import or formula error, including a non-zero `Sun 12+` Summary value.
Formatting need not be pixel-identical. Record the import date, Google Sheets
result, and any caveat on the implementing GitHub issue; do not commit transient
verification reports.

## Related Docs

- `SPEC.md` — durable authorization, payroll, and rendering contracts.
- `AGENTS.md` — editing and verification rules.
- `docs/workstreams/record-retention.md` — unresolved protected-record work.
