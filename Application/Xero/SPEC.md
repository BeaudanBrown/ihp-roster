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
- Managed Xero earnings-rate names put human payroll details first, e.g. `Saturday Penalty - Level 1 - CAS - Bepis - 1-July-2025`; legacy `Bepis - HIGA - ...` managed names remain matchable to avoid duplicate pay items.
- Managed award pay-item effective-date keys/names use the Bepis venue-effective
  rate date from the pay engine, not necessarily the raw FWC/MAPD operative
  date.
- Xero remains payroll, tax, and STP authority. Bepis does not calculate tax.

## Boundaries

- `Application/Xero/*` modules own API/service/read-model logic.
- `Web/Controller/Admin/Xero/*` owns params, redirects, toasts, HTMX/OOB
  responses, and permission response choices.
- Probe scripts are diagnostics; do not make production behavior depend on
  ad hoc probe output.

## Mutation And Live Invalidation Boundary

- `Application/Xero/Timesheets/{Prepare,Preview,Submission}.hs` are internal
  mutation services: they may write Xero preparation/submission records and
  perform Xero API orchestration, but they must not broadcast passive live
  updates directly.
- `Web/Admin/Xero/Mutations.hs` is the web-facing mutation boundary for Xero
  admin write flows. It wraps internal Xero services, returns
  `LiveMutationResult`, and calls touched-resource invalidation.
- Controllers in `Web/Controller/Admin/Xero/*` should not import Xero
  preparation/preview/submission services directly, except narrow domain types
  needed for request parsing.
- Background Xero jobs that mutate connection state should route passive
  invalidation through touched resources, not through direct live-surface
  broadcasts.

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
