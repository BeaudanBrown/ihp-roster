# Pipeline 57 - Xero Payroll Integration

Read after `IMPLEMENTATION_PLAN.md`, `plans/30-timesheets-and-leave.md`,
`plans/40-pay-config-and-admin.md`, `plans/45-payroll-report-exports.md`, and
`plans/55-record-retention-soft-deletion.md`.

## Goal

Integrate `ihp-roster` with Xero Payroll AU so venue managers can send approved,
snapshot-pinned IHP timesheet hours into Xero as draft payroll timesheets.

The first production shape should keep Xero as the payroll and compliance system
of record. IHP should own rostering, attendance, approval, award interpretation,
and audit-friendly hour breakdowns; Xero should own employee payroll identity,
tax, super, STP, pay runs, payslips, and final payroll review.

## Product Direction

The first integration should behave like a conventional rostering/payroll
connector:

- a venue connects one Xero organisation/tenant
- staff in IHP are mapped to existing Xero payroll employees
- IHP proposes and provisions the small set of Xero earnings-rate pay items
  needed for the venue's award conditions before timesheet export
- IHP pay buckets are mapped to the resulting Xero earnings rates
- optional roster/shift grouping can map to Xero tracking items later
- approved IHP timesheets are transformed into Xero timesheet lines
- generated Xero timesheets are submitted as `DRAFT`
- the client or bookkeeper reviews and runs payroll inside Xero

Pay item setup is now part of the first practical milestone. Relying on every
small venue or bookkeeper to pre-create the correct award pay items in Xero makes
the connector too fragile in practice. Employee creation and payroll-calendar
configuration should remain Xero-side/manual for the first milestone, but
earnings-rate pay items should be admin-reviewed and provisioned from the award
data IHP already syncs.

## Xero API Surface

The initial target is Xero Payroll AU:

- OAuth 2.0 connection flow with `offline_access`
- connected tenant lookup and storage of the selected `Xero-Tenant-Id`
- `GET /Employees` for payroll employee mapping
- `GET /PayItems` for earnings-rate mapping
- `POST /PayItems` for admin-reviewed earnings-rate provisioning
- `GET /PayrollCalendars` for pay-period validation
- `GET /Timesheets` for duplicate/update detection
- `POST /Timesheets` to create draft timesheets
- `POST /Timesheets/{TimesheetID}` to update draft timesheets when safe

Required Xero scopes for the first useful version are expected to include:

- `offline_access`
- `payroll.employees.read`
- `payroll.settings` for pay-item reads and admin-reviewed pay-item creation
- `payroll.timesheets`
- possibly `payroll.timesheets.read` if not implied by the write scope in the
  active Xero app configuration

Do not request employee write scopes until the app has a specific employee setup
feature that needs them.

## Existing IHP Fit

The app already has most of the internal source data needed:

- `timesheet_entries` are venue-scoped, soft-deletable, and approval-gated.
- approval pins `pay_config_snapshot_id`, so exported payroll output remains
  explainable after later config changes.
- `timesheet_entry_versions` and `audit_events` already record payroll-adjacent
  mutations.
- `export_jobs` already model generation, expiry, file metadata, and audit.
- `PayrollEarningsCsv` already aggregates approved entries into staff/date,
  earnings-rate-like name, hours, tracking code, source entry IDs, and pay
  snapshot version.

The Xero integration should reuse this calculation/export foundation instead of
building a separate payroll calculation path.

## Pay Item Strategy

As of 2026-04-28, the planned Xero earnings-rate strategy is:

- Use Xero `MULTIPLE` earnings rates for penalties that are stable multipliers
  of the employee's ordinary earnings rate.
- Use Xero `RATEPERUNIT` earnings rates for flat hourly loadings that IHP stores
  as a dollar amount per hour.
- Avoid classification-specific pay items unless a live Xero tenant test proves
  that a required condition cannot be represented by one of those two shapes.

Expected first-pass pay items for a typical small venue are roughly:

- `Ordinary Hours`
- `Saturday Penalty` as `MULTIPLE`
- `Sunday Penalty` as `MULTIPLE`
- `Public Holiday` as `MULTIPLE`
- later overtime buckets such as `Overtime 1.5x` and `Overtime 2.0x`
- `Evening after 7pm` as `RATEPERUNIT`
- `Late night after midnight` as `RATEPERUNIT`

This should usually keep the Xero pay item set around 6-10 earnings rates. The
fallback `classification x condition` model can easily produce 30-60+ pay items
and should be avoided unless Xero forces it.

Current evidence:

- Xero Payroll AU employees expose `OrdinaryEarningsRateID`.
- Xero earnings rates expose `RateType`, `Multiplier`, and `RatePerUnit`.
- Xero timesheet lines carry `EarningsRateID` and `NumberOfUnits`, so ad hoc
  line rates cannot be sent directly from IHP.
