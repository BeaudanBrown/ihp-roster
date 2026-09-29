# Public holiday source authority

## Authenticated v2 shadow evaluation

`Client.hs` implements authenticated Developer.Vic Important Dates v2 reads.
`DATAVIC_KEY` is read from the environment and sent only in the `apikey` header
at the fixed HTTPS gateway; `DATAVIC_SECRET` is not used. HTTP errors are reduced
to safe typed outcomes; redirects are disabled so credentials cannot follow a
provider redirect. Transport has a 30-second response timeout and a 1 MiB body
limit. No per-client retries: future worker integration must retain job-owned
retry policy rather than nesting retry loops.

The client requests each distinct year separately with inclusive `from_date` /
`to_date` bounds, PUBLIC_HOLIDAY type, page 1 and limit 100. It accepts at most
four requested years. Annual count/metadata disagreement fails closed; it never
follows provider pagination links. Live unfiltered pages returned the complete
collection repeatedly. Empty provider UUIDs remain absent IDs; provenance uses
the credential-free annual request URI, not a fabricated record source.

Validation rejects malformed/non-ISO/out-of-year/wrong-type rows, duplicate
identities and IDs, and empty/partial responses. Government holiday dates are
authoritative: the client neither checks holiday-specific weekday rules nor
corrects provider dates. Structural checks do **not** certify complete official
year coverage. The client is used only for shadow evaluation pending approved import cutover.
2026 is additionally compared to the reviewed snapshot by the probe and tests,
not by client validation.

Run the read-only probe (loads `.env` through the normal wrapper):

```bash
bash ./bin/in-env bash ./bin/datavic-probe 2026
bash ./bin/in-env bash ./bin/datavic-probe 2027
bash ./bin/in-env hspec-test --match 'DataVic v2 read-only candidate client'
```

The probe never starts an IHP database context, imports dates, or renews freshness.
The captured 2027 response is accepted unchanged, including its Sunday-valued
Easter Monday; this discrepancy is evidence, not a client rejection rule.
Evidence fixtures and their source notes live in
`Test/Fixtures/wage-sources/datavic-v2/`. The probe remains development-only;
`Shadow.hs` and the client are packaged for the production worker. The anonymous
network fetch is retired; `Sync.hs` retains its decoder and protected importer
for migration evidence and regression tests. Database guards and the reviewed
override retain their existing behavior.

### Worker and Support boundary

`Shadow.hs` owns the distinct `public_holiday_shadow` job and deduplication key.
It reads previous/current/next year, compares date/name multisets against cached
statewide VIC rows, and persists only timestamps, requested years, per-year
counts and sanitized failure classifications. Differences are informational;
no provider payloads or credentials enter persisted results. Any fetch failure
returns no partial calendar. IHP owns retries, and each attempt replaces this
job's result. Job history retains earlier jobs.

The Support holiday section displays shadow attempts separately from the active
coverage table. Its existing typed `CreatePublicHolidayRefreshJobAction` route
now enqueues **only shadow jobs**, retaining support authorization and the same
actor/passive refresh contract. There is no anonymous import button. Pending
legacy `public_holiday_refresh` jobs are rejected at worker dispatch, without
running the importer or emitting source-health success/failure events. They may
consume IHP's normal retry attempts, but cannot write holidays.

A shadow attempt never writes `public_holidays` or `public_holiday_overrides`,
renews import timestamps, or emits a freshness-success job. The new
`PublicHolidayShadowSweep` separately preserves the old timer's override review
and periodic source-health reconciliation. This monitoring may open overdue or
stale-source incidents; it does not extend the review deadline or certify a sync.
No schema migration is needed: evidence lives in existing `app_jobs.result`.

### Staging-first operator rollout

Implementation scope is tracked in GitHub issue #620. Pushing, release-pin
updates, deployment, import cutover and override extension are separate approvals.

1. Check deployed override state and review deadline using Support and the
   [override runbook](../Migration/public-holiday-override-runbook.md). The original
   deadline was 2026-10-15 00:00 UTC; do not assume it is still current. Stop for
   separate review/extension approval if overdue or within the seven-day review
   window. Never extend it based on shadow success.
2. Provision `DATAVIC_KEY` through the private environment secrets: `rozzy-staging/env`
   first, then `rozzy/env`. Both are already loaded by their workers in
   `bepis-dotfiles`. Secret provisioning belongs to the operator; no secret values
   belong in these repositories. The enqueue service does not need API access.
3. Ship the complete staging integration branch. Advance only the
   `ihp-roster-staging` lock input first; do not advance the production input yet.
   The dotfiles candidate adds bespoke staging shadow units and restore lifecycle
   handling. Disable the old staging refresh units and approve the staging switch.
4. Run **Run shadow fetch** from Support as founder support. Check job outcome,
   all three requested years/counts and informational differences. Confirm cached
   dates/import timestamps and override state have not changed. Observe a timer
   run as well before proceeding to production.
5. After approval, advance the production `ihp-roster` input to the same verified
   release and enable `services.ihpRoster.publicHolidays.shadow` with `onCalendar =
   "daily"` and `randomizedDelaySec = "30m"`. Set `publicHolidays.refresh.enable =
   false`. Dotfiles enables production shadow options only when the production
   input exposes them, so advancing staging alone does not activate production
   shadow fetching. The staging input must contain `PublicHolidayShadowSweep`
   before applying its new units; the old staging package lacks that binary.
6. Verify production manual and scheduled shadow runs, worker secret availability,
   and unchanged calendar authority. Daily is evaluation cadence; weekly is the
   recommendation for the separately approved active import cutover.

Rollback of evaluation: disable the shadow timers (and stop any in-flight shadow
job if needed). This does not undo or replace calendar data. Do **not** re-enable
anonymous import or roll the entire application back without separate release
review. If shadow scheduling remains disabled, preserve independent review/expiry
monitoring; the original `PublicHolidayRefreshSweep` also runs that monitoring
but must not be used as an importer during shadow evaluation.

## Active source and override

`Sync.hs` retains the legacy DataVic decoder and protected import boundary. `Override.hs` owns the temporary reviewed VIC
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
