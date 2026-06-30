---
id: ir-xz3b
status: open
deps: [ir-mwma]
links: []
created: 2026-06-30T11:03:28Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-z0j1
tags: [architecture, bepis-actions, agent-loop]
---
# Make authorization helpers produce scope evidence

Move scope/permission evidence production into the helpers that actually authorize request state and IDs.

## Design

Add Bepis-owned wrappers or return types around current helpers such as ensureCurrentVenue, ensureManagerRole, ensureAdminRole, support checks, and record-in-venue checks. Evidence must be produced only after the authorization check succeeds. Do not allow standalone scopedTo* annotation helpers in final code.

## Acceptance Criteria

Representative controller paths get scope evidence from actual authorization helpers; no standalone scope-label components remain; tests cover success/failure and evidence emission.

