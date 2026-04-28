# Pipeline 59 - Code Smell Remediation

Read after `IMPLEMENTATION_PLAN.md` and `AGENTS.md`.

## Goal

Capture the code-smell scan from 2026-04-28 and turn it into a practical
cleanup backlog. These tasks are cross-cutting hardening work; they should be
scheduled around active feature pipelines instead of interrupting in-flight
Xero, profiling, roster, or admin changes.

The scan was read-only. The current worktree was already dirty, so treat line
numbers as pointers into the 2026-04-28 working tree, not immutable anchors.

## Scan Inputs

- Static search for partial functions, raw SQL, unsafe/global state, large
  files, broad exception handling, and fragile frontend DOM mutation.
- Static duplicate-code search across Haskell, TypeScript, JavaScript, CSS, SQL,
  and Markdown sources, excluding vendor/generated/build artifacts.
- File-size hotspot review.
- `bash ./bin/in-env lint`, which exited non-zero with 206 HLint hints. Most
  hints were low-risk style noise around record-dot syntax and eta reduction,
  but the volume reinforces that a cleanup pass would reduce friction.

## Priority Order

1. Move request-thread invitation delivery to durable app jobs.
2. Split the admin controller/view data clumps, starting with Xero.
3. Move production venue bootstrap helpers out of `Application.Support`.
4. Consolidate live-update focus protection and remove stale auto-refresh
   compatibility code.
5. Vendor runtime CDN assets.
6. Make silent failure paths observable or explicit.
7. Finish the CSS split.
8. Consolidate high-signal duplicated helpers where extraction reduces future
   drift.
9. Sweep low-risk lint hints only after the structural work settles.

## Findings And Recommendations

### 1. Raw Background Threads In Request Handlers

**Priority:** high

**Finding:** Invitation delivery is launched with raw `forkIO` from controller
helpers:

- `Web/Controller/Admin.hs:690` captures `?context`, `?modelContext`, and
  `?request` in `queueVenueInvitationDelivery`.
- `Web/Controller/Support.hs:262` does the same in
  `queueVenueOnboardingInvitationDelivery`.

This is brittle because failures can disappear, retries and dedupe are absent,
and request-scoped implicit parameters outlive the request. The repo already has
an app job queue in `Application/Async/Queue.hs` and dispatch in
`Application/Async/Registry.hs`.

**Recommendation:** Add durable job kinds for venue invitation delivery and
venue-onboarding invitation delivery. The job payload should carry only record
ids and actor metadata needed for audit/live invalidation. The worker should
load fresh DB context, call the existing `deliver*InvitationEmail` helpers,
record success/failure on the invitation row, and broadcast the affected live
surface when relevant.

**Acceptance checks:**

- Creating an invite persists a queued/delivery-pending row before returning.
- Failed delivery records `deliveryStatus = failed` and a useful error.
- Retried jobs do not send duplicate accepted/revoked invitations.
- Admin invite live fragments still update after async completion.

### 2. Admin Controller And View Are Carrying Too Many Concerns

**Priority:** high

**Finding:** `Web/Controller/Admin.hs` is about 2,064 lines and handles venue
config, invitations, roster groups, slot names, shift types, report exports,
Xero OAuth, Xero sync, Xero mapping, and Xero pay-item readiness. The matching
view `Web/View/Admin/Index.hs` is about 1,419 lines. `IndexView` currently has
31 fields, and `renderConfigSectionsAccordion` takes a very long positional
argument list.

This creates data clumps and makes unrelated admin changes risky.

**Recommendation:** Introduce narrow view-data records and split by concern.
Start with Xero because it is the fastest-growing area:

- `AdminPageData` for the top-level admin page.
- `AdminConfigData` for invites, roster groups, slot names, shift types, and
  exports.
- `XeroAdminData` for connection state, reference data counts, mappings,
  requirements, payroll calendars, and readiness checklist.
- A controller/helper module for Xero admin loading and mutation responses.
- A view module for Xero admin rendering.

Keep route/action types stable while extracting helpers so existing tests keep
their behavioral value.

**Acceptance checks:**

- `AdminAction` reads as orchestration instead of a long data-loading script.
- `renderConfigSectionsAccordion` takes a small record instead of dozens of
  positional arguments.
- Xero fragment response tests still cover the rendered ids and OOB controls.

