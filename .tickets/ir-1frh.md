---
id: ir-1frh
status: closed
deps: [ir-2l89]
links: []
created: 2026-05-22T06:01:53Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-it5h
tags: [agent-loop, area:live-fragments, area:roster, area:tests]
---
# Verify live-fragment containment and roster refresh behavior

Run the final focused verification pass for containment normalization, roster fragment boundaries, and browser live-fragment behavior.

## Design

Run typecheck, focused LiveSurface/LiveUpdate/RosterWeeks Hspec, and targeted Playwright live-fragment specs. Add a closeout note with any remaining risk or pre-existing failures.

## Acceptance Criteria

Verification includes bash ./bin/in-env typecheck; bash ./bin/in-env hspec-test --match 'LiveSurface' --match 'LiveUpdate' --match 'RosterWeeks'; bash ./bin/in-env e2e e2e/roster-live-fragments.spec.ts; and bash ./bin/in-env e2e e2e/live-update-declarative-adapter.spec.ts, or documents any pre-existing blocker with ticket notes.


## Notes

**2026-05-22T06:35:43Z**

Verification passed: bash ./bin/in-env typecheck; bash ./bin/in-env hspec-test --match 'LiveSurface' --match 'LiveUpdate' --match 'RosterWeeks' (96 examples); bash ./bin/in-env e2e e2e/roster-live-fragments.spec.ts (5 passed); bash ./bin/in-env e2e e2e/live-update-declarative-adapter.spec.ts (10 passed). Discovery: e2e and focused Hspec needed the local dev services running; dev-start restored the postgres socket after one attempted focused Hspec run failed before executing tests.
