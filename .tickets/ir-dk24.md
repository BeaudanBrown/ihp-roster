---
id: ir-dk24
status: closed
deps: [ir-1jsi]
links: [ir-bdvn, ir-l089, ir-6thh]
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


## Notes

**2026-05-21T08:31:37Z**

HANDOFF: Re-ran the baseline scenarios on the SQL/direct roster path. Local Hspec Server-Timing sample: cold page 35.5ms vs projection baseline 25.2ms (+10.3); warm page 34.1 vs 17.8 (+16.3); content fragment 19.6 vs 16.0 (+3.6); row fragment 8.5 vs 2.8 (+5.7); day fragment 12.7 vs 3.3 (+9.4); staff panel 16.5 vs 4.4 (+12.1); slot mutation 11.8 vs 10.8 (+1.0); passive row refetch 14.5 vs 7.9 (+6.6). No projection spans were present; direct path repeatedly pays staff option-state and slot conflict builders. Recommendation for supervisor: keep a temporary hybrid/rollback seam rather than deleting projection immediately, and tune direct fragment costs in ir-bdvn before adoption cleanup. Tests run: IHP_ROSTER_BASELINE_PRINT=1 bash ./bin/in-env hspec-test --match 'Roster direct read-model integration'; bash ./bin/in-env typecheck. Remaining risk: local Hspec timing only, not browser/production-scale load.
