---
id: ir-f42m
status: closed
deps: []
links: []
created: 2026-05-21T07:43:26Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-xyzw
tags: [agent-loop, area:roster, area:performance]
---
# Baseline current roster projection behavior

Establish enough baseline evidence to compare current roster projection caching against a no-projection SQL/direct read path.

## Design

Use existing profileActionSpan coverage and projection cache stats. Capture cold and warm full-page roster loads, content/day/row/staff-panel fragments, slot mutation actor refresh, and passive refetch where feasible. Record roster size dimensions such as staff count, slot count, visible slot count, row/day count, and conflict count. Avoid building a large new observability system unless the existing spans are insufficient.

## Acceptance Criteria

Baseline notes include scenarios, commands, timing/span results, projection hit/miss/load behavior, roster size dimensions, and known limitations. The notes identify which spans dominate cold and warm roster requests.


## Notes

**2026-05-21T07:52:47Z**

HANDOFF: Added focused roster projection baseline coverage and docs/workstreams/roster-sql-read-model-trial.md with scenarios, Server-Timing samples, cache hit/miss/load behavior, fixture dimensions, and limitations; tests run: bash ./bin/in-env hspec-test --match 'Roster projection baseline', bash ./bin/in-env typecheck; remaining risk: timings are local Hspec/mock-controller samples and should be remeasured under larger/production-like data in ir-dk24.
