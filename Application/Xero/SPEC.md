# Xero Specification

This file records durable implemented contracts. Current symbols and request
shapes are authoritative in `Application/Xero/`, `Web/Controller/Admin/Xero/`,
the schema, and focused Xero tests. Future behavior requires a current GitHub
issue and, when cross-system design remains unresolved, a new workstream.

## Authorization And Boundaries


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
  belong to the guided preparation workflow. The staff-selection AppShell action
  is nominal: it carries staff identity plus one provider-owned employee
  selection and has no second text decision discriminator. The pre-wizard
  preview, submit, and retry endpoints are retired.
- App-owned Xero sync, staff/earnings mapping, account-code selection, managed
  pay-item requirement, preparation run/decision, submission run/source, and
  per-staff submission state persists as PostgreSQL enums. Production decisions
  use generated constructors and exhaustive projections from
  `Application.Xero.WorkflowState`; raw enum text appears only at database,
  HTML, telemetry, or other external wire boundaries. Xero-owned employee,
  account, pay-run, and timesheet status vocabulary remains open `Text` and is
  preserved unchanged, including unknown future provider values.
- Every reference-sync path uses the same background-safe persistence and
  reconciliation service. Complete bulk refresh can run as a durable `app_jobs`
  job, coalesced per connection and leased per Xero tenant. Provider requests
  are sequential and paced to 50 requests/minute. Earnings-rate reads use the
  paginated Payroll AU v2 `/earningsRates` endpoint, matching the existing v2
  earnings-rate creation boundary. Pagination continues until a partial page, rejects a
  repeated full page that adds no new ids, and stops at the runtime-configurable
  `XERO_EARNINGS_RATES_MAX_PAGES` safety limit (default 1000). Structured 429
  handling honors valid `Retry-After`, while transient
  failures use Xero-specific jittered continuations for at most 24 hours without
  changing unrelated job retry policy. Progress and errors contain phase/page
  facts only, never tokens or raw provider payloads.
- Successful OAuth connection or same-tenant repair transactionally enqueues
  one coalescing reference-sync job and redirects directly to the Xero shell;
  reference refresh never depends on a browser page-load trigger. The daily
  maintenance sweep independently evaluates `lastSyncAt` for a six-day
  reference refresh and `lastRefreshedAt` for seven-day token keepalive. All
  reference requests reuse the durable connection dedupe and tenant lease;
  keepalive shares that tenant lease so simultaneous due jobs cannot race
  refresh-token rotation, while each job retains independent success/failure.
  Lease contention uses the existing keepalive worker retries; an expired or
  revoked token instead completes in reconnect-required state and does not loop.
- Import and preparation resolve typed snapshot trust before job state. A
  snapshot remains trusted for seven days and opens immediately even while its
  six-day maintenance refresh is queued, running, retrying, or failed. Missing,
  stale, or newly payroll-eligible missing-staff demand enqueues or joins the
  durable job. When that attempt receives a provider `Retry-After`, a still-trusted
  snapshot opens the mapping workflow rather than making preparation wait for the
  delayed background retry. Subscribed live waiting dialogs show canonical
  phase/page facts and resume from local reference rows only after typed
  sync-state invalidation.
- Missing-staff demand resolves approval-pinned pay versions through the
  canonical explicit pay-assignment resolver. Successful snapshots stamp
  unresolved staff mappings as checked. When no mapping row exists yet, or an
  unresolved placeholder is created after that snapshot, the newer of the
  mapping refresh and connection snapshot times proves whether the approval has
  already been checked and prevents repeated preparation observations from
  enqueueing the same refresh. The persisted approval mutation time, not a
  future-dated payroll approval value or later mutable staff edit, determines
  whether another mapping refresh is required. Effective `roster_only` work
  does not request Xero data or block eligible payroll work.
  Suggested staff matches remain pending until explicit owner approval. In the
  preparation dialog, unmatched staff default to Not paid through Xero without
  an immediate write; Continue persists those defaults while approving all
  unchanged suggestions. Manual dropdown changes save immediately.
- Owners do not receive or access manual reference refresh. Founder support sees
  last success, aggregate queued/running/retry-chain state, retry timing,
  canonical progress and sanitized failure, and may request the same coalescing
  refresh. Reauthorization-required state takes precedence over stale-data
  support guidance.
- A complete successful snapshot atomically marks missing or provider-inactive
  employees, earnings rates, calendars, accounts, and imported pay items
  unavailable; reappearance restores provider availability without changing
  local identity. Failed pulls leave the prior availability snapshot untouched.
- Provider availability is separate from owner archival. Unavailable imported
  pay items stay queryable for immutable pay versions and sealed calculations,
  but are excluded from new imports and current assignment selectors. Current
  explicit `xero_rate` assignments require remediation; `roster_only` and
  `staff_default` do not. Approved entries pinned to unavailable rates block
  Xero preparation with the explicit correction/reapproval path.
