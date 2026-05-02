# Pipeline 55 - Record Retention And Soft Deletion

Read after `IMPLEMENTATION_PLAN.md`, `docs/archive/plans/30-timesheets-and-leave.md`, `docs/archive/plans/40-pay-config-and-admin.md`, and `docs/archive/plans/45-payroll-report-exports.md`.

## Goal

Make destructive deletion unavailable for employment, rostering, payroll-adjacent, Xero-sync, and audit records before the app stores paid venue data.

The product behaviour should be:

- ordinary users can remove, cancel, archive, deactivate, or void records
- those actions keep the original row and append attributable history
- default app queries hide records that are no longer active
- hard deletes are blocked at the database layer for protected tables
- retained records remain explainable and exportable for the required retention window

## Scope

- schema lifecycle columns for protected records
- foreign-key changes away from broad `ON DELETE CASCADE`
- database triggers that block accidental hard deletes
- controller/service changes that replace `deleteRecord` with lifecycle updates
- query helper changes so live screens default to active records only
- tests proving important rows cannot be physically deleted
- migration/backfill steps for existing rows and historical event tables

## Non-Goals

- Do not build Xero sync in this pipeline.
- Do not build the full venue export pack here, but leave the data model ready for it.
- Do not make Fair Work or privacy retention decisions configurable by each venue yet.
- Do not keep expired authentication artifacts such as email verification tokens forever.

## Current Risks

The current schema still contains destructive paths that are acceptable in development but not good enough for a paid payroll-adjacent SaaS:

- Many venue-owned records have `ON DELETE CASCADE` from `venues`.
- `timesheet_entries` can still be physically deleted after a version row is written.
- pending `leave_requests` can be physically deleted after an event row is written.
- `timesheet_entry_versions.timesheet_entry_id`, `leave_request_events.leave_request_id`, and `venue_membership_role_events.venue_membership_id` are not protected by hard foreign keys to preserved parent rows.
- roster row cleanup physically deletes `roster_slots`.
- audit, export, snapshot, role-event, and leave-event records cascade from `venues`.
- tests and some helper code still rely on direct `deleteRecord` or `deleteRecords` for business tables.

## Record Classes

### Protected records

Protected records must not be hard deleted by normal app code:

- `venues`
- `users`
- `venue_memberships`
- `staff`
- `staff_roster_groups`
- `roster_groups`
- `slot_names`
- `day_names`
- `shift_types`
- `report_definitions`
- `report_definition_shift_type_filters`
- `venue_config`
- `pay_config_snapshots`
- `roster_weeks`
- `roster_days`
- `roster_slots`
- `staff_shift_preferences`
- `leave_requests`
- `leave_request_events`
- `timesheet_entries`
- `timesheet_entry_versions`
- `venue_membership_role_events`
- `audit_events`
- `export_jobs` metadata
- future `xero_connections`, `xero_employee_mappings`, `xero_pay_item_mappings`, `xero_sync_batches`, and `xero_sync_lines`

### Ephemeral records

Ephemeral records may still be hard deleted or expired because retention increases privacy and security risk without improving employment-record provenance:

- `email_verification_tokens` after expiry or consumption
- `passkeys` when a user removes a credential
- short-lived download tokens if separated from `export_jobs`
- transient `app_jobs` where the durable business effect is already recorded elsewhere
- rebuildable Fair Work MAPD cache rows, provided any pay/config snapshots keep the exact source context needed to explain historical decisions

## Schema Pattern

Protected records should use one of two lifecycle shapes.

### Soft-deleted records

Use this for records the user experiences as removed, cancelled, or voided:

```sql
deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
deleted_by_user_id UUID DEFAULT NULL,
delete_reason TEXT DEFAULT NULL,
FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
```

Default app queries must filter `deleted_at IS NULL`.

Indexes and uniqueness rules that represent live product constraints should become partial indexes, for example:

```sql
CREATE UNIQUE INDEX idx_slot_names_active_name
    ON slot_names (roster_group_id, name)
    WHERE is_active = TRUE AND deleted_at IS NULL;
```

### Deactivated records

Use this for configuration and account records where inactive state already exists or reads more naturally:

```sql
is_active BOOLEAN DEFAULT TRUE NOT NULL,
archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
archived_by_user_id UUID DEFAULT NULL,
archive_reason TEXT DEFAULT NULL,
FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
```

Existing `is_active` columns can remain the live-state flag, but they should gain `archived_at` metadata where the action has business meaning.

## Hard Delete Prevention

