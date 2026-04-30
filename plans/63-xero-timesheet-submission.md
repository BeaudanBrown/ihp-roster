# Pipeline 63 - Xero Draft Timesheet Submission

Read after `IMPLEMENTATION_PLAN.md`, `plans/57-xero-payroll-integration.md`,
`plans/58-xero-connection-foundation.md`, `plans/45-payroll-report-exports.md`,
and `.tickets/ir-176p.md`.

## Goal

Submit approved, snapshot-pinned IHP timesheets to Xero Payroll AU as draft
timesheets, with enough local validation and persisted request/response state to
debug every external side effect.

This plan narrows phases 5 and 6 of `plans/57-xero-payroll-integration.md` into
implementation-ready slices. The first implementation target after planning was
everything up to readiness validation:

1. Xero timesheet API client contract.
2. Local submission state schema.
3. Readiness/blocker model.
4. Admin Xero checklist tightening.
5. Deterministic tests for the validator.

Preview and submission should build on that foundation, not bypass it.

As of 2026-04-30, the readiness foundation and the OpenAPI contract/mock
foundation are in place. The next implementation chunk is:

1. Build deterministic Xero-shaped preview payloads.
2. Persist preview runs in the dedicated Xero submission tables.
3. Submit create-only Xero `DRAFT` timesheets with the strict OpenAPI-backed
   mock harness covering request shape and persistence behavior.

## Source Documents

Reviewed on 2026-04-30:

- Xero Payroll AU OpenAPI source:
  `https://raw.githubusercontent.com/XeroAPI/Xero-OpenAPI/master/xero-payroll-au.yaml`
- Xero Payroll AU SDK reference:
  `https://xeroapi.github.io/Xero-NetStandard/payroll-au/index.html`
- Xero developer Payroll AU pages:
  `https://developer.xero.com/documentation/api/payrollau/timesheets`
  and `https://developer.xero.com/documentation/api/payrollau/payitems`

The developer pages currently require JavaScript for full rendering, so use the
OpenAPI YAML as the canonical endpoint contract when implementation details
matter.

## Xero API Contract

Base URL for Payroll AU endpoints:

```text
https://api.xero.com/payroll.xro/1.0
```

All Payroll AU calls require:

- `Authorization: Bearer <access token>`
- `Xero-Tenant-Id: <tenant id>`
- `Accept: application/json`

All writes must also send:

- `Content-Type: application/json`
- `Idempotency-Key: <stable key no longer than 128 characters>`

### Required scopes

The existing connection flow already requests the useful first set:

- `offline_access`
- `payroll.employees.read`
- `payroll.settings`
- `payroll.timesheets`

The Xero OpenAPI lists `GET /Timesheets` as accepting either
`payroll.timesheets` or `payroll.timesheets.read`. Keep the current write scope
unless manual testing shows the configured Xero app needs the explicit read
scope for GET calls. Do not add employee write scopes for this lane.

### GET /Timesheets

Purpose:

- duplicate detection before create
- status check before update/correction
- post-submit verification

OpenAPI contract:

- method: `GET`
- path: `/Timesheets`
- scopes: `payroll.timesheets` or `payroll.timesheets.read`
- optional header: `If-Modified-Since`
- optional query params: `where`, `order`, `page`
- pagination note: up to 100 timesheets per page
- response envelope: `{ "Timesheets": [ ... ] }`

Implementation rule:

- Prefer a narrow `where` filter for the employee when practical, but do not
  trust Xero-side filtering as the only duplicate check. Parse every returned
  page and filter locally by `EmployeeID`, `StartDate`, and `EndDate`.
- Stop paging when a page returns fewer than 100 records.
- Parse Xero date values from both ISO `YYYY-MM-DD` and Microsoft JSON
  `/Date(...)` formats. Current helper code already has both parsers for payroll
  calendar dates; reuse that pattern.

### POST /Timesheets

Purpose:

- create one draft Xero timesheet for one employee and one pay period.

OpenAPI contract:

- method: `POST`
- path: `/Timesheets`
- scope: `payroll.timesheets`
- body schema: `array[Timesheet]`
- response envelope: `{ "Timesheets": [ ... ] }`
- successful status: HTTP 200 with returned Xero `TimesheetID`

IHP rule:

- Send a singleton array per API call. The API schema is array-shaped, but the
  app should keep idempotency, error handling, and audit state one employee/pay
  period at a time.
- Always send `Status: "DRAFT"`. Do not approve Xero timesheets or create pay
  runs in this lane.
- Use ISO `YYYY-MM-DD` request dates. Xero examples show both SDK ISO inputs and
  `/Date(...)` response values; parsing should accept both.

Minimum request body shape:

```json
[
  {
    "EmployeeID": "b34e89ff-770d-4099-b7e5-f968767118bc",
    "StartDate": "2026-04-27",
    "EndDate": "2026-05-03",
    "Status": "DRAFT",
    "TimesheetLines": [
      {
        "EarningsRateID": "ab874dfb-ab09-4c91-954e-43acf6fc23b4",
        "NumberOfUnits": [2.0, 10.0, 0.0, 0.0, 5.0, 0.0, 5.0]
      }
    ]
  }
]
```

`TrackingItemID` is optional and should stay omitted for the first version.
Tracking is Xero's cost-centre/category mechanism for splitting payroll costs by
department, roster group, location, or similar reporting buckets. IHP does not
need it to submit payroll hours. If a future client needs Xero payroll reporting
by roster group or shift type, add explicit tracking mapping first.

### POST /Timesheets/{TimesheetID}

Purpose:

- later correction/update path for an existing draft timesheet.

OpenAPI contract:

- method: `POST`
- path: `/Timesheets/{TimesheetID}`
- scope: `payroll.timesheets`
- body schema: `array[Timesheet]`
- response envelope: `{ "Timesheets": [ ... ] }`

IHP rule:

- Do not implement automatic updates in the first submission slice.
- Before any update, fetch the remote timesheet and require `Status == "DRAFT"`.
- If Xero status is `APPROVED`, processed, or anything other than draft, block
  the update and surface a manual correction path.

### Timesheet schema

Xero required fields:

- `EmployeeID`
- `StartDate`
- `EndDate`

IHP required fields:

- `Status = "DRAFT"`
- at least one `TimesheetLines` row
- each line has `EarningsRateID`
- each line has `NumberOfUnits`

`NumberOfUnits` is an ordered array of daily units. The app already requires the
venue to select a Xero payroll calendar, so the submission period should be
derived from that selected calendar rather than hard-coded to calendar weeks.
Produce one numeric value per calendar day from `StartDate` through `EndDate`,
inclusive, ordered oldest to newest. A weekly period yields seven values; a
fortnightly period yields fourteen; longer supported calendar periods yield the
matching number of daily values.

Readiness must prove the IHP period being prepared exactly matches the Xero
payroll period for the selected payroll calendar. Do not upload an arbitrary
local date range just because the local entries are approved. The selected Xero
payroll calendar is the authority for expected start and end dates.

### Error handling

The existing Xero helper already catches two important failure modes:

- non-2xx HTTP responses
- 2xx responses whose JSON body contains a non-empty Xero `Type`, such as
  `ValidationException`

Keep that behavior for timesheet endpoints. Persist enough detail for debugging:

- endpoint label
- HTTP status when present
- response body excerpt or full JSON response in submission state
- Xero `Type`, `Title`, `Detail`, `Message`, `Instance`, and
  `ValidationErrors` when present
- idempotency key
- generated request payload

Do not treat HTTP 200 as success until the semantic Xero response has been
checked.

## Local API Client Boundary

Extend `Application.Helper.Xero` instead of creating ad hoc request code in a
controller.

Add types:

- `XeroTimesheetRef`
  - `xeroTimesheetId :: Maybe Text`
  - `xeroTimesheetEmployeeId :: Text`
  - `xeroTimesheetStartDate :: Day`
  - `xeroTimesheetEndDate :: Day`
  - `xeroTimesheetStatus :: Maybe Text`
  - `xeroTimesheetHours :: Maybe Scientific`
  - `xeroTimesheetLines :: [XeroTimesheetLineRef]`
  - `xeroTimesheetRaw :: Aeson.Value`