### 3. Production Code Imports A Seed/Test Utility Module

**Priority:** high

**Finding:** `Application/Support.hs` contains test and seed helpers such as
`resetDatabase`, fixture user builders, and `testPassword`, but production
controllers import it for venue bootstrap:

- `Web/Controller/Users.hs:193`
- `Web/Controller/Support.hs:79`

That mixes destructive test utilities with production domain operations.

**Recommendation:** Move the production venue bootstrap path to a narrow helper,
for example `Application.Helper.VenueBootstrap` or
`Application.Support.VenueBootstrap` if that namespace is intentionally domain
support. Leave `resetDatabase`, fixture builders, and test password utilities in
seed/test-only modules. Then update production controllers and dev fixtures to
use the narrow helper.

**Acceptance checks:**

- Production controllers no longer import `Application.Support`.
- `Application.Support` no longer exposes helpers that production code needs.
- Venue bootstrap tests still prove default venue config, roster groups, slot
  names, and membership setup.

### 4. Duplicate Live-Update Focus Preservation Logic

**Priority:** medium-high

**Finding:** Focused-field preservation is implemented in both:

- `static/app-live-updates.js:74`
- `static/app.js:675`

`static/app.js:663` also still calls the code `auto-refresh` deferral, even
though the documented architecture has retired IHP Auto Refresh in favor of
explicit live fragments.

**Recommendation:** Make `static/app-live-updates.js` the single owner of
focused-field protection. Migrate any remaining morphdom override behavior into
the declarative `LiveFragmentProtection` path from
`plans/56-declarative-live-fragments.md`, then remove the legacy
`enableRosterGridAutoRefreshDeferral` block from `static/app.js`.

**Acceptance checks:**

- Roster note edits are not clobbered by live updates while focused.
- Staff-select changes still apply immediately when they should.
- No code path refers to app runtime "auto-refresh" after migration.

### 5. Runtime Assets Still Depend On CDNs

**Priority:** medium

**Finding:** `Web/View/Layout.hs` loads Bootstrap locally but still loads:

- Bootstrap Icons from `https://cdn.jsdelivr.net/...`
- HTMX from `https://unpkg.com/...`

Runtime CDN dependencies make production behavior depend on third-party network
availability and complicate CSP/supply-chain controls.

**Recommendation:** Vendor HTMX and Bootstrap Icons under `static/vendor/` and
load them through `assetPath`, matching the Bootstrap pattern. Keep versions
documented in the vendor path or a small manifest note.

**Acceptance checks:**

- A production page has no third-party script or stylesheet URLs for core app
  runtime.
- Existing HTMX and icon-dependent E2E tests pass with network disabled.

### 6. Silent Failure Paths Hide Useful Signals

**Priority:** medium

**Finding:** Several paths intentionally degrade to empty output or swallow
details:

- `Web/FrontController.hs:53` catches all auth initialization exceptions,
  clears session state, and does not log the exception.
- `Web/RosterWeeks/Responses.hs:23`, `Web/Controller/LeaveRequests.hs:50`, and
  `Web/Controller/Timesheets.hs:383` return empty fragments when projection
  rendering returns `Nothing`.
- `Application/PublicHolidays/Sync.hs:145` drops malformed Data VIC holiday
  records without exposing counts or errors.

These may be appropriate user-facing fallbacks, but they are poor operational
signals.

**Recommendation:** Add structured logging or counters at each fallback. For
fragment endpoints, prefer explicit 404/422/toast responses where the caller
submitted an invalid target and reserve empty HTML only for deliberate
"not mounted/no visible content" states.

**Acceptance checks:**

- Auth init failures include a log line with the exception class/message.
- Projection misses are distinguishable from valid empty fragments.
- Public holiday sync summary includes skipped/invalid record counts.

### 7. CSS Split Is Half-Finished

**Priority:** low-medium

**Finding:** `static/app.css` is now a manifest, but it still contains temporary
admin slot-name overrides below the imports. `static/css/features/admin.css` is
currently only a placeholder comment.

**Recommendation:** Move the admin slot-name rules into
`static/css/features/admin.css`, remove the temporary block from `static/app.css`,
and keep `app.css` as a pure import manifest plus only genuinely cross-cutting
compatibility rules.

**Acceptance checks:**

