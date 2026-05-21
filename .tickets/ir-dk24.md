---
id: ir-dk24
status: open
deps: [ir-1jsi]
links: []
created: 2026-05-21T07:43:26Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-xyzw
tags: [agent-loop, area:roster, area:performance, area:architecture]
---
# Measure roster SQL trial path and report recommendation

Use the trial path and baseline scenarios to decide whether SQL/direct roster reads should replace roster projection caching.

## Design

Repeat the baseline scenarios with the SQL/direct path. Compare cold and warm full-page loads, fragment GETs, mutation actor refreshes, passive refetches where feasible, query/span distribution, rollback cost, implementation complexity, and correctness risk. The /aloop orchestrator should report the final recommendation in chat instead of committing an ADR/workstream note unless the result is adopted later.

## Acceptance Criteria

A final chat report recommends one path: keep SQL/direct and open cleanup to remove roster projection cache, keep projection and remove the trial path, keep a temporary hybrid with rationale, or run a narrower follow-up experiment. The report includes performance deltas, correctness risks, complexity assessment, and next tickets if needed.

