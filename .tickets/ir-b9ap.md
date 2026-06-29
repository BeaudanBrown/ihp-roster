---
id: ir-b9ap
status: closed
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

**2026-06-29T15:12:55Z**

Starting closeout measurement. First attempt will use the safe local roster_profile_run wrapper at low rate; if the OTel/k6 harness is still blocked by the known OpenTelemetry module load issue, I will capture the failure artifact and use fallback response-byte/server-timing evidence rather than hiding the gap.

**2026-06-29T23:51:44Z**

Measurement complete. Artifacts: lazy run output/profile-load/1782746046-488739-7627; temporary eager-baseline comparison output/profile-load/1782746046-488739-7627-eager-baseline; comparison report output/profile-load/1782746046-488739-7627/lazy-vs-eager.md. Method: ran current lazy code with profile-load --no-otel --scenario=roster-wide --rate=1 --duration=5s --vus=1, then temporarily disabled the staff-panel lazy policy locally without committing and reran against the same seeded profile DB. Results on the large-roster-history dataset: current/full response bytes improved from 155,698 to 121,174 (-34,524 / -22.2%); historical/full from 154,074 to 119,550 (-22.4%); future/full from 241,988 to 207,464 (-14.3%). Staff panel authoritative lazy fetch remains 39,200 bytes and completed in 29ms HTTP / 28.3ms app_total in the lazy run. k6 reported 0 failed HTTP requests, 0 failed checks, 0 dropped iterations, and all roster-wide route checks passed. The --otel wrapper was retried first but could not start its collector because an existing dev observability collector already owned localhost:8888; this is an environment collector-port conflict, not an app trace/error regression. Remaining bottlenecks are roster grid/body render size and future-week visible read-model/render work, which belong to the projection-cache/unified-fragment follow-up epics rather than lazy-loading itself.
