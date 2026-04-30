# Pipeline 61 - View Helper Split

Read after `IMPLEMENTATION_PLAN.md`, `AGENTS.md`, and `Application/AGENTS.md`.

## Goal

Make `Application/Helper/View.hs` a compatibility re-export wrapper instead of
a mixed implementation module. The split should improve agent navigation without
changing rendered HTML, routes, form behavior, or imports outside this helper
boundary unless a narrow import makes a call site clearer.

## Current Shape

`Application/Helper/View.hs` currently re-exports focused modules but still owns
several unrelated concerns:

- audience and role rendering helpers
- staff display-name helpers
- award/pay-rate display labels
- generic date/time/url formatting helpers
- quarter-hour time picker config and rendering
- timesheet entry forms, field errors, and overlay dialogs
- staff edit overlay dialogs

Existing focused modules under `Application/Helper/View/` are:

- `Chrome.hs`
- `Leave.hs`
- `Overlay.hs`
- `Status.hs`
- `Toast.hs`
- `VenueBootstrap.hs`

## 2026-04-30 Consolidation Note

The health scan kept this as the canonical lane for `Application.Helper.View`.
Do not add new helper implementations to the compatibility wrapper while this
pipeline is open.

Follow-on tickets should wait until the wrapper split is complete:

- `ir-esmn` adds small chrome/panel defaults once `Chrome.hs` is the clear home.
- `ir-2vyr` adds optional-OOB rendering helpers once the relevant view helper
  module is stable.

## Proposed Module Boundaries

- `Application.Helper.View.Audience`
  - `currentUserIsManager`
  - `currentUserIsAdmin`
  - `currentUserIsSupportAdmin`
  - `ViewAudience`
  - `currentUserMatchesAudience`
  - `renderWhenAudience`

- `Application.Helper.View.Staff`
  - `isTrialStaff`
  - `linkedActiveStaffForRosterPanel`
  - `staffDisplayName`
  - `staffDisplayBaseName`
  - `normalizedStaffDisplayBaseName`
  - `renderStaffLastInitial`
  - `nonBlankText`

- `Application.Helper.View.Awards`
  - `awardLevelDisplayLabel`
  - `awardLevelOptionLabel`
  - `awardLevelRateLabels`
  - `employmentBasisShortLabel`
  - `formatHourlyRate`

- `Application.Helper.View.Format`
  - `formatDateDisplay`
  - `formatDayMonthDisplay`
  - `formatUtcTimestamp`
  - `boolParam`
  - `appendQueryParams`

- `Application.Helper.View.TimePicker`
  - `TimePickerConfig`
  - `timePickerModalId`
  - quarter-hour option/range helpers
  - storage/display conversion helpers
  - time picker modal, field, control, and step button rendering

- `Application.Helper.View.Timesheets`
  - `timesheetModalTitle`
  - `renderTimesheetForm`
  - timesheet form fields and select options
  - `renderFieldError`
  - `hasErrorFor`
  - timesheet entry modal/dialog helpers

- `Application.Helper.View.StaffDialogs`
  - `renderStaffEditPageModal`
  - `renderStaffEditDialog`

Keep `Application.Helper.View` as:

```haskell
module Application.Helper.View
    ( module Application.Helper.View.Audience
    , module Application.Helper.View.Awards
    , module Application.Helper.View.Chrome
    , module Application.Helper.View.Format
    , module Application.Helper.View.Leave
    , module Application.Helper.View.Overlay
    , module Application.Helper.View.Staff
    , module Application.Helper.View.StaffDialogs
    , module Application.Helper.View.Status
    , module Application.Helper.View.TimePicker
    , module Application.Helper.View.Timesheets
    , module Application.Helper.View.Toast
    ) where
```

## Implementation Order

1. Add the new modules with explicit export lists and move leaf helpers first:
   `Format`, `Staff`, and `Awards`.
2. Move `Audience`, then update `Web/RosterWeeks/Capabilities.hs` to import it
   directly or continue through the compatibility wrapper.
3. Move `TimePicker`; keep all IDs, classes, data attributes, and option labels
   byte-for-byte compatible.
4. Move `Timesheets`; import `Audience`, `Overlay`, `TimePicker`, and `Format`
   from the focused modules rather than from the wrapper.
5. Move `StaffDialogs`; import `Overlay` and `Web.Types`/`Web.Routes` directly.
6. Reduce `Application/Helper/View.hs` to re-exports only.
7. Run `bash ./bin/in-env typecheck`.
8. Run focused Hspec for the helper-visible behavior:
   `bash ./bin/in-env hspec-test --match "Schema" --match "TimesheetsController"`.
9. If the split changes import surfaces in roster/timesheet views, run the
   relevant E2E specs after the current dirty worktree settles.

## Guardrails

- Do not change HTML structure, CSS classes, modal IDs, data attributes, or form
  field names during the split.
- Do not combine this with visual cleanup or form behavior changes.
- Preserve the compatibility wrapper so existing wildcard imports from
  `Application.Helper.View` keep compiling.
- Prefer explicit export lists in new modules so future helpers have an obvious
  home.
- If two modules need the same tiny helper, put it in the more general focused
  module only when there is a real second caller; avoid creating a catch-all
  utility module during this pass.

## Acceptance Checks

- `Application/Helper/View.hs` contains no helper implementations.
- New helper modules are grouped by concern and have explicit export lists.
- Existing call sites compile without broad import churn.
- Timesheet new/edit overlay forms render the same field names and modal mount
  targets as before.
- Roster staff labels still disambiguate duplicate preferred/base names.
