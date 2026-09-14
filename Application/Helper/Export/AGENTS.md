# Export Agent Notes

Read this before editing fixed export helpers or export tests.

## Local Rules

- Keep `Application/Helper/Export.hs` as a compatibility facade.
- Add implementation to the narrowest module under `Application/Helper/Export/`.
- Route all CSV output through `Render.csvCell`.
- Keep export authorization, expiry, download checks, and audit wiring in
  `Persistence.hs`/`Service.hs`, not controllers.
- Preserve golden output stability unless the ticket explicitly changes the
  export contract.

## Gotchas

- Managers are denied export generation/download despite superseded proposals.
- ZIP contents are base64 in `export_jobs.file_contents`.
- `day_names.weekday_index` is real SQL weekday numbering; report columns must
  still follow the selected week order.
- Do not reintroduce report-definition lookup, bootstrap, or filtering. The
  tables are absent from the [current schema](../../Schema.sql);
  [migration 1783899114](../../Migration/1783899114.sql) records their retirement
  with operator/backup gates. This is not deployment evidence and does not
  retire callable fixed exports or historical download/recovery contracts.

## Verification

Run focused export Hspec and exact CSV/ZIP comparisons. Use E2E for workflow
coverage after behavior changes.
