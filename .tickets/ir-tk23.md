---
id: ir-tk23
status: closed
deps: []
links: [ir-36t6]
created: 2026-04-30T06:35:01Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-18tm
tags: [area:helpers, area:maintenance, area:architecture, area:security]
---
# Move shared domain and URL helpers out of view namespace

Relocate helpers such as isTrialStaff and appendQueryParams from Application.Helper.View into non-view modules so controllers, email helpers, projections, and export services do not depend on view helper namespaces.

## Design

Introduce narrow homes such as Application.Helper.Staff or Application.Domain.Staff for staff identity/filtering and Application.Helper.Url or Application.Helper.Routes for query-string construction. Re-export from Application.Helper.View only for compatibility while callers migrate. Coordinate with the existing URL-encoding hardening ticket.

## Acceptance Criteria

Non-view modules no longer import Application.Helper.View just for staff predicates or URL construction; query string construction has a clear non-view API; compatibility re-exports are temporary and documented; typecheck passes.

## Notes

**2026-04-30T08:04:40Z**

Introduced Application.Helper.Url.appendQueryParams and Application.Helper.Staff.isTrialStaff, left documented compatibility re-exports through Application.Helper.View, and migrated non-view callers away from the view namespace. Verified with bash ./bin/in-env typecheck and bash ./bin/in-env hspec-test --match "Schema".
