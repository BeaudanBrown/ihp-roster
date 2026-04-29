# Pipeline 60 - V1 Schema Hardening

Read after `IMPLEMENTATION_PLAN.md`, `plans/40-pay-config-and-admin.md`,
`plans/45-payroll-report-exports.md`, and
`plans/55-record-retention-soft-deletion.md`.

## Goal

Lock down the V1 database schema so it is robust, clear, maintainable, and
ready to support paid venue data without relying on controller code for core
business invariants.

This plan captures the read-only schema review from 2026-04-29. No schema or
code changes were made as part of the review.

## Scope

- tenant and venue-boundary integrity
- payroll snapshot reproducibility
- redundant or legacy schema cleanup
- lifecycle and deletion-state clarity
- finite-state/status constraints
- uniqueness and check constraints
- query-supporting indexes
- spec/schema drift before V1 lock

## Non-Goals

- Do not implement these changes directly from this file without a migration
  plan.
- Do not change product behavior silently; each cleanup candidate needs an
  explicit decision.
- Do not remove historical or payroll-adjacent data without a retention review.
- Do not broaden the app into public self-serve venue creation as part of schema
  hardening.

## IHP Compatibility Decisions

Checked against the local IHP docs and parser/source on 2026-04-29:

- `Application/Schema.sql` remains the source of truth. Every schema change must
  be represented there and in a production migration; fresh dev databases load
  `Schema.sql` directly, while migrations update existing databases.
- Hand-written SQL is acceptable for complex constraints, expression indexes,
  partial indexes, functions, and triggers when the Schema Designer UI is not
  expressive enough. This repo already uses that pattern.
- Keep advanced SQL parser-safe. After every schema slice, run
  `regen-types`, `make db`, and a dev-server restart/wait so both the schema
  compiler and IHP's startup parser see the final `pg_dump` shape.
- Do not rely on composite foreign keys in `Schema.sql` as the default tenant
  integrity mechanism. The local IHP parser's foreign-key parser handles a
  single referencing column and a single referenced column, so composite FKs may
  break generated-code parsing or Schema Designer operations unless proven in a
  small spike. Prefer single-column FKs plus parser-safe trigger checks for
  cross-column venue/group invariants.
- Expression and partial indexes are supported by IHP's parser and are already
  used in this schema. Prefer them over unsupported constraint syntax for
  nullable uniqueness.
- Avoid `NULLS NOT DISTINCT` and `CREATE INDEX CONCURRENTLY` in `Schema.sql`
  unless a parser/migration spike proves support. `CONCURRENTLY` also conflicts
  with IHP's default transactional migration wrapper.
- Custom Postgres enums are supported, but keep the repo's existing parser
  guardrails: avoid enum names that start with built-in SQL type tokens and
  avoid enum constructor collisions with generated model constructors.
- Keep CHECK constraints in the parser-safe explicit-OR style rather than
  `IN (...)`, because `pg_dump` may rewrite `IN` checks into expressions the
  vendored parser does not accept.

## Priority Order

1. Make approved payroll calculations fully snapshot-reproducible.
2. Add database-level tenant/venue integrity checks.
3. Resolve unused or legacy tables/columns before V1.
4. Add missing CHECK constraints and active-row uniqueness rules.
5. Tighten finite-state text columns and nullable uniqueness.
6. Add high-value query indexes after the data model settles.
7. Align stale specs, tests, and helper names with the final V1 schema.

## Findings And Recommendations

### 1. Pay Snapshots Are Not Yet Sufficiently Reproducible

**Priority:** critical

**Finding:** `timesheet_entries.pay_config_snapshot_id` is set when entries are
approved, and snapshots store venue config, award levels, rates, and shift
types. `calculate_timesheet_pay` has started reading the snapshot for display
context such as shift-type name, but it still resolves core payroll values from
live tables:

- staff default and shift override pay level come from current `staff` and
  `shift_types`