- IHP currently stores weekend/public-holiday penalties as full hourly rates per
  award level, which can be converted to multipliers when the ratio is stable.
- IHP stores evening/late-night penalties as `base_rate + hourly_amount`, so
  those should be sent as separate rate-per-unit loading lines rather than
  classification-specific effective-rate lines.

Manual verification still required before production submission:

- create a `RATEPERUNIT` evening loading earnings rate in a payroll-enabled Xero
  AU tenant
- create a draft timesheet with ordinary hours and a matching evening-loading
  line for the same hours
- confirm Xero accepts the timesheet and the generated payslip/pay-run lines
  calculate, tax, super, and report as expected

## Data Model Additions

### Xero connections

Add a venue-scoped connection table, likely `xero_connections`:

- `venue_id`
- `tenant_id`
- `tenant_name`
- `connection_status`
- `scopes`
- encrypted refresh token material
- optional encrypted access token material
- access token expiry
- last refresh timestamps
- last sync timestamps
- disconnect/reconnect/error fields
- connected/disconnected actor fields

Token material must not be stored in plaintext. If app-level encryption is not
already available, add a narrow encrypted-secret helper before persisting live
OAuth credentials.

### Staff mapping

Add `xero_staff_mappings`:

- `venue_id`
- `staff_id`
- `xero_employee_id`
- `xero_employee_name`
- `xero_employee_email`
- mapping status
- last verified timestamp
- source metadata from the most recent Xero employee sync

Prefer explicit manager/admin review before mapping a staff row to a Xero
employee. Name/email auto-suggestions are useful, but silent employee matching is
too risky for payroll.

### Earnings-rate mapping

Add `xero_earnings_rate_mappings`:

- `venue_id`
- local payroll bucket key
- local display label
- optional local pay level / penalty kind / employment basis fields
- `xero_earnings_rate_id`
- Xero earnings rate name
- mapping status
- last verified timestamp

The local bucket key should be stable and derived from the same facts used by
`PayrollEarningsCsv`: pay level, penalty kind, and any other configured payroll
classification that affects the Xero earnings rate.

### Pay item provisioning

Add a durable model for IHP-required Xero earnings-rate pay items before draft
timesheet preview:

- venue and Xero connection
- local requirement key
- display name and source penalty kind
- expected Xero earnings type
- expected Xero rate type: `MULTIPLE` or `RATEPERUNIT`
- expected multiplier or rate-per-unit amount
- expected tax/super/reporting flags where the app can infer safe defaults
- provisioning status: proposed, matched, created, stale, ignored
- linked Xero earnings rate id/name after match or creation
- last verified timestamp and actor metadata
- raw request/response payloads for created pay items

The requirement key should be coarser than the existing pay-level bucket mapping
when Xero can represent the pay condition globally. Prefer one Xero pay item per
condition/rate formula, not one per award classification.

### Optional tracking mapping

Add later if needed: `xero_tracking_item_mappings` for shift type, roster group,
or venue-defined cost centre to Xero `TrackingItemID`.

Do not block the first timesheet export on tracking categories unless the first
client requires cost-centre reporting in Xero payroll.

### Submission runs

Add `xero_submission_runs` and `xero_timesheet_submissions`, or an equivalent
extension of `app_jobs`, to capture:

- venue and connection
- requested actor
- week/pay period
- source approved `timesheet_entry_ids`
- generated request payload
- Xero response payload
- idempotency key
- Xero `TimesheetID`
- status: previewed, pending, submitted, failed, skipped, superseded
- retry count and error detail

This state should be separate from `export_jobs`; Xero submission is an external
side effect, not just a downloadable generated file.

## Current Implementation Status

As of 2026-04-28, the implementation has moved beyond the original connection
foundation text:

### Implemented

- Xero OAuth connection, callback state validation, encrypted token storage,
  tenant storage, reconnect, and disconnect are implemented under the Admin
  Xero section.
- Xero connection management is restricted to the venue owner account. Venue
  admins can view and use the already-connected integration where appropriate,
  but cannot start, reconnect, or disconnect the OAuth connection.
- Refresh-token handling is shared across sync/disconnect/keepalive flows.
  Expired or revoked refresh tokens mark the connection as
  `reauthorization_required`; transient refresh errors mark the connection
  `error`.
- A NixOS `systemd.timer`-backed keepalive sweep enqueues app jobs for active
  Xero connections whose refresh token has not been exercised recently.
- The Admin Xero section uses the declarative live-fragment flow
  (`AdminXeroScope` / `AdminXeroFragment`) for in-place sync and mapping updates.
- Read-only payroll reference sync exists for:
  - Xero employees, stored in `xero_employees`
  - Xero earnings rates, stored in `xero_earnings_rates`
  - Xero payroll calendars, stored in `xero_payroll_calendars`
  - sync run status/counts/errors, stored in `xero_sync_runs`