Add a shared trigger function and attach it to protected tables:

```sql
CREATE FUNCTION prevent_hard_delete()
RETURNS trigger AS $$
BEGIN
    IF current_setting('ihp_roster.allow_hard_delete', true) = 'on' THEN
        RETURN OLD;
    END IF;

    RAISE EXCEPTION 'hard delete blocked for protected table %', TG_TABLE_NAME;
END;
$$ LANGUAGE plpgsql;
```

Each protected table gets:

```sql
CREATE TRIGGER prevent_hard_delete_<table_name>
BEFORE DELETE ON <table_name>
FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
```

Use the custom setting only for controlled maintenance migrations, never from ordinary controller code:

```sql
SET LOCAL ihp_roster.allow_hard_delete = 'on';
```

Acceptance rule: the production app database role must not be a superuser, and app code must not set this flag.

## Foreign-Key Direction

Replace broad cascade behaviour with explicit retention semantics:

- `venues` to protected child tables: `ON DELETE RESTRICT`
- `users` referenced as an actor or approver: `ON DELETE RESTRICT` or `SET NULL` only where legal identity is preserved in payload snapshots
- `staff` referenced by employment records: `ON DELETE RESTRICT`
- `timesheet_entries.staff_id`: `ON DELETE RESTRICT`
- `timesheet_entry_versions.timesheet_entry_id`: add a real FK to `timesheet_entries(id) ON DELETE RESTRICT`
- `leave_request_events.leave_request_id`: add a real FK to `leave_requests(id) ON DELETE RESTRICT`
- `venue_membership_role_events.venue_membership_id`: add a real FK to `venue_memberships(id) ON DELETE RESTRICT`
- `audit_events`: keep generic `target_table` and `target_id`, but block hard deletes of `audit_events` themselves
- `export_jobs.file_contents`: may expire or be nulled separately from export metadata if file contents are regenerated or retained elsewhere

Do not rely on `ON DELETE CASCADE` to clean business data. Cleanup should be an explicit archival/voiding operation with an event or audit row.

## Table-Specific Changes

### Venues

- Keep `venues.status` as the primary state.
- Add `closed_at`, `closed_by_user_id`, and `retention_until`.
- Do not support hard venue deletion through the app.
- Deactivating a venue should stop ordinary access, not remove its records.

### Users and memberships

- Add account lifecycle fields to `users`: `deactivated_at`, `deactivated_by_user_id`, `deactivation_reason`.
- Keep `venue_memberships.is_active`.
- Add `archived_at`, `archived_by_user_id`, and `archive_reason` to `venue_memberships`.
- Role changes and membership archival continue to append `venue_membership_role_events` or a new membership lifecycle event.

### Staff

- Keep `staff.is_active`.
- Add `archived_at`, `archived_by_user_id`, and `archive_reason`.
- Never hard delete staff rows once they have roster, leave, timesheet, export, Xero, or audit references.

### Timesheets

- Add `deleted_at`, `deleted_by_user_id`, and `delete_reason` to `timesheet_entries`.
- Rename user-facing "delete" semantics to "void" or "remove draft entry".
- Approved entries must be unapproved/corrected/voided with a version row; they must not disappear.
- Pending/unapproved entries may be hidden after soft deletion, but the row remains.
- Add a hard FK from `timesheet_entry_versions.timesheet_entry_id` to `timesheet_entries(id) ON DELETE RESTRICT`.
- Consider adding `entry_version_action_enum` values `voided` and `restored`; keep historical `deleted` values readable.

### Leave

- Add `deleted_at`, `deleted_by_user_id`, and `delete_reason` to `leave_requests`.
- Pending leave cancellation becomes a soft delete plus `leave_request_events` row.
- Reviewed leave remains non-deletable and can only transition by an explicit review event.
- Add a hard FK from `leave_request_events.leave_request_id` to `leave_requests(id) ON DELETE RESTRICT`.

### Rosters

- Add `deleted_at`, `deleted_by_user_id`, and `delete_reason` to `roster_slots`.
- Convert row-removal and inactive slot-name cleanup from physical `DELETE FROM roster_slots` to soft deletion.
- Default roster rendering filters `roster_slots.deleted_at IS NULL`.
- Keep `roster_weeks` and `roster_days` preserved. If a week is withdrawn, add lifecycle fields rather than deleting.

### Configuration