- `XeroTimesheetLineRef`
  - `xeroTimesheetLineEarningsRateId :: Maybe Text`
  - `xeroTimesheetLineTrackingItemId :: Maybe Text`
  - `xeroTimesheetLineUnits :: [Scientific]`
  - `xeroTimesheetLineRaw :: Aeson.Value`
- `XeroTimesheetQuery`
  - optional `ifModifiedSince`
  - optional `where`
  - optional `order`
  - optional `page`

Extend `XeroClient` with:

```haskell
fetchTimesheets ::
    Text -> Text -> XeroTimesheetQuery ->
    IO (Either XeroClientError [XeroTimesheetRef])

fetchTimesheet ::
    Text -> Text -> Text ->
    IO (Either XeroClientError XeroTimesheetRef)

createTimesheet ::
    Text -> Text -> Text -> Aeson.Value ->
    IO (Either XeroClientError [XeroTimesheetRef])

updateTimesheet ::
    Text -> Text -> Text -> Text -> Aeson.Value ->
    IO (Either XeroClientError [XeroTimesheetRef])
```

Parameter order follows existing helper style: access token, tenant id,
idempotency key where needed, endpoint id where needed, request body.

## Local Submission State

Add dedicated tables. Do not overload `export_jobs`: Xero submission is an
external side effect, not a generated downloadable file.

### xero_submission_runs

Suggested columns:

- `id`
- `venue_id`
- `xero_connection_id`
- `submitted_by_user_id`
- `pay_period_start`
- `pay_period_end`
- `source_kind`, initially `approved_timesheets`
- `status`: `previewed`, `blocked`, `pending`, `submitted`, `partially_failed`,
  `failed`, `superseded`
- `preview_payload_json`
- `readiness_snapshot_json`
- `xero_duplicate_check_json`
- `submitted_at`
- `completed_at`
- `error_summary`
- `created_at`, `updated_at`

### xero_timesheet_submissions

Suggested columns:

- `id`
- `xero_submission_run_id`
- `venue_id`
- `xero_connection_id`
- `staff_id`
- `xero_employee_id`
- `pay_period_start`
- `pay_period_end`
- `status`: `blocked`, `pending`, `submitted`, `failed`, `skipped`,
  `superseded`
- `idempotency_key`
- `request_payload_json`
- `response_payload_json`
- `xero_timesheet_id`
- `xero_timesheet_status`
- `xero_updated_date_utc`
- `attempt_count`
- `last_error`
- `submitted_at`
- `created_at`, `updated_at`

Add a unique index for active submissions by connection, employee, and pay
period where status is not `superseded`. This prevents duplicate local creates
before Xero is even called.

### xero_timesheet_submission_entries

Suggested columns:

- `id`
- `xero_timesheet_submission_id`
- `timesheet_entry_id`
- `pay_config_snapshot_id`
- `entry_updated_at_at_preview`
- `entry_approved_at_at_preview`
- `created_at`, `updated_at`

This join table makes it possible to mark a submitted run stale when an included
entry is edited, unapproved, or deleted later.

## Readiness Validator

Expose one shared validator that can be used by:

- Admin Xero readiness checklist
- future Xero timesheet preview page
- future submission action
- Hspec/controller tests

Suggested result shape:

- `XeroTimesheetReadiness`
  - `ready :: Bool`
  - `periodStart :: Day`
  - `periodEnd :: Day`
  - `blockers :: [XeroReadinessBlocker]`
  - `warnings :: [XeroReadinessBlocker]`
  - `staffCount`
  - `entryCount`
  - `payBucketCount`
- `XeroReadinessBlocker`
  - `code :: Text`
  - `severity :: "blocker" | "warning"`
  - `message :: Text`
  - optional affected `staffId`
  - optional affected `timesheetEntryId`
  - optional affected `localBucketKey`
  - optional affected `xeroObjectId`
  - optional `actionHint`

Blockers for the first readiness slice:

