# Public holiday source authority

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
