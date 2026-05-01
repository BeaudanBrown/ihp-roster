---
id: ir-wrle
status: closed
deps: [ir-k86z, ir-0t21]
links: []
created: 2026-04-30T23:32:33Z
type: task
priority: 2
assignee: beaudan
parent: ir-sryt
tags: [area:performance, area:profiling]
---
# Add profiling comparisons budgets and dropped-iteration reporting

Make profiling reports useful for before/after decisions and regression detection instead of only manual inspection.

## Design

Extend profile-load-report and suite reporting to parse dropped_iterations, iterations, VU saturation, threshold failures, and k6 checks from NDJSON/stdout. Add comparison commands for load profiles and load suites that rank p50/p95/p99/app/span/status/dropped-iteration deltas. Support configurable route/span budgets for CI or pre-merge checks.

## Acceptance Criteria

load-profile.json/md include dropped iterations and VU saturation; profile-load-suite comparison output ranks improvements/regressions; budgets can fail a run on configured p95/p99/failure/dropped-iteration thresholds; docs describe a before/after workflow.


## Notes

**2026-04-30T23:59:05Z**

Load reports and suite summaries now include dropped iterations, completed iterations, check failures, observed VUs, and VU saturation. profile-compare now handles load-profile and load-suite JSON pressure deltas.