- Keep `is_active` for `shift_types`, `slot_names`, `day_names`, `roster_groups`, and `report_definitions`.
- Add archival metadata where admin actions have business meaning.
- Preserve `pay_config_snapshots` forever for the retention window. Snapshots are immutable and hard-delete protected.
- If config rows are superseded, references from historical entries must remain valid or the snapshot must contain the full historical context.

### Audit, events, and exports

- Protect `audit_events`, `timesheet_entry_versions`, `leave_request_events`, `venue_membership_role_events`, and `export_jobs` from hard deletion.
- Add retention metadata where useful: `retention_until`, `purged_file_contents_at`, `purged_by_user_id`.
- If file contents are removed after expiry, keep export metadata, scope, requester, timestamps, and snapshot version.

### Xero-ready records

When Xero tables are added, make them protected from day one:

- `xero_connections`: soft disconnect, never hard delete token metadata until retention allows de-identification
- `xero_employee_mappings`: archive instead of delete
- `xero_pay_item_mappings`: version or archive instead of mutate in place
- `xero_sync_batches`: immutable submitted batch header
- `xero_sync_lines`: immutable submitted line payload and Xero response identifiers

## Implementation Slices

### 55.1 Deletion inventory and schema contract
- **Status:** [ ]
- **Deliverables:**
  - Confirm the protected and ephemeral table lists.
  - Add a short schema convention note to `AGENTS.md` or an appropriate spec.
  - Decide whether user-facing language is "void", "cancel", "archive", or "remove" for each surface.

### 55.2 Core schema migration
- **Status:** [ ]
- **Deliverables:**
  - Add lifecycle columns to protected tables.
  - Backfill existing rows as active/non-deleted.
  - Add missing event-table FKs.
  - Replace high-risk `ON DELETE CASCADE` constraints with `RESTRICT` or narrow `SET NULL`.
  - Add partial indexes for live-record lookups.
  - Add hard-delete prevention triggers.

### 55.3 Timesheet and leave controller migration
- **Status:** [ ]
- **Deliverables:**
  - Replace `deleteRecord timesheetEntry` with a soft-delete update plus version row.
  - Replace `deleteRecord leaveRequest` with a soft-delete update plus event/audit row.
  - Update UI copy so payroll-adjacent actions no longer say "cannot be undone" when the record is actually retained.
  - Ensure normal list and export queries exclude soft-deleted entries unless explicitly requested.

### 55.4 Roster and admin configuration migration
- **Status:** [ ]
- **Deliverables:**
  - Replace roster slot physical deletion with soft deletion.
  - Replace slot/config cleanup paths with archive or soft-delete operations.
  - Update roster projection/cache invalidation to treat lifecycle updates as mutations.
  - Ensure admin screens use active/archived filters consistently.

### 55.5 Guardrail tests
- **Status:** [ ]
- **Deliverables:**
  - Schema tests assert protected tables have lifecycle columns and hard-delete triggers.
  - Controller tests prove deletion actions retain rows and append history.
  - A DB-level test proves direct `DELETE` on protected tables fails.
  - Query tests prove default list/export/report paths exclude soft-deleted records.
  - A grep-style regression check flags new `deleteRecord` or raw `DELETE` usage against protected tables.

### 55.6 Retention operations and export readiness
- **Status:** [ ]
- **Deliverables:**
  - Add retention cutoff fields where needed.
  - Document the manual maintenance path for legally allowed purge/de-identification after retention.
  - Define which human-readable venue export surfaces must include soft-deleted, voided, archived, and event records.

## Migration Notes

- Add columns as nullable first where existing data needs a staged backfill.
- Prefer timestamp-null lifecycle filters over new enum types unless the state machine needs more than active versus removed.
- If adding enum values, remember Postgres enum migrations need special handling and schema-parser verification.
- After schema edits, run `bash ./bin/in-env regen-types`, `bash ./bin/in-env typecheck`, `make db`, and restart the dev server to catch IHP schema parser issues.
- The hard-delete trigger function may need verification against IHP's schema parser. If it cannot live cleanly in `Application/Schema.sql`, keep the canonical table/column shape there and manage trigger creation in migrations with a schema test that proves the trigger exists.

## Acceptance Focus

- No protected business table can be hard deleted by ordinary app/database usage.
- Timesheet, leave, roster, pay snapshot, export metadata, event, and audit records survive user-facing delete/cancel/archive actions.
- Historical pay and roster context remains explainable after staff/config/archive changes.
- Default UI, export, and report queries do not accidentally include soft-deleted records.
- Support/admin views can still find retained records when investigating a payroll or venue support issue.
- The migration path does not destroy existing development or pilot data.
