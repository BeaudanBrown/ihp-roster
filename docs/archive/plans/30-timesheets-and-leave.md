# Pipeline 30 — Timesheets and Leave

Read after `IMPLEMENTATION_PLAN.md`, plus pipelines 00 and 10.

## Goal

Deliver timesheet and leave workflows that are venue-scoped, approval-aware, and correction-safe.

## Scope

- timesheet CRUD and validation
- approval/unapproval workflow
- edit windows
- leave lifecycle and roster recalculation
- correction-safe history for timesheets and leave
- venue-role change history when it affects business records

## Dependencies

- venue membership auth helpers
- venue-scoped query enforcement
- audit event infrastructure
- pay/config snapshot contract from pipeline 40

## Slices

### 5.1 Timesheet CRUD with exact 15-minute validation
- **Status:** [x]

### 5.2 Timesheet approval workflow
- **Status:** [x]

### 5.3 Staff edit window constraints
- **Status:** [x]

### 5.4 Leave request lifecycle + roster recalculation trigger
- **Status:** [x]

### A.6 Correction-safe timesheets, leave history and role changes
- **Status:** [x]
- **Goal:** Replace destructive employment-record behavior with provenance-preserving flows.
- **Deliverables:**
  - Choose and implement a correction-safe model for timesheets.
  - Add leave status history or equivalent provenance model.
  - Add durable audit or event history for venue membership role changes.
  - Update UI and tests for corrected/superseded record behavior.
- **Acceptance checks:**
  - Payroll-adjacent changes are not silently destructive.
  - Approval and correction history remain attributable and test-covered.
- **Completion notes:** Added `timesheet_entry_versions`, `leave_request_events`, and `venue_membership_role_events` in `Application/Schema.sql`; wired shared provenance helpers through `Application/Helper/Controller.hs`; updated `Web/Controller/Timesheets.hs`, `Web/Controller/LeaveRequests.hs`, `Web/Controller/Users.hs`, and related views to block destructive deletion of approved/reviewed records; extended `Test/Controller/TimesheetsSpec.hs`, `Test/Controller/LeaveRequestsSpec.hs`, `Test/Controller/UsersSpec.hs`, and `Test/SchemaSpec.hs`.

## Primary Files

- `Web/Controller/Timesheets.hs`
- `Web/View/Timesheets/*`
- `Web/Controller/LeaveRequests.hs`
- `Web/View/LeaveRequests/*`
- `Application/Helper/Controller.hs`
- `Test/PaySpec.hs`
- relevant controller/integration tests
