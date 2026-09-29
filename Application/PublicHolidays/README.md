# Public holiday source authority

## Read-only v2 candidate client (not activated)

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
year coverage. The client remains a read-only candidate pending approved cutover.
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
`Test/Fixtures/wage-sources/datavic-v2/`. Both client and probe are development-only
until cutover. `Sync.hs`, scheduled jobs, deployment credentials, database guards
and the reviewed override are intentionally unchanged. Worker wiring, production
packaging and activation belong to the separately approved cutover.

## Active source and override

`Sync.hs` owns DataVic ingestion. `Override.hs` owns the temporary reviewed VIC
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
