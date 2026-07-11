---
id: ir-loyx
status: closed
deps: [ir-6kbg]
links: []
created: 2026-07-10T05:32:29Z
type: task
priority: 1
assignee: beaudan
parent: ir-zpyz
tags: [agent-loop, verification, closeout]
---
# Run final full verification sweep and closeout

Run the full audited command list, capture remaining artifacts/flakes, update docs only for durable discoveries, and add an epic closeout note.

## Design

Use focused artifacts from prior tickets for context, then run the full gate: regen-types, frontend-contracts-check, frontend-check, frontend-build, typecheck, hspec-test, hspec-coverage, lint, style-audit, doc-drift-check, and e2e.

## Acceptance Criteria

All target commands pass. Epic has a closeout note summarizing final green state and any intentionally deferred linked follow-ups.


## Notes

**2026-07-11T02:33:49Z**

Final verification sweep passed on 2026-07-11: regen-types, frontend-contracts-check, frontend-build, frontend-check, typecheck, hspec-test, hspec-coverage, lint, style-audit, doc-drift-check, and full e2e. hspec-coverage required a longer retry after the first worker timeout; retry completed with 938 examples, 0 failures. Full e2e completed with 176/176 passing.