- Offline request contracts use checksum-pinned, unmodified official Identity,
  Payroll AU v1/v2, and Accounting OpenAPI files from one upstream commit.
  Payroll AU v2 Earnings Rates reads and creation lack official upstream
  operations; their separately named local supplement records documentation
  provenance, pagination, and explicit response-shape assumptions.
- Synced payroll calendars are retained reference data. Calendar and period
  choice is explicit on each guided preparation run; no global
  `xero_payroll_calendar_selections` fallback is read or written.
- A selected preparation period includes only mapped Xero employees whose
  synced payroll-calendar assignment exactly matches that period's calendar.
  Employees assigned to another calendar or to no calendar are excluded from
  that period rather than sent to Xero's Timesheets API. The modal summary,
  readiness counts, preview, and submission all use this same eligible set.
  Preparation summary units use locked approved pay facts. Xero selects entries
  by Operational date and allocates every component's units to that Operational
  date in the provider period array while retaining the component-date-derived
  earnings-rate line. Provider period dates remain submission-range authority;
  they do not redefine Bepis pay-window ownership. Hourly quantities aggregate
  without quarter-hour rounding, commenced-hour quantities remain whole, and
  protocol serialization uses 12 decimal places.
- Managed Xero earnings-rate names put human payroll details first, e.g. `Saturday Penalty - Level 1 - CAS - Bepis - 1-July-2025`; legacy `Bepis - HIGA - ...` managed names remain matchable to avoid duplicate pay items. Pay-item approval recreates any missing current-run proposal decisions before applying them, so incomplete decision persistence cannot trap the modal on the approval step.
- Preview/submission consumes every positive sealed earnings component exactly
  once. Managed requirements reserve separate `RATEPERUNIT` evening and
  early-morning commenced-hour additions and a separate missed-meal-break 50%
  addition per classification/effective rate. Base ordinary, weekend and public
  holiday components remain hourly; minimum top-ups merge into those hourly
  buckets. Imported components resolve through the imported-item id locked in
  the approved staff/shift pay version and require no managed Award mapping.
  Imported-item venue, connection and remote earnings-rate identity are database
  immutable; refresh may update display/rate/freshness metadata but cannot reroute
  a sealed component to another Xero earning rate. Approved entries pinned to an
  imported item from a previous venue connection are preserved but excluded from
  readiness counts, preview, and submission with one visible warning. Other
  eligible entries continue; a period containing only excluded entries remains
  blocked from creating an empty submission.
- Readiness, managed pay-item proposals, preview, and submission resolve overlapping projected rates through the same latest venue-effective-rate rule as payroll calculations. Raw FWC operative dates are normalized to the venue week before constructing bucket keys.
- Managed award pay-item effective-date keys/names use the Bepis venue-effective
  rate date from the pay engine, not necessarily the raw FWC/MAPD operative
  date. Projection provenance comes only from the typed WageEngine source
  identity renderer. Effective-date recovery matches the stable projection-row
  portion of a sealed source identity, so a later append-only MAPD refresh may
  repoint that row without invalidating approved facts; the exact sealed raw
  source identity and rate remain unchanged in the resulting key.
  `Application.Xero.PayrollSourceKey` owns that exact source/rate suffix.
- Xero remains payroll, tax, and STP authority. Bepis does not calculate tax.
- Readiness, persisted preview, direct submission, retry, and guided preparation
  use the shared strict wage-source enforcement boundary. Any included entry's
  calculation or source failure blocks the complete operation; imported overrides
  bypass FWC/DataVic freshness only with a valid imported pay item.


## Reference Data


- `Application/Xero/*` modules own API/service/read-model logic. Ordinary page
  reads load connection state only; preparation-specific reads run after the
  workflow is launched.
- `Web/View/Admin/Xero/TimesheetPreparation.hs` owns workflow/dialog
  orchestration. Its `StaffMappings` module owns mapping attention, selection,
  and rendering through three focused interfaces; its `Review` module owns the
  complete review and preview projections through two rendering interfaces.
  Controllers continue to consume only the established top-level view interface.
- `Web/Controller/Admin/Xero/*` owns params, redirects, toasts, HTMX/OOB
  responses, and permission response choices.
- Probe scripts are diagnostics; do not make production behavior depend on
  ad hoc probe output. The Payroll AU v2 Earnings Rates gap probe is operator-only,
  read-only, refuses CI, requires an exact tenant-id gate, and emits structural
  response facts rather than customer/provider payloads.


The exact paging, lease, retry, and trust implementation is authoritative in
`ReferenceSyncJob.hs`, `Admin/ReferenceSyncPolicy.hs`, and `ReferenceTrust/`.

