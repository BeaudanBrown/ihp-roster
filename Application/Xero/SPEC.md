# Xero Specification

This file records durable implemented contracts. Current symbols and request
shapes are authoritative in `Application/Xero/`, `Web/Controller/Admin/Xero/`,
the schema, and focused Xero tests. Future work belongs in
`docs/workstreams/xero-payroll.md`.

## Authorization And Boundaries

- Xero management is restricted to current-venue owners and founder super
  admins. Venue admins and managers have no Xero management authority.
- OAuth connect, callback, reconnect, and disconnect remain native
  session/full-page security flows. Tokens and provider payloads must not enter
  tracked fixtures, logs, progress text, or documentation.
- Application modules own API, service, and read-model behavior. Controllers own
  params, authorization responses, redirects, toasts, and HTMX fragments.
- The ordinary Xero page is a connection shell. Mapping, readiness, pay-item,
  preview, and submission decisions occur inside guided preparation; there is no
  venue-global payroll-calendar selection.

## Reference Data

- Every refresh path uses the same durable, connection-deduplicated reference
  job and background-safe persistence service. Work is leased per Xero tenant so
  concurrent refresh and token maintenance cannot race token rotation.
- Provider requests are sequential and paced. Earnings-rate pagination continues
  to a partial page, fails on a repeated full page with no new ids, and obeys the
  configured page limit. Structured rate limits honor valid `Retry-After`;
  bounded Xero-specific retries do not alter global job policy.
- Complete refreshes atomically reconcile provider availability. Failed pulls
  leave the previous complete snapshot intact. Provider availability is distinct
  from owner archival, and reappearance restores availability without changing
  local identity.
- A snapshot is trusted for seven days. Missing, stale, or approval-pinned
  missing-staff demand enqueues or joins refresh work; a still-trusted snapshot
  remains usable while maintenance retries. Suggested staff matches always need
  explicit owner approval.
- Owners cannot manually refresh reference data. Founder support may inspect
  bounded progress/failure facts and request the same coalescing refresh.
  Reauthorization-required state takes precedence over stale-data guidance.

The exact paging, lease, retry, and trust implementation is authoritative in
`ReferenceSyncJob.hs`, `Admin/ReferenceSyncPolicy.hs`, and `ReferenceTrust/`.

## Payroll Preparation And Submission

- Each preparation run explicitly selects one synced calendar and period. Only
  mapped employees assigned by Xero to that calendar are eligible.
- Readiness, proposals, preview, and submission use the same venue-effective
  rate resolution and strict wage-source boundary. Any included calculation or
  source failure blocks the complete operation.
- Submission consumes approved, locked Timesheet/pay facts. Every positive
  sealed earnings component is consumed exactly once; imported components retain
  their approval-pinned imported-item identity. Provider availability changes
  cannot reroute sealed components.
- Xero quantities preserve canonical sealed units and precision. Xero remains
  payroll, tax, and STP authority; Bepis does not calculate tax.
- Submitted entries require explicit correction/reversal behavior. Stable
  idempotency is tied to employee, selected period, and create/update target—not
  a transient local run.

Canonical calculation and bucket behavior lives in `Timesheets/Prepare.hs`,
`Timesheets/Buckets.hs`, `Timesheets/Preview.hs`, `Timesheets/Submission.hs`, and
their focused/golden tests.

## Live And Mutation Boundary

- Internal Xero services do not broadcast browser updates.
- `Web/Admin/Xero/Mutations.hs` is the web-facing invalidation boundary and
  returns typed touched-resource results.
- Background jobs publish typed resource invalidations without requiring request
  or current-user context. The retained shell depends only on its declared
  connection resource; guided preparation remains dialog-local.

## Provider Contracts

Official checksum-pinned OpenAPI sources and the explicitly named Payroll AU v2
supplement are the provider-contract evidence. Probe scripts are operator-only
diagnostics, must refuse CI/customer ambiguity, and emit structural facts rather
than tokens or payloads.

## Verification

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Xero"
bash ./bin/in-env e2e e2e/xero-timesheet-preparation.spec.ts e2e/xero-import-filter.spec.ts
```
