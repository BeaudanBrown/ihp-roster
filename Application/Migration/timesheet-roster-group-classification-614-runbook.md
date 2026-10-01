# Timesheet roster-group classification review

Migration `1790220401` preserves every Timesheet and all approval, pay, export,
and source evidence. Linked entries take their source Roster group. Unlinked
entries with active Staff memberships take the first group by `sort_order`, then
stable group ID; entries with no active membership become `NoRosterGroup`.

Before production rollout, run the migration rehearsal. Before applying the
migration, record this aggregate in the approved deployment record; its four
values must be identical after the migration:

```sql
SELECT count(*) AS entry_count,
       count(*) FILTER (WHERE is_approved) AS approved_count,
       count(*) FILTER (WHERE staff_pay_version_id IS NOT NULL) AS staff_pay_evidence_count,
       md5(string_agg(concat_ws('|', id::text, is_approved::text,
           coalesce(approved_at::text, ''), coalesce(approved_by_user_id::text, ''),
           coalesce(staff_pay_version_id::text, ''), coalesce(shift_type_pay_version_id::text, ''),
           coalesce(active_pay_calculation_id::text, '')), ',' ORDER BY id)) AS approval_pay_fingerprint
FROM timesheet_entries;
```

Immediately after the upgrade, export the following review set to the approved
operator workspace:

```sql
SELECT te.id, te.staff_id, te.roster_group_id,
       array_agg(srg.roster_group_id ORDER BY rg.sort_order, rg.id) AS candidates
FROM timesheet_entries te
JOIN staff_roster_groups srg ON srg.staff_id = te.staff_id AND srg.deleted_at IS NULL
JOIN roster_groups rg ON rg.id = srg.roster_group_id
WHERE te.source_roster_slot_id IS NULL
GROUP BY te.id, te.staff_id, te.roster_group_id
HAVING count(*) > 1;
```

Also review zero-group classifications with:

```sql
SELECT id, staff_id, operational_date
FROM timesheet_entries
WHERE roster_group_classification = 'no_roster_group'
ORDER BY operational_date, id;
```

These outputs contain customer identifiers and must not enter issue comments or
build logs. The venue operator decides corrections from historical records.
There is intentionally no application correction UI. A correction is an audited
operator maintenance event: pause Timesheet writes, take and verify a backup,
record the entry ID, old/new classification and reason in the deployment record,
disable only `enforce_roster_derived_timesheet_identity_immutable`, update the
classification/group in one transaction, and re-enable the trigger.

Before resuming writes, the following query must return one row with every
violation count equal to zero:

```sql
SELECT
    count(*) FILTER (WHERE
        (roster_group_classification = 'in_roster_group') <> (roster_group_id IS NOT NULL)
    ) AS classification_violations,
    count(*) FILTER (WHERE roster_group_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM roster_groups rg
        WHERE rg.id = timesheet_entries.roster_group_id
          AND rg.venue_id = timesheet_entries.venue_id
    )) AS venue_violations,
    count(*) FILTER (WHERE source_roster_slot_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM roster_slots rs
        JOIN roster_days rd ON rd.id = rs.roster_day_id
        WHERE rs.id = timesheet_entries.source_roster_slot_id
          AND rd.venue_id = timesheet_entries.venue_id
          AND rd.operational_date = timesheet_entries.operational_date
          AND rd.roster_group_id = timesheet_entries.roster_group_id
          AND timesheet_entries.roster_group_classification = 'in_roster_group'
    )) AS source_provenance_violations,
    count(*) FILTER (WHERE NOT (
        (is_approved = FALSE AND approved_at IS NULL AND approved_by_user_id IS NULL
            AND staff_pay_version_id IS NULL AND shift_type_pay_version_id IS NULL)
        OR
        (is_approved = TRUE AND approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL
            AND staff_pay_version_id IS NOT NULL AND shift_type_pay_version_id IS NOT NULL)
    )) AS approval_evidence_violations
FROM timesheet_entries;
```

Rerun the pre-migration aggregate and require an exact match. Also verify the
immutability trigger is enabled:

```sql
SELECT tgenabled
FROM pg_trigger
WHERE tgrelid = 'timesheet_entries'::regclass
  AND tgname = 'enforce_roster_derived_timesheet_identity_immutable';
```

Acceptance is exactly one row with `tgenabled = 'O'`. Do not alter approval
fields, pay calculations, entry versions, timestamps, source IDs, or export
evidence. Recovery is a forward correction from the recorded old value; do not
drop the new columns or enum.
