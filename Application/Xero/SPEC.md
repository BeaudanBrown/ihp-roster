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
- Imported-pay-item candidate filtering receives one opaque normalized
  name/account-code search projection in an exact Haskell-rendered config.
  Browser code validates that boundary, then performs only root-local generic
  matching and visibility; earnings-rate ids, checkbox
  fields, validation, and import mutations remain server-owned.
- The Xero page is a minimal connection shell. It may start reference sync,
  open the imported-pay-item dialog, or launch guided timesheet preparation,
  but it must not load or render standalone staff-mapping, earnings-mapping,
  calendar, readiness, pay-item, or legacy timesheet panels.
- Staff decisions, managed pay items, readiness checks, preview, and submission
  belong to the guided preparation workflow. The pre-wizard preview, submit,
  and retry endpoints are retired.
- Manual reference sync and preparation use the same application service and
  persistence/reconciliation path.
- Offline request contracts use checksum-pinned, unmodified official Identity,
  Payroll AU v1/v2, and Accounting OpenAPI files from one upstream commit. The
  only application API operation without an official upstream operation is
  Payroll AU v2 Earnings Rates creation; its separately named local supplement
  records documentation provenance and explicit response-shape assumptions.
- Synced payroll calendars are retained reference data. Calendar and period
  choice is explicit on each guided preparation run; no global
  `xero_payroll_calendar_selections` fallback is read or written.
- A selected preparation period includes only mapped Xero employees whose
  synced payroll-calendar assignment exactly matches that period's calendar.
  Employees assigned to another calendar or to no calendar are excluded from
  that period rather than sent to Xero's Timesheets API. The modal summary,
  readiness counts, preview, and submission all use this same eligible set.
  Preparation summary units use locked approved pay facts. Xero request hourly
  quantities aggregate by employee, managed earning bucket and local day, then
  round once to the nearest quarter hour with exact 7.5-minute ties up.
  Commenced-hour quantities remain whole. Protocol serialization uses 12 decimal
  places only after that output transform.
- Managed Xero earnings-rate names put human payroll details first, e.g. `Saturday Penalty - Level 1 - CAS - Bepis - 1-July-2025`; legacy `Bepis - HIGA - ...` managed names remain matchable to avoid duplicate pay items.
- Preview/submission consumes every positive sealed earnings component exactly
  once. Managed requirements reserve separate `RATEPERUNIT` evening and
  early-morning commenced-hour additions and a separate missed-meal-break 50%
  addition per classification/effective rate. Base ordinary, weekend and public
  holiday components remain hourly; minimum top-ups merge into those hourly
  buckets. Imported components resolve through the imported-item id locked in
  the approved staff/shift pay version and require no managed Award mapping.
  Imported-item venue, connection and remote earnings-rate identity are database
  immutable; refresh may update display/rate/freshness metadata but cannot reroute
  a sealed component to another Xero earning rate.
- Readiness, managed pay-item proposals, preview, and submission resolve overlapping projected rates through the same latest venue-effective-rate rule as payroll calculations. Raw FWC operative dates are normalized to the venue week before constructing bucket keys.
- Managed award pay-item effective-date keys/names use the Bepis venue-effective
  rate date from the pay engine, not necessarily the raw FWC/MAPD operative
  date.
- Xero remains payroll, tax, and STP authority. Bepis does not calculate tax.
- Readiness, persisted preview, direct submission, retry, and guided preparation
  use the shared strict wage-source enforcement boundary. Any included entry's
  calculation or source failure blocks the complete operation; imported overrides
  bypass FWC/DataVic freshness only with a valid imported pay item.

## Boundaries

- `Application/Xero/*` modules own API/service/read-model logic. Ordinary page
  reads load connection state only; preparation-specific reads run after the
  workflow is launched.
- `Web/Controller/Admin/Xero/*` owns params, redirects, toasts, HTMX/OOB
  responses, and permission response choices.
- Probe scripts are diagnostics; do not make production behavior depend on
  ad hoc probe output. The Payroll AU v2 Earnings Rates gap probe is operator-only,
  read-only, refuses CI, requires an exact tenant-id gate, and emits structural
  response facts rather than customer/provider payloads.

## Mutation And Live Invalidation Boundary

- `Application/Xero/Timesheets/{Prepare,Preview,Submission}.hs` are internal
  mutation services: they may write Xero preparation/submission records and
  perform Xero API orchestration, but they must not broadcast passive live
  updates directly.
- `Web/Admin/Xero/Mutations.hs` is the web-facing invalidation boundary for
  Xero admin write flows. It wraps internal Xero services, returns
  `LiveMutationResult`, and calls touched-resource invalidation.
- `Application/Xero/Admin/ReferenceData.hs` owns the single reference-sync
  transaction path used by the manual action and preparation.
- Controllers in `Web/Controller/Admin/Xero/*` should not import Xero
  preparation/preview/submission services directly, except narrow domain types
  needed for request parsing.
- Background Xero jobs that mutate connection state should route passive
  invalidation through touched resources, not through direct live-surface
  broadcasts.
- The retained Xero live shell depends only on its declared connection
  resource. Guided timesheet preparation mutations are dialog-local and emit no
  Surface resource; do not recreate the retired undeclared Xero mappings,
  pay-items, or timesheets sentinel resources, which selected no live target.

## Timesheet Submission Direction

- Submission must use approved, locked timesheet/pay facts.
- Preview and submission should record the entries and pay-version context they
  include.
- Submitted entries need explicit correction/reversal behavior rather than
  silent destructive edits. Submission idempotency keys are stable for the
  employee, selected period and create/update target rather than varying by local
  run id.
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
bash ./bin/in-env e2e e2e/xero-timesheet-preparation.spec.ts e2e/xero-import-filter.spec.ts
```
