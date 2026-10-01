# Developer.Vic v2 public-holiday evidence

Captured 2026-09-28 at 23:46 UTC from the authenticated, read-only endpoint:

`https://wovg-community.gateway.prod.api.vic.gov.au/vicgov/v2.0/dates`

Query: `type=PUBLIC_HOLIDAY&from_date=YEAR-01-01&to_date=YEAR-12-31&limit=100&page=1&sort=date:asc`.

Only public date fields and pagination metadata are retained; credentials,
request headers, response headers, links and volatile response timing are omitted.
The provider dates are not corrected or inferred.

- `2026.json`: all 14 date/name pairs match the reviewed Business Victoria snapshot
  in `Application/PublicHolidays/Override.hs` (including 26 and 28 December).
- `2027.json`: provider evidence with a known calendar discrepancy. Easter Monday
  is `2027-03-28` (Sunday), not Monday 29 March. The client accepts the government
  response and preserves that date unchanged; it does not enforce holiday-specific
  calendar rules. AFL Friday is absent; this fixture is not evidence of complete
  official 2027 coverage.

Published specification: Developer.Vic catalogue, **Victorian Government -
Important Dates API 2.0.0**, API ID `3f3482a0-6562-4bdb-92db-ee4163455956`.
Live authentication is the `apikey` header only; the older prose describing a
key/secret pair does not match the working security scheme. Unfiltered live
requests returned 142 rows on both pages despite a declared limit of 100. Annual
filtered queries avoid that observed repetition; the client rejects annual
pagination/count disagreement rather than trusting provider links.

Source attribution: Victorian Government / Business Victoria; API documentation
specifies CC BY 4.0. Operator-approved cutover remains required; fixtures do not
authorize database changes.