- `static/app.css` contains imports only, or documented app-wide compatibility
  rules only.
- Admin slot-name responsive controls still pass the existing admin slot-name
  E2E coverage.

### 8. Large Generated-Adjacent And Domain Modules Need Ownership Boundaries

**Priority:** low-medium

**Finding:** Several files are over 900 lines:

- `Application/FwcMapd/Sync.hs`
- `Application/Helper/Export.hs`
- `Application/Script/SeedProfile.hs`
- `Application/Support/DevFixtures.hs`

Some of these are naturally batch/domain-heavy, but they still mix parsing,
curation, persistence, projection, and reporting.

**Recommendation:** Split only along stable boundaries. Do not churn these
modules for style alone. Good future boundaries:

- FWC MAPD payload parsing and curation separate from persistence/projection.
- Export report payload building separate from export job persistence.
- Profile/dev seed scenario generation separate from low-level fixture helpers.

**Acceptance checks:**

- Extracted modules have focused Hspec coverage.
- Existing public helper APIs stay stable for scripts/controllers.

### 9. Duplicate Toast Construction And Class Names

**Priority:** medium

**Finding:** Several controllers construct nearly identical
`ToastOverlayConfig` records inline:

- `Web/Controller/LeaveRequests.hs:349`, `:414`, and `:441`
- `Web/Controller/Timesheets.hs:420`
- `Web/Controller/Profiles.hs:102`
- `Web/RosterWeeks/Responses.hs:81` and `:91`
- `Web/Controller/Admin.hs:1147`

`Application/Helper/View/Toast.hs` already owns toast config/rendering, so these
literals are drifting away from the helper boundary. One leave error path uses
`app-toast-danger`, while the stylesheet defines `app-toast-error`.

**Recommendation:** Add small constructors such as `successToast`, `errorToast`,
and `renderToastOob` to `Application.Helper.View.Toast`. Keep message text and
placement as parameters, but centralize icon defaults, class names, dismissible
defaults, and OOB rendering. Replace `app-toast-danger` with the canonical error
class unless the design intentionally needs a third severity.

**Acceptance checks:**

- Controllers no longer construct basic success/error toast records by hand.
- Toast severity CSS class names are consistent with `static/css/...` rules.
- Existing HTMX responses still include the expected toast mount OOB swap.

### 10. Duplicate Pay-Config Snapshot JSON Serialization

**Priority:** medium

**Finding:** Snapshot JSON payload construction appears in both:

- `Application/Helper/Pay.hs:200`
- `Application/Support/PayrollFixtures.hs:98`

The serializers for venue config, award levels, base rates, penalty rates, and
shift types are very similar. This risks test fixtures using a subtly different
snapshot shape from production approval/export code.

**Recommendation:** Move the pure snapshot payload builders into a shared helper
owned by the pay/config domain. Production code and payroll fixtures should call
the same serializer. Keep fixture-specific record creation in the fixture module;
only share the pure JSON shape.

**Acceptance checks:**

- Snapshot fixture JSON and production snapshot JSON are produced through the
  same helper path.
- Existing payroll snapshot and export tests continue to pass.
- A future snapshot schema change has one serializer to update.

### 11. Duplicate Invitation Delivery Status Handling

**Priority:** medium

**Finding:** Venue invitations and venue-onboarding invitations have parallel
delivery-result update logic:

- `Application/Helper/VenueInvitation.hs:31`
- `Application/Helper/VenueOnboardingInvitation.hs:37`

The controllers also have similar queue/fork wrappers:

- `Web/Controller/Admin.hs:690`
- `Web/Controller/Support.hs:262`

This duplicates the status transition, error-message truncation, timestamping,
and logging shape.

**Recommendation:** Pair this with the durable-job work in finding 1. Extract a
small shared helper for recording delivery success/failure, parameterized by the
query/update action or by a narrow invitation record capability. Then move the
request-thread queue wrappers to app jobs.

**Acceptance checks:**

- Both invitation types share one delivery result policy.
- Error truncation and status names cannot drift between invitation lanes.
- Async job tests cover success, failure, and retry behavior for both record
  types.

### 12. Duplicate Leave View Formatting Helpers

**Priority:** medium-low

**Finding:** Leave date range rendering and non-empty text normalization are
duplicated in:

