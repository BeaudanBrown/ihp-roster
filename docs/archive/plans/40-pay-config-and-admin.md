# Pipeline 40 — Pay Config and Admin

Read after `IMPLEMENTATION_PLAN.md`. Coordinate with pipeline 30 before locking approval behavior.

## Goal

Implement canonical SQL pay logic together with immutable pay/config snapshot versions created by the venue admin bulk-save workflow.

## Scope

- SQL pay functions
- Haskell orchestration
- venue admin configuration screens
- immutable pay/config snapshot versions
- version binding for approved records and exports
- wage/hour summaries

## Chosen Model

The selected historical model is:

- venue admin edits pay-relevant configuration in bulk on the admin page
- unsaved edits remain draft UI state only
- save creates a new immutable pay/config snapshot version
- approved timesheets and exports reference the snapshot version used
- later edits do not rewrite earlier approved/exported context

## Dependencies

- venue-scoped config ownership from pipeline 10
- export metadata support from pipeline 10

## Slices

### A.7 Historical pay/config stability
- **Status:** [x]
- **Goal:** Ensure old pay results and exports remain explainable after later configuration changes.
- **Deliverables:**
  - Add venue-admin-created pay/config snapshot versions.
  - Update SQL/Haskell pay logic to resolve against stored snapshot version context.
  - Add snapshot version metadata to payroll-adjacent exports.
  - Define venue admin bulk-edit/save behavior for draft edits versus saved versions.
- **Acceptance checks:**
  - Historical periods remain reproducible after later pay/config changes.
  - Exports carry enough metadata to explain which rule set produced them.
- **Completion notes:** Added `pay_config_snapshots` plus `timesheet_entries.pay_config_snapshot_id` in `Application/Schema.sql`; extended `Application/Helper/Pay.hs` and SQL pay functions so approved entries resolve against stored snapshot context while draft entries continue using current config; updated admin, timesheet approval, and export flows to create/bind immutable snapshot versions and carry snapshot metadata; added coverage in `Test/PaySpec.hs`, `Test/Controller/AdminSpec.hs`, `Test/Controller/ExportsSpec.hs`, `Test/Controller/TimesheetsSpec.hs`, `Test/SchemaSpec.hs`, and `Test/Support.hs`.

### 6.1 SQL function scaffolding for canonical pay math
- **Status:** [x]

### 6.2 Pay segmentation and weekday windows
- **Status:** [x]

### 6.3 Weekend multiplier with penalty stacking
- **Status:** [x]

### 6.4 Haskell orchestration layer for pay outputs
- **Status:** [x]

### 7.1 Admin screens for config tables
- **Status:** [x]
- **Completion notes:** Added venue-scoped admin screens and controller actions for pay levels, shift types, pay level day rules, slot names, and day names, including active/inactive support, current-venue validation, and snapshot-context messaging. Coverage lives in `Test/Controller/AdminSpec.hs`.

### 7.2 Venue configuration editor
- **Status:** [ ]
- **Goal:** Make the admin page the normal workflow that creates new pay/config snapshot versions on save.

### 8.2 Wage/hour summary outputs
- **Status:** [ ]

## Primary Files

- `Application/Schema.sql`
- `Application/Helper/Pay.hs`
- `Web/Controller/Admin/*` or equivalent admin controllers
- `Web/View/Admin/*` or equivalent admin views
- `Test/PaySpec.hs`
- export-related controllers/helpers where snapshot metadata is attached
