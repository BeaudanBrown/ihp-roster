# Xero Specification

This file describes implemented Xero integration behavior. Future Payroll AU
submission behavior belongs in `docs/workstreams/xero-payroll.md` until it
lands.

## Current Contract

- Xero management is restricted to current venue owners and super admins.
- Venue admins and managers must not manage Xero connection or payroll
  integration surfaces unless a future product decision changes access.
- OAuth connect/reconnect/callback/disconnect flows are low-frequency security
  flows and should remain native full-page/session flows unless a specific
  ticket requires in-place behavior.
- Xero reference-data and pay-item operations are venue-scoped.
- Xero remains payroll, tax, and STP authority. Bepis does not calculate tax.

## Boundaries

- `Application/Xero/*` modules own API/service/read-model logic.
- `Web/Controller/Admin/Xero/*` owns params, redirects, toasts, HTMX/OOB
  responses, and permission response choices.
- Probe scripts are diagnostics; do not make production behavior depend on
  ad hoc probe output.

## Timesheet Submission Direction

- Submission must use approved, locked timesheet/pay facts.
- Preview and submission should record the entries and pay-version context they
  include.
- Submitted entries need explicit correction/reversal behavior rather than
  silent destructive edits.
- Staff-level Xero pay item overrides are tracked in
  `docs/workstreams/rooks-pilot.md`.

## Extension Rules

- Keep token material out of tracked source and deterministic seeds.
- Do not broaden Xero visibility without updating tests and access-control
  specs.
- Prefer strict local contract tests/mocks for request construction before
  touching real Xero endpoints.

## Verification

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Xero"
bash ./bin/in-env e2e e2e/xero-staff-mapping.spec.ts
```