- award level labels and award ids come from current `award_levels`
- base, penalty, and time allowance rates come from current rate projection
  tables
- `resolve_effective_pay_level_snapshot` exists but is not used by the
  canonical calculation

This means some historical exports can change after later pay-config edits even
when the entry is snapshot-pinned.

**Recommendation:** Choose one V1 historical model:

- Fully JSON-backed: when `pay_config_snapshot_id` is present, resolve pay
  level, labels, base rates, penalty rates, and time allowances from the JSON
  snapshot.
- Normalized snapshot tables: create immutable snapshot child tables for shift
  types, award levels, base rates, penalty rates, and allowances, then calculate
  against those rows.

**Acceptance checks:**

- Mutating a staff default award level after approval does not alter approved
  export output.
- Mutating a shift type override after approval does not alter approved export
  output.
- Mutating base rates, penalty rates, and time allowances after approval does
  not alter approved export output.
- `calculate_timesheet_pay` and export helpers use the same snapshot semantics.
- `pay_config_snapshots.snapshot`, `version_number`, and `version_label` cannot
  be updated after creation except through an explicit maintenance path.

### 2. Venue Integrity Is Mostly Enforced In Haskell, Not The Database

**Priority:** critical

**Finding:** Controllers and helpers consistently scope records to
`currentVenueId`, but many schema relationships can still connect records from
different venues because the database only has independent foreign keys.

Examples:

- `roster_weeks.venue_id` can disagree with `roster_group_id`
- `slot_names.venue_id` can disagree with `roster_group_id`
- `staff_roster_groups.staff_id` can point to a different venue than
  `roster_group_id`
- `staff_shift_preferences` can mix a staff member, roster group, and slot name
  across venues or groups
- `leave_requests.venue_id` can disagree with `staff_id`
- `timesheet_entries.venue_id` can disagree with `staff_id`, `shift_type_id`,
  or `pay_config_snapshot_id`
- report-definition filters and Xero mappings can reference records outside
  their stored `venue_id`

**Recommendation:** Add tenant-integrity protection in the database. Because
the local IHP parser handles single-column foreign-key constraints, use ordinary
single-column FKs for existence and add parser-safe trigger checks for
cross-column venue/group consistency.

Composite FKs are not the default V1 choice. Use one only after a small spike
proves the exact `Schema.sql`, generated types, migration, `pg_dump` round trip,
and dev-server startup all work. If used, account for the supporting
referenced-side constraints they require. For example, referencing
`staff (id, venue_id)` means `staff` also needs a unique constraint or unique
index on `(id, venue_id)` even though `id` is already globally unique.

**Candidate trigger-checked invariant families:**

- `roster_weeks.venue_id` and `slot_names.venue_id` must match their
  `roster_group_id`
- `staff_roster_groups.staff_id` must belong to the same venue as
  `roster_group_id`
- `staff_shift_preferences.staff_id`, `roster_group_id`, and `slot_name_id`
  must agree on venue, and `slot_name_id` must belong to the referenced roster
  group
- `leave_requests.venue_id` must match `staff_id`
- `timesheet_entries.venue_id` must match `staff_id`, `shift_type_id`, and
  `pay_config_snapshot_id` when a snapshot is present
- report-definition filters and Xero mappings must not point at records outside
  their stored `venue_id`

**Acceptance checks:**

- Direct SQL cannot create a timesheet whose staff or shift type belongs to a
  different venue.
- Direct SQL cannot create a roster week for one venue with a roster group from
  another venue.
- Direct SQL cannot create staff roster-group membership across venues.
- Existing controller venue-isolation tests still pass.

### 3. `staff_availability` Is Under-Integrated

**Priority:** high

**Finding:** `staff_availability` exists, is seeded, and appears in tests and
hard-delete protection, but current roster option/conflict logic uses
`staff_shift_preferences` and leave requests. The spec still says assignment
filtering should hide staff with day/date unavailability.