- no active Xero connection
- token refresh fails or connection is `reauthorization_required`
- latest reference sync is missing or failed
- selected payroll calendar missing or stale
- selected period cannot be derived from the selected Xero payroll calendar
- local preview/submission period does not exactly match the Xero payroll
  calendar's expected period start and end dates
- active approved entries are missing
- included entry is not approved
- included entry is soft-deleted
- included entry lacks `pay_config_snapshot_id`
- included entries contain mixed pay configuration snapshots, meaning the
  approved timesheet entries were calculated against different versions of the
  venue's award/pay setup. This is always a blocker. Pay rates should change at
  controlled effective boundaries, usually once per year, and the new rates
  should only affect the first pay period that starts after the new financial
  year/effective date.
- staff row lacks verified Xero employee mapping
- local earning bucket lacks verified Xero earnings-rate mapping
- managed pay item requirement for an included bucket is not `matched` or
  `created`
- selected pay item account code missing when pay item requirements are still
  proposed
- Xero duplicate check finds any existing timesheet for employee/period. Until
  the explicit update path exists, the app should block create for both draft
  and non-draft remote timesheets so it cannot accidentally create duplicates.

Warnings:

- Xero duplicate check finds an existing draft timesheet. This blocks create for
  that employee/period until update support exists, but the UI can show it as a
  future update candidate.
- Xero GET filtering fails and fallback pagination had to fetch broadly.
- payroll calendar period support is manual/unverified in the connected tenant.

## Admin Readiness Checklist Gap

The current `XeroReadyChecklist` shape is too coarse for draft-timesheet
readiness. It checks connection, latest sync, staff mappings, account code, and
payroll calendar, but it must also include:

- all required active pay item requirements are matched or created
- local bucket to Xero earnings-rate mappings are verified for every included
  payroll bucket
- readiness diagnostics include counts and affected rows, not just booleans

Implementation should update `Application.Helper.XeroAdminTypes`,
`Web.Controller.Admin.Xero`, and `Web.View.Admin.Xero` so the Admin Xero section
is a trustworthy gate before the preview/submission screens are built.

## Preview Payload Builder

The preview builder comes after readiness validation.

Inputs:

- venue
- selected week or payroll period
- approved non-deleted `timesheet_entries`
- staff mappings
- earnings-rate mappings
- pay item requirement records
- selected payroll calendar

Rules:

- Reuse the approved timesheet/pay-result pipeline used by
  `PayrollEarningsCsv`.
- Do not group by display name alone. Derive the stable local bucket key from
  the same facts used for pay item requirements:
  classification x employment basis x effective date x condition.
- Build one Xero timesheet per Xero employee and period.
- Build one Xero timesheet line per `EarningsRateID`. Add `TrackingItemID` only
  after a future tracking-mapping feature exists.
- Fill missing days with `0.0`.
- Round/format units consistently with payroll export behavior.
- Preserve source `timesheet_entry_ids` and pay snapshot versions in preview
  metadata.

### Next preview slice

Track this work under `ir-lgy7` and its child tasks:

- `ir-f09l` - Define Xero timesheet preview payload types and builder.
- `ir-4jzo` - Add Xero timesheet preview tests and fixtures.
- `ir-1urs` - Persist preview runs for Xero timesheet submission.

The first deliverable should be a deterministic service module, not a page. A
reasonable module boundary is `Application.Xero.Timesheets.Preview`, adjusted to
fit the current post-refactor Xero module layout. Keep the builder free of Xero
HTTP effects so Hspec can assert exact payloads.

Recommended data shape:

- `XeroTimesheetPreview`
  - local staff id
  - Xero employee id
  - period start/end
  - source timesheet entry ids
  - pay config snapshot id
  - lines
  - Xero request object JSON
- `XeroTimesheetPreviewLine`
  - local bucket key
  - Xero earnings rate id
  - `NumberOfUnits` by day
  - source entry ids contributing to the line
- `XeroTimesheetPreviewRun`
  - readiness snapshot
  - duplicate-check snapshot
  - previews
  - combined `preview_payload_json` suitable for persistence

Implementation rules:

