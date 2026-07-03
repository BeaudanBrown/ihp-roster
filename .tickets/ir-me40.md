---
id: ir-me40
status: open
deps: [ir-h5nr]
links: []
created: 2026-07-03T06:55:44Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-aa95
tags: [agent-loop, docs, guardrails]
---
# Document and guard generated resource auth architecture

Document final generated live resource/subscription authorization architecture and add guardrails.

## Design

Update FrontendSurface and LiveUpdate docs plus relevant AGENTS guidance. Add guardrails against missing scope auth, Live fragments without dependency/resync declarations, hard-coded live registry/planner case lists, handwritten TS mount config parsers, and temporary bridge/custom dependency code after cleanup.

## Acceptance Criteria

Docs describe the authoring flow: declare Resource, assign it to fragments with explicit FromScope/FromFragment sources, emit typed resources from mutations, and run generated checks. Final scan proves no temporary bridge/custom dependency remains. Epic closeout note records final architecture and verification.

