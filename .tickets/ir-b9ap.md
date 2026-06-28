---
id: ir-b9ap
status: open
deps: [ir-fvq6]
links: []
created: 2026-06-28T12:17:09Z
type: task
priority: 1
assignee: beaudan
parent: ir-osr3
tags: [agent-loop, observability, performance, lazy-loading]
---
# Measure lazy loading performance impact

Use the OTel/browser/profile tooling to compare roster staff panel lazy loading against the current eager baseline on normal and profile-sized data.

## Design

Run focused profile/OTel scenarios before and after implementation where possible. Capture initial ShowRosterWeekAction server time, response bytes, lazy staff panel fragment time, browser wall time, and error count. Update or add a small regression threshold/report if practical without making tests flaky.

## Acceptance Criteria

Artifacts or notes record before/after timings; expected initial roster response time/size improvement is demonstrated on the huge/profile dataset; no trace errors are introduced; any remaining bottlenecks are documented as follow-up tickets rather than hidden.


## Notes

**2026-06-28T13:12:28Z**

Attempted measurement with roster_profile_run roster-wide (1 rps, 5s) but the profile run failed before serving roster requests because the current Haskell environment cannot load OpenTelemetry.* modules; latest failed artifact dir: output/profile-load/1782652131-2623154-16262. Leaving ticket open because before/after timings could not be captured.
