---
id: ir-qq35
status: open
deps: [ir-52yn]
links: []
created: 2026-07-07T03:24:11Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-elys
tags: [frontend-contracts, frontend, tests, htmx]
---
# Consume generated surface action metadata in frontend runtime tests

Prove generated action metadata is active, not decorative.

## Design

Add or extend frontend tests so emitted data-bepis surface action metadata is parsed/validated through generated contracts and checked against FrontendSurfaceRegistry. Add focused Hspec/view tests for Admin Roster Groups rendered attrs and guardrails against reintroducing handwritten action metadata in the migrated surface.

## Acceptance Criteria

Frontend tests exercise generated action validators/manifests. Hspec/view tests prove Admin Roster Groups emits correct attrs. Guardrails catch stale/manual hx metadata in the migrated surface where the helper should be used.

