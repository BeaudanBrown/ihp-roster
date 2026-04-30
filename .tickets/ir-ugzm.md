---
id: ir-ugzm
status: in_progress
deps: [ir-fv82]
links: []
created: 2026-04-30T01:11:39Z
type: task
priority: 1
assignee: beaudan
parent: ir-23k7
tags: [area:xero, area:admin, area:maintenance, source:2026-04-30-health-scan]
---
# Move Xero admin mutations into service modules

Move OAuth, sync, staff mapping, earnings mapping, pay-item, calendar, and readiness mutation orchestration behind service functions so the controller stays thin.

## Design

After the read-model extraction, move mutation logic out of controller actions in
small lanes:

- connection/OAuth disconnect and reconnect helpers.
- tenant/reference-data sync orchestration.
- staff mapping create/update/delete helpers.
- earnings mapping create/update/delete helpers.
- pay-item requirement create/update/retry helpers.
- payroll calendar selection helpers.
- readiness refresh helpers.

Each service function should own one domain operation and return a narrow result
that the controller can turn into a redirect, HTMX fragment, toast, or live
invalidation. Keep controller response formatting in the controller or a
response helper; keep Xero/domain mutation semantics in the service module.

Guardrails:

- Do not hide authorization: controller actions must still make venue/current
  user requirements explicit before calling services.
- Do not add generic "Xero admin service" bags with many unrelated functions in
  one module if narrower modules are clearer.
- Preserve existing audit/history rows and error messages unless a test proves
  the current text is wrong.

## Acceptance Criteria

- Xero admin action bodies validate input, call one or two named service
  functions, and choose a response.
- Mutation services are covered by focused Hspec tests for success, validation
  failure, Xero API failure, and idempotency/retry behavior where relevant.
- Existing Xero admin HTMX and full-page flows still emit the same redirects,
  fragments, and toasts.
- `bash ./bin/in-env typecheck` and focused Xero Hspec/Playwright tests pass.

## Notes

**2026-04-30T01:40:21Z**

Extracted reference-data upsert/stale helpers into Application.Xero.Admin.ReferenceData and pay-item create/verification orchestration into Application.Xero.Admin.PayItems. Controller still owns response formatting for this slice. Verified with bash ./bin/in-env typecheck and bash ./bin/in-env hspec-test --match "Xero".