- `Web/View/LeaveRequests/Index.hs:200`
- `Web/View/Profiles/Edit.hs:275`

`Web/View/Profiles/Edit.hs` already imports a helper from the leave view, so the
two views already have a coupling point. `Web/Controller/Passkeys.hs:53` has a
smaller `nonEmptyText` variant.

**Recommendation:** Move shared view-only formatting to a narrow helper module,
for example `Application.Helper.View.Leave` or
`Application.Helper.View.Text`, depending on whether the date-range helper stays
leave-specific. Prefer one `nonEmptyText` implementation that strips whitespace
before deciding whether to render a fallback.

**Acceptance checks:**

- Leave and profile leave sections render date ranges through the same helper.
- Blank and whitespace-only notes render consistently.
- Existing profile/leave view tests or focused Hspec coverage still pass.

### 13. Duplicate Weekday Label Mapping

**Priority:** medium-low

**Finding:** Weekday index labels are defined in several places:

- `Application/Helper/WeekBoundaries.hs:85`
- `Application/Helper/View/VenueBootstrap.hs:54`
- `Web/View/Admin/Index.hs:1397`

The `WeekBoundaries` helper already exposes `weekdayIndexLabel` and
`weekdayIndexLabels`.

**Recommendation:** Use `Application.Helper.WeekBoundaries` as the canonical
source for weekday index labels. Keep only presentation-specific wrappers in
view modules if needed.

**Acceptance checks:**

- There is one weekday-index-to-label mapping.
- Admin and venue bootstrap UI still show the same labels.

### 14. Duplicate E2E Test Helpers

**Priority:** medium-low

**Finding:** Several Playwright specs define local versions of helpers that
already exist or should live in `e2e/test-helpers.ts`:

- WebAuthn base URL setup in many specs, including `e2e/passkeys.spec.ts`,
  `e2e/admin-invites.spec.ts`, and `e2e/mobile-experience.spec.ts`.
- Roster opener helpers parallel to `openRoster` in `e2e/test-helpers.ts:325`.
- `setFlatpickrDate` in `e2e/live-fragment-multiview.spec.ts:30` and
  `e2e/live-fragment-submit-regressions.spec.ts:14`.
- Profile leave section openers in multiple live-fragment, navigation, and
  mobile specs.
- Invite URL reconstruction in `e2e/admin-invites.spec.ts:16` and
  `e2e/venue-owner-onboarding.spec.ts:11`.
- Xero staff mapping database helper logic in
  `e2e/xero-staff-mapping.spec.ts:12`.

**Recommendation:** Expand `e2e/test-helpers.ts` with focused helpers:
`webauthnBaseURL`, `inviteUrlForCurrentBase`, `setFlatpickrDate`,
`openProfileLeaveSection`, and, if needed, an exported `runSql` helper. Replace
local helper copies incrementally by spec area to keep failures easy to trace.

**Acceptance checks:**

- New E2E specs use shared navigation/date/database helpers by default.
- Existing affected specs pass with the shared helpers.
- Helper names stay workflow-oriented rather than exposing unrelated Playwright
  internals.

### 15. Duplicate Focused Field Lookup In Frontend Runtime

**Priority:** medium-low

**Finding:** `findPreservedField` exists in both:

- `static/app-live-updates.js:74`
- `static/app.js:675`

The live-updates version accepts a configurable field-key attribute, while the
`app.js` version is tied to roster field keys.

**Recommendation:** Resolve this through finding 4. Keep the more generic lookup
in the live-update runtime and remove the legacy roster-specific duplicate once
the old auto-refresh compatibility path is gone.

**Acceptance checks:**

- Focus protection has one implementation.
- Roster focused fields and generic live fragments still preserve active input
  correctly.

### 16. Duplicate Xero Mapping Count Rendering

**Priority:** low

**Finding:** `Web/View/Admin/Index.hs` has two nearly identical count renderers:

- `renderXeroStaffMappingCounts`
- `renderXeroStaffMappingCountsOob`

The only meaningful difference is the presence of `hx-swap-oob`.

**Recommendation:** Extract a parameterized renderer, for example
`renderXeroStaffMappingCountsWith :: Maybe Text -> ...`, or a boolean
`oob` option if the call sites are clearer that way. This should be done during
the larger Xero admin view split in finding 2.

**Acceptance checks:**

