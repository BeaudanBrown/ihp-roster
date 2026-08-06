# Export Helpers

## Ownership

`Application/Helper/Export/` owns the fixed export catalog, venue-scoped read
models, payload construction, safe rendering, export-job persistence, expiry,
download authorization, and controller-facing orchestration.

## Start Here

- `Service.hs` — controller-facing generation and download boundary.
- `Types.hs` and `Definitions.hs` — fixed catalog and date/week rules.
- `ReadModel.hs` and `Payloads.hs` — authoritative export inputs and payloads.
- `Render.hs` — CSV/ZIP formatting and output safety.
- `Persistence.hs` — job lifecycle, authorization, and audit.
- `Application/Helper/Export.hs` — compatibility facade only.

## Related Docs

- `SPEC.md` — durable authorization, payroll, and rendering contracts.
- `AGENTS.md` — editing and verification rules.
- `docs/workstreams/pay-config-versioning.md`,
  `docs/workstreams/xero-payroll.md`, and
  `docs/workstreams/record-retention.md` — unresolved cross-system work.