**Recommendation:** Decide before V1:

- Integrate `staff_availability` into roster conflicts and staff filtering as
  the source for recurring and date-specific availability restrictions.
- Or remove/defer `staff_availability` and make `staff_shift_preferences` the
  single V1 preference/availability model.

**If kept, add constraints:**

- exactly one of `weekday_index` or `specific_date` must be set
- `weekday_index` must be 0..6
- one active row per staff/date or staff/weekday availability key
- staff and venue must match

**Acceptance checks:**

- Staff with explicit unavailable weekdays are hidden when the filter is active.
- Staff with date-specific unavailability are hidden on the matching roster day.
- Availability rows cannot be created for a staff member outside the venue.

### 4. Active Roster Slot Uniqueness Is Missing

**Priority:** high

**Finding:** Roster rendering builds a map by
`(roster_day_id, row_index, slot_name_id)`, and roster sync code assumes one
active cell per key. The schema does not enforce this.

**Recommendation:** Add a partial unique index:

```sql
CREATE UNIQUE INDEX idx_roster_slots_active_cell
    ON roster_slots (roster_day_id, row_index, slot_name_id)
    WHERE deleted_at IS NULL;
```

Also add CHECK constraints for `row_index >= 0`, `slot_sort_order >= 0`, and
`duration_minutes IS NULL OR duration_minutes >= 0`.

**Acceptance checks:**

- Concurrent row/slot sync cannot produce duplicate active cells.
- Soft-deleted historical slots do not block recreating the active cell.

### 5. Date And Weekday Invariants Need CHECK Constraints

**Priority:** high

**Finding:** Several fields are treated as bounded values by code and specs but
are unconstrained in the database.

**Recommendation:** Add parser-safe CHECK constraints for:

- `day_names.weekday_index BETWEEN 0 AND 6`
- `venue_config.roster_week_starts_on BETWEEN 0 AND 6`
- `roster_days.day_offset BETWEEN 0 AND 6`
- `staff_availability.weekday_index BETWEEN 0 AND 6`
- `staff_shift_preferences.weekday_index BETWEEN 0 AND 6`
- `staff.ideal_shifts_per_week BETWEEN 0 AND 7`
- `venue_config.staff_timesheet_edit_window_days >= 0`
- `venue_config.late_to_early_min_start_gap_minutes >= 0`
- `leave_requests.end_date > start_date` if `end_date` remains the exclusive
  "available again" date

**Acceptance checks:**

- Invalid weekday/day offsets fail at database level.
- Leave UI and schema agree on exclusive end-date semantics.

### 6. Timesheet Entry Shape Is Mostly Controller-Enforced

**Priority:** high

**Finding:** Controller validation enforces quarter-hour times, max duration,
break containment, and approval metadata. The database does not enforce the
basic state shape.

**Recommendation:** Add DB constraints for the durable invariants:

- `break_minutes >= 0`
- if `had_break = false`, break times are null and `break_minutes = 0`
- if `had_break = true`, break start/end are present and `break_minutes > 0`
- approved entries have `approved_at`, `approved_by_user_id`, and
  `pay_config_snapshot_id`
- unapproved entries do not carry stale approval metadata unless a specific
  product decision says they may
- start/end/break values are 15-minute aligned if this can be expressed
  cleanly with `EXTRACT`

Keep complex "break strictly inside overnight shift" validation in Haskell
unless a SQL helper makes it clear.

**Acceptance checks:**

- Direct SQL cannot create an approved entry without snapshot/approver
  metadata.
- Direct SQL cannot create inconsistent break fields.
- Existing controller validation tests still cover friendly user-facing errors.

### 7. Nullable UNIQUE Constraints Do Not Enforce Intended Uniqueness

**Priority:** high

**Finding:** Postgres permits duplicate rows when any UNIQUE column is null.
This weakens several current uniqueness rules:

