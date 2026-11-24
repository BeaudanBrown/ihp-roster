# Public holiday source authority

## Active authenticated import (#656)

Active import is opt-in: `DATAVIC_ACTIVE_IMPORT=true` must be present for both
`PublicHolidayRefreshSweep` and the worker. It uses a distinct
`public_holiday_active_import` job. Retired shadow and anonymous refresh jobs
remain rejected, and historical job rows are retained. Support reports live import
status and coverage without enqueuing a job.

DataVic is the sole date authority. Each nonempty, structurally valid response
represents current complete knowledge, including unannounced future holidays.
A daily job fetches previous/current/next year, then replaces all three in one
transaction. Removals and date/name corrections are accepted without manual
review; malformed/empty/partial responses preserve all prior data. A request
started before a newer accepted import cannot overwrite that import.

`public_holiday_import_batches` retains acceptance independently of calendar
rows, with before/after date provenance for recovery. The additive migration
preserves legacy import timestamps as legacy evidence, never as a new refresh.
Age over 45 days warns but does not block final payroll. Missing accepted year
coverage still blocks; protected overrides retain their checks until cutover.
FWC freshness and sealed payroll/Xero history are unchanged. Failures alert only
after retry exhaustion through the existing founder notification pipeline.

### Operator cutover and recovery

No deployment, timer activation or production cutover is implied by this code.
First rehearse on an isolated production clone, verify a full backup can be
restored, and record the target database, reviewer, release and approval.
Stop active enqueue timers and drain workers before the cutover. Keep
app writers stopped during the protected override transition. Do not reset DBs.

With the target service's database environment and `DATAVIC_KEY` supplied via
its protected environment file, run the packaged binary (not automatically):

```sh
/path/to/app-binaries/bin/PublicHolidayCutover --apply --database rozzy_staging --reviewer PLATFORM_SUPER_ADMIN_UUID
```

The command checks the actual database name and active platform-super-admin,
fetches all three calendars, locks calendar/override/evidence tables, verifies
the known 2026 override and exact old calendar, and retires it alongside the
import. Its original correction audit is retained. Failure rolls back every
write; a second cutover is rejected rather than silently refreshing.

After successful staging verification, configure the daily active sweep with
up to 30 minutes jitter and set `DATAVIC_ACTIVE_IMPORT=true` on the sweep and
worker. The app need not have it.
Verify a `public_holiday_active_import` job, its receipt, expected wage estimates
and absence of missing-coverage blockers, then observe a scheduled run.
Production requires separate approval with its own database name and backup.

Rollback: disable active scheduling and unset the gate; retain accepted cached
dates and the additive evidence table. Do not roll back to code that treats
retired overrides or new acceptance evidence incorrectly. If calendar recovery
is needed, stop writers and prepare a separately approved checked transaction
using the latest receipt's previous/accepted snapshots and verified backup.
Never overwrite newer customer activity or modify sealed payroll. Compare current
rows with the accepted snapshot before restoring; recover backups into an
isolated database first. Keep all receipt and override audits permanently.

## Read-only provider diagnostics

Use the authenticated DataVic v2 probe to inspect the provider independently of
the worker and database. It uses the normal `DATAVIC_KEY` environment and never
imports dates or renews freshness. Structural validation is not a substitute
for comparing the result with the published Victorian calendar. After restores
or provider changes, spot-check 2027 Easter Monday (29 March), which an earlier
provider response misdated.

```bash
bash ./bin/in-env bash ./bin/datavic-probe 2027
```

## Active source and override

`Override.hs` owns the temporary reviewed VIC
2026 snapshot, complete-calendar validation and validity window. The normal
`public_holidays` table remains the sole date lookup for wage calculation;
there is no second calendar inside the wage engine.

An unretired `public_holiday_overrides` row protects its jurisdiction/year even
when expired or unknown to the running code. The importer rejects any whole
request containing a protected year before mutations, and the schema trigger
rejects row-level changes by older/direct writers. Neither an HTTP success nor
expiry retires an override.

`WageSourceFacts` accepts reviewed coverage only when the snapshot key/source,
verification time, deadline and exact stored statewide date/name multiset match.
Other years and FWC policy are unchanged. Imported Xero override pay remains
independent of Award sources. Provider health snapshots remain separate and
are not renewed by reviewed coverage. Support displays override usability and
its review deadline alongside the provider job state. Draft source-maintenance
warnings are platform-super-admin-only; calculation errors and strict payroll
checks remain.

Deployment, re-review, controlled retirement and recovery:
`../Migration/public-holiday-override-runbook.md`. The code snapshot and SQL data
revision intentionally share a version key; persistence tests exercise their
agreement through the actual migration script. The revision-owned rehearsal
fixture verifies the real runner upgrade path. Tests use fixed clocks and no
live HTTP calls.