## Payroll Preparation And Submission

- Each preparation run explicitly selects one synced calendar and period. Only
  mapped employees assigned by Xero to that calendar are eligible. The period
  selector shows every eligible past and future period and selects the newest
  non-posted option by default. Selecting a period checks its current Xero pay
  run without downloading remote timesheet history. After concise owner
  confirmation, submission performs one fresh reconciliation read and
  immediately creates or updates safe drafts from that state; unsafe provider
  states block before writes. Every remote reconciliation read uses the Payroll
  AU v2 timesheet endpoint scoped to the selected payroll calendar and period.
  The initial read omits the optional `page` query parameter because live Xero
  returns 400 for an explicitly requested empty page 1; later full-result pages
  use page 2 onward.
- Readiness, proposals, preview, and submission use the same venue-effective
  rate resolution and strict wage-source boundary. Any included calculation or
  source failure blocks the complete operation.
- Submission consumes approved, sealed Timesheet/pay facts. Approval seals the
  Operational date, Bepis roster-window boundary/start day, component date,
  source, exact amount, local earnings bucket, and provider EarningsRateID when
  an active Xero connection has an available mapping. A missing approval-time
  mapping remains blocked after later mapping changes until the entry is
  unapproved and reapproved. Every positive sealed earnings component is consumed
  exactly once; imported components retain
  their approval-pinned imported-item identity. Provider availability changes
  cannot reroute sealed components. Submission source links retain immutable audit
  snapshots but do not lock Timesheet entries; corrected entries reset approval and
  enter Xero only after reapproval and a fresh preparation.
- An effective staff-level imported Xero rate maps that staff member's imported
  components to the one approval-pinned Xero earnings rate; an explicit shift
  override still follows the shared pay-assignment precedence. Imported-rate
  selectors present the human Xero name before account-code metadata.
- Xero quantities preserve canonical sealed units and precision. Every positive
  component is placed in the provider period position for the Timesheet entry's
  local start day, keeping an overnight shift whole while actual component dates
  remain authoritative for rates, conditions, public holidays, breaks, and DST.
  Preview fails closed if that ownership day is outside the selected period. Xero
  remains payroll, tax, and STP authority; Bepis does not calculate tax.
- A fresh preparation may update a matching Xero draft after local entries are
  corrected and reapproved. Bepis does not delete or clear a prior Xero draft when
  an employee no longer has approved local entries; owners resolve obsolete drafts
  in Xero. Each persisted provider mutation receives a bounded idempotency key
  derived from its immutable local submission identity and operation sequence.
  Re-entering that exact persisted operation reuses its key; a fresh preparation
  or recovery transition to a different provider operation receives a new key.
  Legacy employee/period keys fail closed after deployment and require fresh
  preparation rather than risking reuse across independent draft updates.
- Provider outcomes that cannot be confirmed are recorded as failed with explicit
  check-Xero guidance; persisted payloads are never replayed. Fresh preparation is
  the only retry path. A pending reservation blocks concurrent writes for two
  minutes, after which the next reconciliation fails it as abandoned and proceeds
  from fresh provider state.

Canonical calculation and bucket behavior lives in `Timesheets/Prepare.hs`,
`Timesheets/Buckets.hs`, `Timesheets/Preview.hs`, `Timesheets/Submission.hs`, and
their focused/golden tests.

## Live And Mutation Boundary

- Internal Xero services do not broadcast browser updates.
- `Web/Admin/Xero/Mutations.hs` is the web-facing invalidation boundary and
  returns typed touched-resource results.
- Background reference-sync requests and jobs publish the dedicated typed
  reference-sync-state resource for queued, progress, retry, skipped, success,
  and failure transitions without requiring request or current-user context.
  The retained shell depends only on its connection resource. Its nested
  read-only diagnostics fragment and dialog-local preparation and pay-item import
  wait fragments depend on the sync-state resource; reconnect/version-gap resync
  refetches the same canonical venue-scoped state. Opening either workflow may
  request sync once, while every later wait-fragment read remains side-effect-free.
  Progress, retry, failure, and trusted completion replace the mounted dialog
  fragment only after sync-state invalidation. Trusted preparation completion
  performs one separate preparation mutation; trusted import completion renders
  candidates directly from local reference rows.

## Provider Contracts

Official checksum-pinned OpenAPI sources and the explicitly named Payroll AU v2
supplement are the provider-contract evidence. Probe scripts are operator-only
diagnostics, must refuse CI/customer ambiguity, and emit structural facts rather
than tokens or payloads.

## Verification

```bash
bash ./bin/in-env http-polling-policy-check
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Xero"
bash ./bin/in-env e2e e2e/xero-timesheet-preparation.spec.ts e2e/xero-pay-item-import.spec.ts e2e/xero-import-filter.spec.ts
```
