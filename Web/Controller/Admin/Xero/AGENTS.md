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
- Imported pay-item dialog actions belong in `ImportedPayItems.hs`.
- Reference sync actions belong in `ReferenceSync.hs` and call the shared
  application service.
- Guided preparation actions belong in `Timesheets.hs`; do not recreate
  standalone mapping/readiness panels or pre-wizard preview/submit/retry routes.
- Shared controller response helpers belong in `Responses.hs`.

## Verification

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Xero"
```
