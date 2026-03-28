# Pipeline 47 — Payroll Generation Parity

Read after `IMPLEMENTATION_PLAN.md` and `plans/45-payroll-report-exports.md`.

## Goal

Add a durable payroll-generation correctness suite that proves one canonical payroll CSV export for the current primary/only venue staff group is correct through deterministic multi-staff fixtures and exact output assertions.

Status on `2026-03-27`: completed locally for the current single-CSV scope. The lane delivered reusable payroll fixtures, exact `staff_hours` CSV parity fixtures, explicit inclusion/bucketing assertions, snapshot-drift stability coverage, and mixed-snapshot metadata coverage. Future multi-group exports remain a separate backlog lane.

## Why This Exists

The current payroll export stack is implemented and browser-covered, but the correctness pyramid is still upside down for payroll math:

- `Test/Controller/ExportsSpec.hs` proves happy paths but still uses ad hoc setup and mostly substring checks
- `Test/PaySpec.hs` proves selected payload behavior but not full report output shape
- Playwright proves the exports workflow, not complete payroll parity

For payroll artifacts, exact generated files matter more than just “the button worked.” The strongest verification surface should therefore be fast controller-level parity specs that exercise the real export path and compare exact CSV contents for the canonical export. Historical filtered variants can remain as regression checks, but they are not the active product target.

## Target Verification Model

Use three layers with distinct responsibilities:

1. Controller parity layer
   - canonical source of truth for the generated payroll CSV artifact
   - deterministic canonical fixture week
   - exact CSV output assertions

2. Pay helper / schema layer
   - focused tests for pay resolution and edge cases
   - snapshot and segmentation behavior

3. Browser layer
   - thin workflow coverage only
   - generation/download path still works through the real UI

## Canonical Fixture Week

Create one reusable fixture week rich enough to drive the canonical payroll CSV and its edge cases:

- multiple staff
- at least two pay levels
- multiple shift types
- historical filtered rows may remain in the fixture for regression purposes, but not as the primary target
- weekday override to a different pay level
- evening and after-midnight entries
- weekend entries
- unpaid break subtraction
- approved and unapproved entries
- one excluded/trial-style row
- snapshot-pinned approvals

This fixture should live in test support, not inside one spec.

## Planned Deliverables

### 1. Reusable payroll fixture support

- new helper module under `Test/Support/`
- canonical payroll fixture week builders
- helpers for generating payroll export jobs and decoding file outputs

### 2. Exact-output single payroll CSV parity

- dedicated parity spec module
- expected fixtures committed under `Test/Fixtures/exports/`
- exact comparison for:
  - canonical `staff_hours`
- assertions cover:
  - header
  - row ordering
  - grouping by staff and effective pay level
  - day columns
  - totals
  - exclusions

### 3. Edge-case coverage

- approved vs unapproved inclusion
- shift-type/day override resolution
- break subtraction
- weekend and time-window segmentation
- snapshot stability after config changes
- mixed-version export metadata where reachable

### 4. Historical regression alignment

- keep any existing historical filtered-variant coverage clearly marked as regression-only
- do not let those checks redefine the active product scope

## Recommended File Layout

- `Test/Support/PayrollFixtures.hs`
- `Test/Controller/PayrollExportParitySpec.hs`
- `Test/Fixtures/exports/staff_hours-expected.csv`

Adjust naming if a better grouped layout emerges, but keep fixtures easy to inspect in diffs.

## Acceptance Checks

Done when:

1. payroll export correctness no longer depends mainly on substring assertions in `ExportsSpec`
2. there is one canonical reusable payroll fixture week used across parity specs
3. exact-output parity exists for the canonical `staff_hours` CSV
4. pay edge cases are covered below the browser layer
5. any remaining filtered-variant coverage is clearly treated as regression-only rather than as the active product target
