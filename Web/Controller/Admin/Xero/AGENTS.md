# Admin Xero Controller Agent Notes

Read this before editing Xero admin controller submodules.

## Local Rules

- Controllers own request params, permission response choices, redirects,
  toasts, and HTMX/OOB response shape.
- Application logic belongs in `Application/Xero/` or focused helpers.
- Keep access owner/super-admin only.
- Preserve Xero OAuth/security flows as full-page native requests unless a
  ticket explicitly requires HTMX.

## Common Changes

- Connection actions belong in `Connection.hs`.
- Staff/pay item mapping actions belong in `Mappings.hs`.
- Pay item mutation response wiring belongs in `PayItemMutations.hs`.
- Reference sync actions belong in `ReferenceSync.hs`.
- Timesheet preview/submission actions belong in `Timesheets.hs`.
- Shared controller response helpers belong in `Responses.hs`.

## Verification

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Xero"
```