- `public_holidays (jurisdiction, holiday_date, name, region)` allows duplicate
  statewide holidays with `region IS NULL`
- `award_level_base_rates` uniqueness includes nullable `operative_from` and
  `operative_to`
- `award_level_penalty_rates` uniqueness includes nullable operative dates
- `award_time_penalty_allowances` uniqueness includes nullable operative dates

**Recommendation:** Use one of:

- expression unique indexes with `COALESCE`
- non-null sentinel values such as empty text for `region`
- generated normalized key columns

Do not use `NULLS NOT DISTINCT` for V1 unless a parser and migration spike
proves IHP accepts it in `Schema.sql`, generated types, migration application,
and dev-server startup. Expression unique indexes are the safer IHP-compatible
default.

**Acceptance checks:**

- Running the public-holiday sync twice cannot create duplicate statewide rows.
- Running FWC/MAPD projection twice cannot create duplicate open-ended rate
  rows under concurrent or repeated syncs.

### 8. `users.user_role` Is Legacy And Redundant

**Priority:** high

**Finding:** Runtime authorization comes from `venue_memberships.venue_role`
and platform support access comes from `users.platform_role`. Tests explicitly
assert that `users.user_role` is not venue authority. `users.user_role` remains
in schema, fixtures, helper parsers, and some display naming.

**Recommendation:** Prefer removing `users.user_role` before V1. If removal is
too disruptive immediately, mark it deprecated and stop using helper names that
imply it is authority.

**Migration shape:**

1. Replace remaining display use with venue membership role or staff employment
   labels.
2. Remove `UserRole` helper parsing once tests no longer depend on it.
3. Drop `users.user_role`.
4. Update seed/profile CSV column lists and fixtures.

**Acceptance checks:**

- Venue access tests still prove membership-scoped authority.
- Staff panel role display is driven by `venue_memberships.venue_role`.
- No production code reads `users.user_role`.

### 9. `day_names` And Pay-Level Day-Rule References Need A Product Decision

**Priority:** medium-high

**Finding:** `day_names.name` appears not to be used for display; admin view
labels render from `weekday_index`. The specs and test helpers still mention
`pay_level_day_rules`, but the helper now models a "day rule" by setting
`shift_types.override_award_level_id`, ignoring the `DayName` argument.

**Recommendation:** Choose one V1 direction:

- Keep day names: make custom day labels real in admin, roster, reports, and
  snapshots.
- Simplify: remove the mutable `name` concept and rely on `weekday_index`.
- Reintroduce explicit day-specific pay-level override rules if the product
  still needs them.
- Otherwise update specs and helper names so `shift_types.override_award_level_id`
  is the documented model.

**Acceptance checks:**

- Specs do not mention `pay_level_day_rules` unless the table exists.
- Tests no longer create fake day rules through a helper that only updates shift
  types.
- Pay snapshots contain every field needed for the selected model.

### 10. `roster_groups.is_default` Is Derived But Not Enforced

**Priority:** medium-high

**Finding:** App code derives the default roster group from the top active group
and updates `is_default`. The database does not enforce one default active group
per venue.

**Recommendation:** Either:

- add a partial unique index for one active default per venue, or
- remove `is_default` and derive default from active sort order everywhere.

**Candidate index:**

```sql
CREATE UNIQUE INDEX idx_roster_groups_one_active_default
    ON roster_groups (venue_id)
    WHERE is_default = TRUE
      AND is_active = TRUE
      AND archived_at IS NULL;
```

**Acceptance checks:**

- Direct SQL cannot create two active default roster groups for one venue.
- Deactivating the default group deterministically moves default to the next
  active group.

### 11. Shift Type Names Need Active Uniqueness

**Priority:** medium-high

**Finding:** `roster_groups` and `slot_names` have active-name uniqueness, but
`shift_types` does not. Admin code permits shift types to be created and
renamed per venue.

**Recommendation:** Add a partial unique index:

```sql
CREATE UNIQUE INDEX idx_shift_types_active_name
    ON shift_types (venue_id, name)
    WHERE is_active = TRUE
      AND archived_at IS NULL;
```

Consider case-insensitive uniqueness if admin input is not otherwise
normalized.

**Acceptance checks:**

- Active duplicate shift type names in one venue are rejected.
- Inactive/archived historical shift types do not block reusing a name.

### 12. Text Status Columns Should Be Constrained

**Priority:** medium

**Finding:** Some finite-state columns are constrained or modeled as Postgres
enums, but others are plain text:

- `export_jobs.export_type`
- `export_jobs.status`
- `export_jobs.file_encoding`
- `export_jobs.delivery_method`
- `xero_payroll_calendar_selections.calendar_status`
- `xero_pay_item_account_code_selections.selection_status`
- `xero_pay_item_requirement_records.penalty_kind`

**Recommendation:** Add parser-safe CHECK constraints or Postgres enums where
the IHP parser and generated constructor names are safe. Follow the existing
repo guidance to avoid `IN (...)` checks that `pg_dump` rewrites into parser-
hostile `ANY(ARRAY ...)` expressions.

**Acceptance checks:**

- Direct SQL cannot insert unknown export or Xero mapping statuses.
- SchemaSpec keeps the finite-state helper lists in sync with SQL constraints.

### 13. Invitation Tables Are Similar But Probably Worth Keeping Separate

**Priority:** medium

**Finding:** `venue_invitations` and `venue_onboarding_invitations` share many
columns. They represent different workflows: joining an existing venue versus
creating a new venue.

**Recommendation:** Keep separate tables for clarity unless there is a strong
reason to unify them. Add duplicate-pending protection:

- active pending `venue_invitations` should be unique by
  `(venue_id, lower(email))`
- active pending onboarding invitations should be unique by `lower(email)`
  while pending and unexpired, if the product wants one open owner invite per
  email

**Acceptance checks:**

- Repeated invite submissions do not create duplicate pending invites.
- Accepted/revoked/expired invitations remain historically visible.

### 14. Lifecycle Columns Need A Consistent V1 State Model

**Priority:** medium

**Finding:** The schema now has a mix of `is_active`, `archived_at`,
`deleted_at`, `status`, `closed_at`, `deactivated_at`, and retention columns.
Some are actively used; some are future placeholders.

**Recommendation:** Document and enforce the V1 state model:

- `deleted_at`: user removed/voided/cancelled row that should be hidden but
  retained
- `is_active`: current selectable/configurable row
- `archived_at`: retired configuration/entity with actor/reason
- `status`: workflow state with finite transitions
- `closed_at`/`retention_until`: venue lifecycle, not ordinary admin hiding
- `deactivated_at`: user account lifecycle, and login should respect it if kept

Add simple CHECK constraints where lifecycle metadata implies a state, but avoid
over-constraining states that product flows have not designed yet.

**Acceptance checks:**

- User deactivation fields are either wired into login/access or deferred out of
  V1 schema.
- Venue closure fields are either wired into support/admin flows or documented
  as future-only.
- Queries consistently filter active/deleted/archived rows through helpers.

### 15. FWC/MAPD Raw Data Needs Better Lineage If Kept Append-Only

**Priority:** medium

**Finding:** FWC/MAPD raw tables are intentionally append-only so projections
can keep historical raw source rows. Rows are tied by `synced_at`, but not by a
foreign key to `fwc_mapd_sync_runs`.

**Recommendation:** Add `sync_run_id` to raw MAPD tables if append-only raw
lineage matters. Keep `synced_at` for time filtering, but use the FK for audit,
debugging, and future cleanup.

**Acceptance checks:**

- Every raw FWC/MAPD row can be traced to one sync run.
- Projection refreshes can report exactly which sync run produced the projected
  rows.

### 16. Export Jobs Need A Stronger Snapshot Relationship

**Priority:** medium

