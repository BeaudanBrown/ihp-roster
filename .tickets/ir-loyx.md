---
id: ir-loyx
status: open
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

