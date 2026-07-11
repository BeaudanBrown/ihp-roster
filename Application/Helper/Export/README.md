# Export Helpers

## Purpose

`Application/Helper/Export/` owns the fixed export catalog, read models,
payload construction, rendering, persistence, download authorization, and
controller-facing orchestration.

## Modules

- `Types.hs` - fixed-export domain types and conversions.
- `Render.hs` - CSV/ZIP rendering and pure formatting.
- `Definitions.hs` - default date ranges and week slicing.
- `ReadModel.hs` - export read queries.
- `Payloads.hs` - fixed-export payload construction.
- `Persistence.hs` - job persistence, expiry, download authorization, audit.
- `Service.hs` - controller-facing orchestration.
- `Application/Helper/Export.hs` - compatibility re-export facade.

## Related Docs

- `SPEC.md`
- `AGENTS.md`
- `docs/workstreams/pay-config-versioning.md`
- `docs/workstreams/xero-payroll.md`
- `docs/workstreams/record-retention.md`
- `docs/archive/plans/45-payroll-report-exports.md`
