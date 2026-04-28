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
- IHP pay buckets are mapped to existing Xero earnings rates
- optional roster/shift grouping can map to Xero tracking items later
- approved IHP timesheets are transformed into Xero timesheet lines
- generated Xero timesheets are submitted as `DRAFT`
- the client or bookkeeper reviews and runs payroll inside Xero

Avoid making automatic Xero payroll setup the first milestone. Creating employees,
pay items, payroll calendars, or complex award configurations in Xero should be a
later admin-assisted helper after the basic mapping and draft-timesheet workflow
is reliable.

## Xero API Surface

The initial target is Xero Payroll AU:

- OAuth 2.0 connection flow with `offline_access`
- connected tenant lookup and storage of the selected `Xero-Tenant-Id`
- `GET /Employees` for payroll employee mapping
- `GET /PayItems` for earnings-rate mapping
- `GET /PayrollCalendars` for pay-period validation
- `GET /Timesheets` for duplicate/update detection
- `POST /Timesheets` to create draft timesheets
- `POST /Timesheets/{TimesheetID}` to update draft timesheets when safe

Required Xero scopes for the first useful version are expected to include:

- `offline_access`
- `payroll.employees.read`
- `payroll.settings.read`
- `payroll.timesheets`
- possibly `payroll.timesheets.read` if not implied by the write scope in the
  active Xero app configuration

Do not request write scopes for employees or payroll settings until the app has a
specific setup-sync feature that needs them.

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

Implement:

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

Token refresh should be serialized per connection so two workers cannot consume
the same rotating refresh token concurrently.

### Phase 3 - Read-only sync and mapping UI

Implement read-only Xero sync for:

- employees
- pay items / earnings rates
- payroll calendars

Then add admin mapping screens:

- staff to employee
- local earning bucket to Xero earnings rate
- optional shift type or roster group to tracking item
- payroll calendar selection for the venue

The UI should clearly distinguish unmapped, stale, and verified mappings. It
should also show a "ready to submit" checklist for the selected venue.

### Phase 4 - Xero timesheet preview

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

### Phase 5 - Draft submission

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

### Phase 6 - Update and correction handling

After draft creation works, define correction behaviour:

- if an IHP entry changes after submission, mark the previous submission stale
- if the Xero timesheet is still draft, allow an explicit update
- if the Xero timesheet has been approved/processed, block automatic update and
  surface a manual correction workflow
- preserve old submission payloads for audit

Never silently mutate a submitted payroll period after a manager has already sent
it to Xero.

### Phase 7 - Optional setup helpers

Only after the core workflow is proven, consider admin-assisted helpers:

- create missing Xero earnings rates from local IHP bucket definitions
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
- Xero payload grouping from approved IHP entries
- blocked submission when mappings are incomplete
- stale preview detection after source entry changes
- idempotency key persistence

Integration-style tests with mocked Xero:

- employee/pay item/calendar sync
- create draft timesheet success
- create draft timesheet validation error
- token refresh failure
- duplicate existing timesheet handling
- rate-limit/retry classification

Manual/demo-company verification:

- connect demo company
- sync employees, earnings rates, and calendars
- map one staff member and one earnings bucket
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
- Whether mixed pay-config snapshot weeks should be blocked or allowed with an
  explicit warning.
- Whether leave should be exported to Xero in the same lane or kept separate
  until timesheet submission is stable.

## First Milestone Acceptance

The first useful milestone is complete when a venue admin can:

- connect an Australian Xero demo or payroll-enabled organisation
- sync Xero employees, earnings rates, and payroll calendars
- map IHP staff and IHP earning buckets to Xero objects
- preview one approved IHP payroll week as Xero draft-timesheet payloads
- submit those payloads as draft Xero timesheets
- see submission status, request/response metadata, source entry IDs, and audit
  history inside IHP

