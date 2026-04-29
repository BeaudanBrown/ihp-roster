# Pipeline 46 — Payroll Export E2E Hardening

Read after `IMPLEMENTATION_PLAN.md` and `plans/45-payroll-report-exports.md`.

## Goal

Add strong browser-level verification for the payroll/report export surface so the newly landed parity work is exercised end-to-end through the real UI, not only through controller/spec coverage.

## Why This Exists

Controller coverage for payroll/report exports is now good, but the browser layer is still largely untested:

- no Playwright spec opens the exports page and generates payroll exports
- no browser test downloads and inspects the `staff_hours`, `kitchen`, or `wage` files
- no browser test drives report-definition create/update flows
- no browser test locks in role-based visibility and denial behavior on the exports page

The current risk is not the SQL/controller engine alone. It is the real user workflow: page render, week selection, form wiring, success/error messaging, download handling, and visible report-definition state.

## Coverage Target

The intended browser suite should cover these surfaces:

1. Exports page happy paths for a manager user
   - page render
   - current/previous/next week navigation
   - generating `staff_hours`
   - generating `kitchen`
   - generating `wage`
   - job list updates
   - download filename and content sanity checks

2. Report-definition management for a venue admin
   - bootstrap definitions visible
   - create a new report definition
   - update an existing report definition
   - edit shift-type filters
   - toggle active/inactive
   - resulting change in visible generate actions for manager users

3. Role and authorization boundaries
   - manager can access exports and generate reports
   - manager cannot see or use report-definition management controls
   - worker/non-manager cannot access exports
   - current-venue scope is respected for report definitions and jobs

4. High-value edge cases
   - inactive report definitions disappear from the manager generation surface
   - repeated generation appends/refreshes export jobs without breaking downloads
   - CSV and ZIP contents stay deterministic for representative seeded data

## Concrete Spec Plan

Prefer a small number of focused Playwright files over one giant spec:

1. `e2e/exports-payroll-downloads.spec.ts`
   - seeded manager login
   - open exports page
   - assert payroll report cards are present
   - change week selection
   - generate `staff_hours`
   - verify download filename and representative CSV rows
   - generate `kitchen`
   - verify filtered CSV shape
   - generate `wage`
   - verify ZIP filename, day CSV filenames, and representative hourly cells

2. `e2e/exports-report-definitions.spec.ts`
   - seeded venue admin login
   - assert management section visible
   - create a report definition with shift-type filters
   - update slug/name/engine/active state/filter set
   - verify visible export actions reflect the change
   - verify inactive definitions no longer appear for a manager session

3. `e2e/exports-authz.spec.ts`
   - manager cannot see management section
   - direct POST/interaction attempts for management fail safely
   - worker is denied exports access
   - cross-venue jobs/definitions are not shown when current venue differs

## Fixture Strategy

Add deterministic export/payroll fixture support rather than relying on ad hoc browser mutation setup.

Needed fixture characteristics:

- a seeded manager who can generate exports
- a seeded venue admin who can manage report definitions
- representative approved weekly timesheet data that yields:
  - visible `staff_hours` rows across at least two pay levels
  - visible `kitchen` filtered rows
  - visible hourly ZIP overlap across at least two shift types
- stable shift-type ordering for ZIP columns
- stable week offset / week start expectations

Prefer fixed IDs and `ON CONFLICT DO UPDATE` in `e2e/fixtures/seed.sql`.

## Helper Strategy

Add reusable helpers in `e2e/test-helpers.ts` for:

- navigating to exports with a ready selector
- selecting previous/current/next export week
- triggering a download and returning the file path
- reading downloaded CSV text
- opening ZIP downloads and asserting filenames / representative entries

Do not duplicate download parsing logic inside every spec.

## Acceptance Checks

Done when:

1. Playwright covers manager payroll generation/download flows for `staff_hours`, `kitchen`, and `wage`
2. Playwright covers venue-admin report-definition management
3. Playwright covers manager/worker authorization boundaries on the exports surface
4. download assertions inspect real CSV/ZIP contents, not just “download happened”
5. the new specs are stable under the repo's serial `bash ./bin/in-env e2e` model