- Call the shared readiness validator before building a persisted preview. Pure
  helper tests may call the builder with already-prepared fixture data.
- Use the selected Xero payroll calendar period. Do not derive a local week from
  roster settings.
- Include only approved, non-deleted, snapshot-pinned entries from the selected
  period.
- Hard-fail mixed `pay_config_snapshot_id` values before preview persistence.
- Resolve staff through verified `xero_staff_mappings`.
- Resolve local pay buckets through verified `xero_earnings_rate_mappings`.
- Build one Xero timesheet object per Xero employee and selected period.
- Build one line per `EarningsRateID`; omit `TrackingItemID` in v1.
- Emit one `NumberOfUnits` value per day from period start through period end,
  filling missing days with `0.0`.
- Store source entry ids and snapshot metadata in preview metadata, but keep the
  Xero request JSON itself limited to fields Xero accepts.
- Persist preview output into `xero_submission_runs.preview_payload_json`,
  `readiness_snapshot_json`, and `xero_duplicate_check_json`. Do not call
  `POST /Timesheets` in the preview slice.

Minimum preview tests:

- weekly period produces seven daily units in date order
- fortnightly period produces fourteen daily units in date order
- missing days are zero-filled
- two entries for one employee and one Xero earnings rate aggregate into one
  line
- two Xero employees produce two timesheet objects
- source entry ids and pay snapshot ids survive in metadata
- the Xero request JSON omits `TrackingItemID`
- persisted preview runs do not call Xero HTTP

## Implementation Order

1. Add the timesheet API client boundary and tests with mocked JSON envelopes.
2. Add local submission schema and generated types.
3. Add readiness result/blocker types and pure-ish validator helpers.
4. Tighten the Admin Xero readiness checklist using the same validator concepts.
5. Add focused Hspec coverage for missing connection, missing sync, missing staff
   mapping, missing earnings mapping, missing pay item, bad calendar, any remote
   duplicate, and happy readiness.
6. Vendor the OpenAPI contract and add strict local Xero request/mock tests.
7. Build preview payload generation.
8. Persist preview runs.
9. Build create-only draft submission.
10. Add the first Xero page preview/submission UI.
11. Add correction/update handling after draft creation is proven.

## Draft Submission Service

Track create-only submission under `ir-ujwc` and its child tasks:

- `ir-tsvi` - Implement Xero draft timesheet submission service.
- `ir-yikx` - Cover Xero submission with strict contract mock tests.
- `ir-uxn9` - Add Xero timesheet preview and submit UI on the existing Xero
  page.

The submission service should consume the same preview payload shape produced by
`ir-lgy7`; do not rebuild a second payload path in the controller. A reasonable
module boundary is `Application.Xero.Timesheets.Submission`, adjusted to fit the
current post-refactor Xero module layout.

Submission rules:

- Rerun readiness immediately before any write.
- Run duplicate detection immediately before any write. Use `GET /Timesheets`
  with a narrow employee/period query where practical, but still filter locally
  by employee id, start date, and end date.
- Block create if any remote Xero timesheet exists for the same employee/period.
- Use `POST /Timesheets` only. Do not call `POST /Timesheets/{TimesheetID}` in
  this slice.
- Send a singleton JSON array per employee/period.
- Always send `Status: "DRAFT"`.
- Generate and persist a durable idempotency key before calling Xero. Reuse that
  key on retry for the same intended request.
- Persist the exact request JSON in
  `xero_timesheet_submissions.request_payload_json`.
- Persist the full response JSON, returned `TimesheetID`, Xero status,
  `attempt_count`, `last_error`, and `submitted_at`.
- Insert `xero_timesheet_submission_entries` rows for every source
  `timesheet_entry_id`, including the preview-time `pay_config_snapshot_id`,
  `updated_at`, and `approved_at` values.
- Mark the run as `submitted`, `partially_failed`, `failed`, or `blocked`
  depending on per-employee outcomes.
- Do not approve Xero timesheets, create pay runs, or implement correction/update
  workflow in this slice.