- Xero staff mapping counts render from one helper.
- OOB and normal render paths keep the same DOM id and text.

### 17. Small Repeated Formatting Helpers

**Priority:** low

**Finding:** Several tiny helpers repeat across views:

- `boolText` in `Web/View/Timesheets/Edit.hs:55` and
  `Web/View/Timesheets/Index.hs:367`
- `boolParam` in `Web/View/Admin/Index.hs:1393`
- compact date formatting in `Web/View/Timesheets/Index.hs:363` and
  `Application/Helper/View.hs:163`
- UTC timestamp formatting in `Web/View/Admin/Index.hs:1412`,
  `Web/View/Support/Index.hs:591`, and `Web/View/Exports/Index.hs:399`
- `timeOfDayToMinutes` in `Web/View/Timesheets/Index.hs:445` and
  `Application/Helper/TimeRules.hs:28`

These are not urgent individually, but they add friction when behavior changes.

**Recommendation:** Consolidate only when touching the surrounding feature. Put
view formatting in `Application.Helper.View.*` and domain time math in
`Application.Helper.TimeRules`. Check the seconds behavior before merging the
two `timeOfDayToMinutes` variants, since the view version accounts for seconds
and the domain helper currently does not.

**Acceptance checks:**

- Shared helpers preserve existing display text.
- Domain helpers do not silently change rounding behavior.

### 18. Similar FWC MAPD Searchable Text Construction

**Priority:** low

**Finding:** Searchable text fields are built with repeated text-collection and
normalization patterns in:

- `Application/FwcMapd/Sync.hs:1082`
- `Application/Helper/FwcMapd.hs:111`

**Recommendation:** Extract a small pure helper such as
`searchableTextFields :: [Text] -> Text`, or a more domain-specific
classification searchable-text helper if call sites need stronger naming.

**Acceptance checks:**

- FWC searchable text output remains byte-for-byte equivalent for representative
  fixtures.
- The sync path and helper path cannot drift.

### 19. Fixture Builder Overlap Between App And Test Support

**Priority:** low

**Finding:** `Application/Support.hs` and `Test/Support.hs` overlap on fixture
builder concepts such as roster weeks, roster days, slots, timesheet entries,
leave requests, pay levels, and synthetic penalties.

Some behavior is intentionally different. For example, test support creates
linked staff for completed-profile users and reset helpers include test-only
tables such as passkeys.

**Recommendation:** Avoid a broad unification. Extract only low-level,
side-effect-free defaults or record-builder primitives where the production
seed path and tests truly need the same shape. Keep destructive resets and
test-only conveniences in test support.

**Acceptance checks:**

- Production code does not import destructive test helpers.
- Test fixture conveniences remain explicit and easy to reason about.
- Shared builders are small, pure, and covered by the tests that use them.

## Lint Follow-Up

`bash ./bin/in-env lint` produced 206 hints. Defer broad lint cleanup until the
structural work above is complete. When sweeping lint, prefer one narrow commit
per area and avoid mixing mechanical style changes with behavior changes.

Low-risk categories:

- redundant `.id` after record-dot syntax
- eta reduction
- `when (not ...)` to `unless`
- small import consolidations

Avoid adding language extensions only to satisfy cosmetic suggestions such as
tuple sections unless the surrounding module already uses that style.

## Non-Goals

- Do not refactor the SQL pay engine simply because it is implemented in
  `Application/Schema.sql`; the helper layer already treats it as the canonical
  pay-calculation boundary.
- Do not replace global in-memory live-update registries unless there is a
  concrete multi-process/runtime requirement. They are a watchlist item, not the
  first cleanup target.
- Do not run whole-file formatting as part of these slices unless the slice is
  already touching that file.

## Suggested Verification Matrix

- After Haskell changes: `bash ./bin/in-env typecheck`
- After controller/job changes: focused `bash ./bin/in-env hspec-test --match "..."`
- After admin/Xero/invite UI changes: focused Playwright specs such as
  `bash ./bin/in-env e2e e2e/admin-invites.spec.ts e2e/xero-staff-mapping.spec.ts`
- After frontend runtime changes: live-fragment E2E specs and roster focused-field
  regressions.
- Before merging a cleanup slice: `bash ./bin/in-env lint` and
  `bash ./bin/in-env format`
