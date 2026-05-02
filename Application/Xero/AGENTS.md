# Xero Agent Notes

Read this before editing `Application/Xero/` or Xero application helpers.

## Local Rules

- Read `SPEC.md` and the relevant workstream first.
- Keep application modules free of web response concerns.
- Put controller params, redirects, HTMX fragments, and toast response choices
  in `Web/Controller/Admin/Xero/`.
- Keep Xero management owner/super-admin only unless the ticket explicitly
  changes authorization.
- Keep token material out of tracked fixtures and docs.

## Gotchas

- Older archived plans mention venue-admin access; current behavior is
  owner/super-admin only.
- Real Xero API behavior can differ from the OpenAPI shape. Preserve contract
  probes as diagnostics, but harden local request construction with tests.
- Xero payroll submission must not bypass pay-version locking.

## Verification

Run focused Xero Hspec after application or controller changes. Use E2E for
admin readiness/mapping flows.