**Finding:** `export_jobs.pay_config_snapshot_version` stores text such as
`v1` or `mixed`. This is useful for display, but it loses direct linkage for
single-snapshot exports.

**Recommendation:** Consider adding one of:

- nullable `pay_config_snapshot_id` for single-snapshot exports plus current
  text label for display
- `pay_config_snapshot_ids JSONB` for mixed exports
- a child table `export_job_pay_config_snapshots`

Keep `pay_config_snapshot_version` as a denormalized display field if it is
useful in CSV/report metadata.

**Acceptance checks:**

- A single-snapshot export can join directly to the exact snapshot row.
- Mixed exports preserve all snapshot ids, not only the word `mixed`.

### 17. Public Holiday Regional Semantics Need A Hard Constraint

**Priority:** medium

**Finding:** `public_holidays.region` is nullable while `is_regional` is a
separate boolean. The unique constraint does not protect statewide null-region
duplicates.

**Recommendation:** Normalize the model:

- either make `region TEXT NOT NULL DEFAULT ''`
- or add a CHECK such as regional rows require non-empty `region`, statewide
  rows require `region IS NULL`
- and add an expression unique index using `COALESCE(region, '')`

**Acceptance checks:**

- Statewide holidays are unique by jurisdiction/date/name.
- Regional holiday rows are only regional when a region key is present.

### 18. Query Indexes Should Be Added After Shape Fixes

**Priority:** medium-low

**Recommendation:** Reassess with `EXPLAIN (ANALYZE, BUFFERS)` after the schema
decisions above, ideally against the profile seed rather than only the tiny dev
fixture. Do not add speculative indexes before the tenant/snapshot/lifecycle
shape settles; every extra index adds write cost to roster edits, timesheet
approval, job processing, sync imports, and audit insertion.

Likely useful indexes:

- `timesheet_entries (venue_id, is_approved, worked_on, start_time)
  WHERE deleted_at IS NULL`
- `staff (venue_id, is_active, archived_at, last_name, first_name)`
- `shift_types (venue_id, is_active, archived_at, sort_order, created_at)`
- `email_verification_tokens (user_id, consumed_at, expires_at)`
- case-insensitive pending invitation indexes

Also check existing indexes for redundancy before adding new ones. For example,
compare any proposed timesheet week/export index against
`idx_timesheet_entries_venue_worked_on` and
`idx_timesheet_entries_venue_staff` using real endpoint queries and row counts.

Where planner estimates are wrong for multi-column predicates, consider
extended statistics before adding another btree index. Likely candidates are
`timesheet_entries (venue_id, is_approved, worked_on, deleted_at)`,
`leave_requests (venue_id, status, staff_id, start_date, end_date)`, and Xero
mapping status tables if they grow large enough to show plan instability.

**Acceptance checks:**

- Timesheet week view and approved export queries use targeted indexes.
- Admin config list queries use active/sort indexes.
- New indexes are justified by common queries or measured plans.
- Query plans have acceptable estimated-vs-actual row counts; if estimates are
  off by more than roughly 2x on important endpoints, run `ANALYZE` and decide
  whether extended statistics or per-table autovacuum/analyze thresholds are
  needed.

### 19. High-Write Tables Need Statistics And Maintenance Expectations

**Priority:** medium-low

**Finding:** The V1 schema now has several append-heavy or churn-heavy tables:
`app_jobs`, `audit_events`, `timesheet_entry_versions`, `export_jobs`, Xero sync
tables, and FWC/MAPD raw cache tables. The schema has indexes for common access
paths, but the plan does not yet say how to keep planner statistics current as
these tables grow.

**Recommendation:** Add a lightweight operational checklist for production:

- enable and use `pg_stat_statements` where hosting allows it
- review top total-time and high-variance queries after real usage begins
- monitor `pg_stat_user_tables.n_mod_since_analyze`, `n_dead_tup`,
  `last_autoanalyze`, and `last_autovacuum` for append/churn tables