- Staff-to-Xero-employee mapping exists through `xero_staff_mappings`, including
  `unmapped`, `verified`, `not_applicable`, and `stale` states.
- Local earning-bucket-to-Xero-earnings-rate mapping exists through
  `xero_earnings_rate_mappings`.
- Venue payroll-calendar selection exists through
  `xero_payroll_calendar_selections`.
- The Admin Xero section shows a ready-to-submit checklist covering connection,
  reference sync, staff mappings, earnings mappings, and payroll calendar
  selection.
- The staff mapping UI is hidden for venues without a linked Xero connection and
  only becomes actionable after employee reference data has been synced.
- The dev seed script can replay a local ignored Xero connection SQL dump from
  `build/dev-xero-connection.sql` or `$DEV_XERO_SEED_FILE` after `seed-dev`.
- Hspec coverage exists for connection state, reference sync, staff mappings,
  token-refresh failure handling, reconnect preservation, disconnect, and
  keepalive jobs with a mocked Xero client.

### Not Yet Implemented

- Deterministic Xero pay item requirements are now derived from active award
  data, persisted in `xero_pay_item_requirement_records`, and shown in the
  Admin Xero section. The preview classifies stable weekend/public-holiday
  ratios as `MULTIPLE` requirements, flat time allowances as `RATEPERUNIT`
  requirements, and stores synced Xero earnings-rate name matches where present.
- No live `POST /PayItems` write path, Xero pay item update path, or automated
  mapping from created pay items exists yet.
- No Xero-shaped timesheet preview exists yet.
- No draft Xero timesheet submission, submission history, idempotency-key
  persistence, duplicate timesheet detection, or correction workflow exists yet.

## Implementation Phases

### Phase 1 - Developer proof

Use Xero's demo company and API Explorer to confirm:

- OAuth app setup and redirect URL behaviour
- tenant selection and `Xero-Tenant-Id`
- payroll employee reads
- pay item/earnings-rate reads
- payroll calendar reads
- draft timesheet create/update payload shape

In parallel, add a local mocked Xero client test fixture so most iteration does
not depend on live API calls, rate limits, or demo-company reset state.

### Phase 2 - Connection foundation

Status: implemented, with extra lifecycle management now included.

Implemented:

- config variables for Xero client ID, client secret, redirect URI, and encryption
  secret
- OAuth start/callback actions
- CSRF/state handling
- token exchange and refresh
- selected tenant storage
- disconnect/reconnect flow
- admin-only connection page under the venue admin surface
- audit events for connect, reconnect, disconnect, token refresh failure, and
  tenant selection

Also implemented:

- remote Xero connection id storage and remote disconnect via Xero's
  connections API
- reconnect repair for an existing same-tenant connection while preserving staff
  mappings
- app-owned keepalive job scheduling from the NixOS module

Remaining hardening:

- Token refresh should be serialized per connection so two workers cannot consume
  the same rotating refresh token concurrently. Current code centralizes refresh
  handling but still needs an explicit DB lock or equivalent single-flight guard.

### Phase 3 - Read-only sync and mapping UI

Status: implemented for the current mapping/readiness scope.

Implemented read-only Xero sync for:

- employees
- pay items / earnings rates
- payroll calendars

Implemented admin mapping screens:

- staff to employee
- local earning bucket to Xero earnings rate
- payroll calendar selection for the venue

The UI should clearly distinguish unmapped, stale, and verified mappings. It
already does this for staff mappings; earnings-rate mappings should follow the
same state model. It should also show a "ready to submit" checklist for the
selected venue.

Remaining optional mapping/config screens:

- optional shift type or roster group to tracking item, only if the first client
  needs Xero tracking categories

### Phase 4 - Pay item provisioning

Status: in progress. The deterministic requirement derivation, durable
requirement record sync, and admin review preview are implemented; live Xero
create/update actions remain.

Build the admin-reviewed pay item provisioning lane before timesheet preview:

- derive required Xero earnings-rate pay items from current award/pay data
- classify each requirement as `MULTIPLE` or `RATEPERUNIT`
- surface expected multiplier or hourly loading amount
- match requirements against synced Xero earnings rates where possible
- persist requirement records and mark removed requirements as `stale`
- let admins create missing earnings rates through Xero `POST /PayItems`
- store the resulting local requirement to Xero earnings-rate link
- feed those links into the existing earnings-rate mapping/readiness UI

Completed slices:

- deterministic requirement set and admin review UI before enabling live Xero
  writes
- durable `xero_pay_item_requirement_records` sync for `proposed`, `matched`,
  `ignored`, and `stale` requirement states

### Phase 5 - Xero timesheet preview

Build a Xero-shaped preview using the existing approved-timesheet and pay-result
pipeline:

- select one venue and one report week/pay period
- load approved, non-deleted timesheet entries
- resolve staff mappings
- resolve earnings-rate mappings
- group by Xero employee, pay period, earnings rate, and tracking item
- produce `TimesheetLines` where `NumberOfUnits` is a seven-element day array
- show unmapped staff/pay buckets before allowing submission
- show already-submitted or externally-existing Xero timesheets for the period
  where known

The preview should be deterministic and testable without hitting Xero.

### Phase 6 - Draft submission

Submit one Xero timesheet per employee/pay period:

- create only `DRAFT` timesheets initially
- send idempotency keys on write calls
- persist full request and response payloads
- record the returned `TimesheetID`
- mark source entries as included in that Xero submission run
- write audit events for submission success/failure
- provide a retry path for failed submissions

Do not automatically submit approved/final Xero timesheets or pay runs in the
first version. Keep the final payroll review inside Xero.

### Phase 7 - Update and correction handling

After draft creation works, define correction behaviour:

- if an IHP entry changes after submission, mark the previous submission stale
- if the Xero timesheet is still draft, allow an explicit update
- if the Xero timesheet has been approved/processed, block automatic update and
  surface a manual correction workflow
- preserve old submission payloads for audit

Never silently mutate a submitted payroll period after a manager has already sent
it to Xero.

### Phase 8 - Optional setup helpers

Only after the core workflow is proven, consider additional admin-assisted
helpers:

- create or update Xero employee records from IHP staff profiles
- sync Xero employees back into IHP staff records
- create tracking options for roster groups or shift types

Each helper should be explicit, previewed, audited, and easy to skip for clients
whose accountant/bookkeeper wants Xero payroll setup managed directly in Xero.

## Validation Rules

Block submission when:

- the venue has no active Xero connection
- the token cannot be refreshed
- the selected Xero tenant is disconnected
- the selected week does not match the configured payroll calendar/pay period
- any included staff row lacks a verified Xero employee mapping
- any local earning bucket lacks a verified Xero earnings-rate mapping
- approved entries span multiple incompatible pay config snapshot versions unless
  the user explicitly accepts a mixed-snapshot submission
- a source entry has been edited, unapproved, or deleted since preview generation
- Xero already has a non-draft timesheet for the employee/pay period

## Security And Compliance

- Store OAuth credentials encrypted.
- Scope Xero connections by venue.
- Restrict connection, mapping, preview, and submission flows to venue admins or
  owners unless a narrower payroll-manager role is introduced.
- Include support-mode audit distinction when a platform support admin touches
  Xero configuration.
- Keep all Xero writes idempotent and auditable.
- Avoid storing unnecessary Xero payroll PII beyond IDs, names, emails, and
  metadata needed for mapping verification.
- Do not use Xero API data for AI/ML training or broad model context.

## Test Strategy

Unit/controller tests:

- OAuth callback state validation
- token refresh state transitions
- staff and earnings-rate mapping validation
- pay item requirement derivation from award data
- Xero payload grouping from approved IHP entries
- blocked submission when mappings are incomplete
- stale preview detection after source entry changes
- idempotency key persistence

Integration-style tests with mocked Xero:

- employee/pay item/calendar sync
- pay item creation success and validation error
- create draft timesheet success
- create draft timesheet validation error
- token refresh failure
- duplicate existing timesheet handling
- rate-limit/retry classification

Manual/demo-company verification:

- connect demo company
- sync employees, earnings rates, and calendars
- provision or match the required earnings-rate pay items
- map one staff member and one earnings bucket
- verify an ordinary plus rate-per-unit loading timesheet path in Xero
- submit one draft timesheet
- confirm the draft appears in Xero Payroll
- reset or disconnect cleanly

## Open Decisions

- Whether to use IHP's current `app_jobs` table for Xero submission runs or add
  dedicated Xero submission tables.
- Whether tracking should map shift type, roster group, venue cost centre, or be
  deferred entirely.
- Whether the first client expects Xero employee records to already exist or
  wants IHP to create/update employees.
- Whether Xero AU accepts rate-per-unit loading earnings rates on timesheets in
  the target tenant exactly as the docs imply.
- Whether mixed pay-config snapshot weeks should be blocked or allowed with an
  explicit warning.
- Whether leave should be exported to Xero in the same lane or kept separate
  until timesheet submission is stable.

## First Milestone Acceptance

The first useful milestone is complete when a venue admin can:

- connect an Australian Xero demo or payroll-enabled organisation
- sync Xero employees, earnings rates, and payroll calendars
- provision or match the required Xero earnings-rate pay items
- map IHP staff and IHP earning buckets to Xero objects
- preview one approved IHP payroll week as Xero draft-timesheet payloads
- submit those payloads as draft Xero timesheets
- see submission status, request/response metadata, source entry IDs, and audit
  history inside IHP
