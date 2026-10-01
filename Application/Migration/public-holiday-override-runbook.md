# Temporary verified VIC 2026 holiday calendar

## Scope and evidence

This is an operator-approved data correction, not a successful DataVic refresh.
Revisions `1789440000` (additive authority/guard) and `1789440001` (guarded
correction/activation) implement the reviewed `business-victoria-vic-2026-20260915-v1`
snapshot in `Application/PublicHolidays/Override.hs`.

Verified on 15 September 2026 against:

- https://business.vic.gov.au/business-information/public-holidays/victorian-public-holidays-2026
- https://business.vic.gov.au/business-information/public-holidays/victorian-public-holidays-2027

The first page lists all 14 dates retained in the code snapshot, including
25 September (Friday before the AFL Grand Final). The second confirms Easter
Monday 2027 is 29 March. This is not verification of complete 2027 or 2025 coverage.

The DataVic resource `caaa47de-8626-46a6-aa28-3d948c15c5d9` currently declares
`important_date` as timestamp and reverses ambiguous day/month values compared
with its August 2026 CSV. Both sources also contain the wrong Easter Monday 2027
and records with 2028 source URLs but 2027 dates. Neither permissive ISO parsing
nor automatic CSV fallback is authorized by this change.

## Approval and preflight

**Do not deploy these revisions without separate production approval.** Confirm
installed release, database identity and expected revisions first. Rehearse on
an isolated production clone using `docs/runbooks/migration-rehearsal.md`.
The data revision deliberately aborts if the complete 2026 calendar differs
from the reviewed set after the single missing-date insertion; it is not an
empty-database seeder. Fresh installations use Schema.sql and need an explicitly
reviewed calendar activation, not an assumption of coverage.

1. Re-check both official calendars for amendments. The review deadline is
   **2026-10-15 00:00 UTC**. If deployment is later, re-review and issue a new
   auditable revision rather than moving timestamps casually.
2. Take a full database backup using the established production backup procedure;
   verify restoration into an isolated database. Never reset the production DB.
3. Record the deployed release, selected database, backup reference, approver and
   the following preflight output in the deployment evidence. Substitute your
   connection via normal PostgreSQL environment settings; never paste secrets.

```sql
BEGIN READ ONLY;
SELECT current_database(), now();
SELECT id, jurisdiction, holiday_date, name, region, is_regional,
       source, source_id, source_url, imported_at
FROM public_holidays
WHERE jurisdiction = 'VIC'
  AND holiday_date BETWEEN DATE '2026-01-01' AND DATE '2027-12-31'
ORDER BY holiday_date, name, id;
ROLLBACK;
```

Expected incident shape: 13 statewide 2026 records with correctly ordered dates,
missing Grand Final eve, and one Easter Monday 2027 at 28 March. Already-correct
Grand Final/Easter Monday rows are accepted; ambiguous rows, unknown 2026 names,
extra/missing 2026 holidays and unexpected region values abort without mutation.
Absent 2027 Easter Monday is left absent, never used to certify that year.

## Apply and verify

Stop **both app and worker** and relevant refresh timers before running the
normal IHP deployment migration path. This is required so an old writer cannot
race activation. Do not execute the data revision outside a transaction.
Deploy the matching application version before reopening traffic.

The data revision:

- saves complete before/after rows in `public_holiday_overrides`;
- adds only the missing 2026 Grand Final eve record (no fabricated imported_at);
- corrects the existing wrong Easter Monday 2027 row without changing its ID or
  imported_at; leaves Easter Sunday and all unrelated records intact;
- checks the exact 14-row 2026 date/name multiset, then activates its override;
- changes no sealed payroll, timesheet, export or Xero history.

```sql
BEGIN READ ONLY;
SELECT snapshot_key, jurisdiction, target_year, source_url,
       verified_at, review_due_at, retired_at,
       jsonb_array_length(correction_before) AS before_count,
       jsonb_array_length(correction_after) AS after_count
FROM public_holiday_overrides;
SELECT holiday_date, name, imported_at FROM public_holidays
WHERE jurisdiction = 'VIC' AND NOT is_regional
  AND holiday_date BETWEEN DATE '2026-01-01' AND DATE '2027-12-31'
ORDER BY holiday_date, name;
ROLLBACK;
```

Verify Support shows `Verified override` and the deadline, separately from the
failed DataVic refresh job. The scheduled public-holiday sweep reconciles one
single-fire event exactly seven days before the deadline and one escalation at
expiry. Initial observation after expiry emits only the overdue event. Repeated
sweeps and restarts do not send reminders. Event metadata includes jurisdiction,
year, verification source, deadline, review cycle and reviewed action; no provider
payload is retained. Ordinary venue users must not receive the generic
wage-source warning on roster or timesheet full pages or fragments. Calculation
errors and final payroll gates remain unchanged. Check an affected draft dated
25 September uses holiday rates; historical sealed results do not recalculate.

The override is usable only while unexpired and the complete stored statewide
calendar matches the reviewed snapshot. Expiry does **not** unlock writes.
DataVic refresh attempts including a protected year fail without replacing any
year or renewing any timestamps; the DB trigger also rejects old/direct row
writers. Existing failure/freshness alerts remain super-admin-only and continue
to report provider health. This rollout does not change refresh scheduling.

## Review and return to DataVic

There is intentionally no automatic release on a successful HTTP response or
expiry. Before the deadline, either reverify in a new audited revision, or
perform a separately approved cutover:

Every approved extension increments `review_cycle`, records the reviewing platform
super-admin and bounded action, resolves the prior cycle and creates no warning for
the new cycle until its own seven-day window. Validated retirement records the same
audit fields and resolves the active cycle. These mutations remain runbook-gated;
there is intentionally no generic Support-page extension or retirement button.

1. Capture the repaired provider payload, schema and retrieval time. Confirm
   format, date/year identity, uniqueness, complete year coverage and all known
   error cases. Compare **all 14** 2026 date/name pairs with the reviewed snapshot;
   explicitly review any legitimate differences against Business Victoria.
2. Add regression fixtures for the repaired provider format before accepting it.
   The current strict slash parser remains intentional until that reviewed change.
3. With writers stopped, apply one reviewed transactional cutover revision that
   locks both tables, checks snapshot identity and exact current calendar, marks
   this override retired, and installs the validated candidate calendar/provenance.
   Do not simply clear retired_at/set imported_at or run an unchecked refresh.
4. Restart matching code, verify normal source freshness and holiday calculations,
   and retain this override's before/after audit permanently.

Other years retain ordinary source policy. Correcting one 2027 date does not
renew that year's freshness or assert that the rest of its dataset is trustworthy.

## Rollback and recovery

A preflight failure rolls back the complete data revision; resolve the discrepancy
from official evidence, never weaken the exact-set check. Re-running an applied
data revision is a no-op, including after retirement.

For application rollback, prefer leaving the additive table and protective
trigger installed. Older code cannot overwrite the protected dates, but does not
understand override usability and may block payroll on stale imports; do not
reopen it as an apparently healthy payroll service. Forward-fix is preferred.

If the correction itself must be reversed, stop writers and obtain separate
operator approval. Use the retained before/after UUIDs plus the verified backup
to prepare a new transaction that checks rows still match the recorded after
state before restoring only affected fields. The inserted Grand Final row has no
before counterpart: its removal needs explicit data-deletion approval and must
not be bundled into ordinary rollback. Do not restore the whole database over
new customer activity, delete the audit, drop the table, or bypass guards while
workers run. Restore backups only to an isolated clone for recovery comparison.
