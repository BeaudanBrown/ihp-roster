---
id: ir-pqis
status: closed
deps: []
links: []
created: 2026-06-30T13:02:20Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [architecture, bepis-actions, agent-loop]
---
# Harden Bepis runtime fact coverage

Make Bepis runtime fact collection and helper coverage reliable after the final fact architecture migration.

## Design

Keep the runBepis/BepisFact model. Harden collector cleanup, improve response/scope coverage, clarify audit semantics, add tests, and keep architecture wording accurate.

## Acceptance Criteria

Fact contexts clean up on exceptions; common helpers emit facts consistently; focused tests and architecture gates pass.

