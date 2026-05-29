---
id: ir-kuyy
status: open
deps: [ir-oxnj]
links: []
created: 2026-05-29T03:16:10Z
type: epic
priority: 2
assignee: beaudan
parent: ir-cfcr
tags: [agent-loop, roster, live-fragments, high-risk]
---
# Migrate roster week fragments to unified actor OOB responses

Bring the most complex surface, roster weeks, onto the unified fragment/swap model while preserving row/day precision and scroll behavior.

## Design

Roster already has typed content, staff panel, day, and row fragments plus containment. The migration must reconcile immediate OOB row/day patches, actor refresh headers, week/group navigation, direct/projection read-model paths, and horizontal scroll containers.

## Acceptance Criteria

Roster successful actor updates use declared fragment renderers consistently; row/day precision is preserved; live passive invalidations and resyncs still work; mobile/desktop roster E2E and Hspec pass.