Use the vendored OpenAPI contract and strict local mock from
`Test.XeroContractSpec` for submission tests. Avoid ad hoc request stubs for the
main HTTP behavior; the point of the refactor is that the concrete app request
path can be tested against a local contract-backed Xero surface.

Minimum submission tests:

- successful create stores run, per-employee submission, source-entry links,
  request JSON, response JSON, Xero `TimesheetID`, Xero status, submitted
  timestamp, and `attempt_count`
- request hits strict mock as `POST /Timesheets` with singleton array body,
  required auth headers, tenant header, content type, and `Idempotency-Key`
- semantic Xero validation errors are persisted as failed per-employee
  submissions
- transport failures are persisted as failed per-employee submissions
- partial success marks the run `partially_failed`
- remote duplicate blocks create before `POST /Timesheets`
- retry reuses the persisted idempotency key for the same submission row

## First Xero Page UI Slice

Build the first user-facing draft-timesheet workflow inside the existing Xero
page, not as a separate page. This slice is for venue owners only. Do not expose
draft-timesheet preview or submission controls to ordinary venue admins or
managers.

Initial UI scope:

- Use the selected verified Xero payroll calendar to derive the current
  submission period.
- Show readiness blockers and warnings before preview/submission.
- Provide a preview action that persists the latest preview run using the same
  `xero_submission_runs.preview_payload_json`,
  `readiness_snapshot_json`, and `xero_duplicate_check_json` shape used by the
  submission service.
- Render the preview as one row per Xero employee. Keep the first version dense:
  employee, period, total units, earnings-rate/line summary, source-entry count,
  and any blocker/error state are enough.
- Show only the latest run for now. Do not build a historical run list in this
  slice.
- Provide a submit action that calls the existing create-only submission service.
  It must still rerun readiness and duplicate detection immediately before
  write.
- Show per-employee submission status and errors from
  `xero_timesheet_submissions`.
- A retry button or affordance can be shown for failed rows, but full retry UX
  polish is not required in this slice.
- Do not approve Xero timesheets, create pay runs, implement update/correction
  support, or build a separate preview/submission UI route.

Minimum UI tests:

- venue owners can see the panel on the existing Xero page
- non-owner venue roles cannot see or invoke preview/submission actions
- preview action persists a latest preview run and renders one row per employee
- submit action calls the existing submission service and renders latest
  run/submission status
- readiness blockers and per-employee submission errors are visible
- historical runs are not rendered as a list in this first slice

## Tests

Minimum tests before preview/submission implementation:

- parse `GET /Timesheets` response envelope with Microsoft JSON dates
- parse `POST /Timesheets` response envelope and returned `TimesheetID`
- treat non-2xx response as `XeroHttpError`
- treat HTTP 200 with non-empty Xero `Type` as `XeroHttpError`
- generate `GET /Timesheets` URLs with `where/order/page` safely encoded
- readiness blocks missing staff mapping
- readiness blocks missing earnings/pay item mapping
- readiness blocks unverified pay item requirements
- readiness blocks payroll calendar periods that cannot be derived
- readiness blocks any existing remote timesheet for the employee/period until
  update support exists
- readiness permits fully mapped weekly and fortnightly payroll-calendar periods
  with no remote duplicate

Manual demo-company validation remains required before production use:

- create or match required managed pay items
- approve representative IHP timesheets
- run readiness
- preview one employee/week payload
- call `POST /Timesheets` for a draft
- verify the draft appears in Xero Payroll
- verify Xero uses the expected earnings rates and unit totals

## Decisions

1. Support the selected Xero payroll calendar period instead of hard-coding
   weekly submission. The selected payroll calendar determines the period start,
   period end, and `NumberOfUnits` length. The app must verify that the IHP
   timesheet period being prepared exactly matches what Xero expects for that
   payroll calendar.
2. Block creates when Xero already has any timesheet for the same employee and
   period until update support is implemented.
3. Omit `TrackingItemID` in the first milestone. Tracking categories are
   optional Xero cost-centre/reporting metadata and are not needed to submit
   hours.
4. Hard-block mixed pay-config snapshots. A single Xero submission period must
   use one pay configuration snapshot.