- tune per-table autovacuum/analyze thresholds only after seeing stale
  statistics or dead-tuple pressure
- keep FWC/MAPD raw cache maintenance explicit if those tables remain
  append-only or are periodically rebuilt

**Acceptance checks:**

- Production runbook identifies the first SQL diagnostics to run for slow
  roster, timesheet, export, job, and Xero pages.
- Large profile seed runs execute `ANALYZE` after bulk load before plan review.
- No global planner settings such as `enable_seqscan = off` or inflated
  `work_mem` are used as production fixes.

## Suggested Execution Slices

### 60.1 Snapshot Reproducibility Foundation
- **Status:** [ ]
- Update `calculate_timesheet_pay` and range calculation to use snapshot data
  for approved entries.
- Add snapshot immutability protection.
- Expand payroll parity tests for post-approval mutations.

### 60.2 Tenant Integrity Constraints
- **Status:** [ ]
- Add parser-safe trigger checks for cross-venue relationships; use composite
  FKs only after an explicit IHP compatibility spike.
- Backfill/fix any existing inconsistent rows before adding constraints.
- Add direct SQL tests proving cross-venue writes are rejected.

### 60.3 Roster And Availability Schema Decisions
- **Status:** [ ]
- Decide whether `staff_availability` is V1 scope.
- Add active roster slot uniqueness.
- Add roster group default enforcement or remove the column.
- Add shift type active-name uniqueness.

### 60.4 Core CHECK Constraints
- **Status:** [ ]
- Add weekday/day/date/range constraints.
- Add timesheet break and approval-state shape constraints.
- Add staff ideal-shift range constraints.

### 60.5 Nullable Uniqueness And Public Holiday Cleanup
- **Status:** [ ]
- Fix public holiday uniqueness.
- Fix open-ended award/rate uniqueness.
- Add concurrency/repeated-sync tests.

### 60.6 Legacy Field And Spec Cleanup
- **Status:** [ ]
- Remove or deprecate `users.user_role`.
- Resolve `day_names.name` and stale `pay_level_day_rules` references.
- Align `specs/02-domain-model.md`, `specs/05-timesheets-and-leave.md`, and
  `specs/06-pay-engine.md` with the final schema.

### 60.7 Finite-State Text Constraints
- **Status:** [ ]
- Add CHECK constraints or enums for export and Xero status/type fields.
- Keep helper lists, tests, and SQL constraints in sync.

### 60.8 Query Index And Statistics Pass
- **Status:** [ ]
- Run targeted `EXPLAIN (ANALYZE, BUFFERS)` checks for timesheet, export,
  roster, admin, invitation, token lookup, job, and Xero mapping paths.
- Add only indexes that support common V1 queries or known background jobs.
- Add extended statistics or per-table autovacuum/analyze tuning only when
  measured row-estimate drift or churn justifies it.

## Verification Plan

Run in this order for each schema slice:

```bash
bash ./bin/in-env regen-types
bash ./bin/in-env typecheck
make db
bash ./bin/in-env dev-stop
bash ./bin/in-env dev-start
bash ./bin/in-env dev-wait
bash ./bin/in-env hspec-test --match "Schema" --match "VenueAccess" --match "PayrollExportParity"
```

For UI-affecting slices, also run:

```bash
bash ./bin/in-env e2e
```

Before committing:

```bash
bash ./bin/in-env lint
bash ./bin/in-env format
```

## V1 Acceptance Criteria

- Approved payroll outputs are explainable and stable after later config edits.
- Direct SQL cannot violate venue ownership boundaries for operational rows.
- The schema enforces active-row uniqueness for roster cells and named config.
- Nullable unique constraints no longer permit duplicate active/current facts.
- Finite-state text columns reject unknown values.
- Legacy or confusing columns are removed, renamed, or explicitly documented as
  future placeholders.
- Specs, helper names, and tests describe the same schema model.
