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
# Make authorization helpers emit scope facts

Move scope/permission fact emission into the helpers that actually authorize request state and IDs.

## Design

Update or wrap current helpers such as ensureIsUser, ensureCurrentVenue, ensureVenueWritable, ensureManagerRole, ensureAdminRole, support checks, and record-in-venue checks. A scope fact is emitted only after the check succeeds. Do not keep standalone scopedTo* annotation helpers in final code.

## Acceptance Criteria

Representative controller paths emit scope facts from actual authorization helpers; no standalone scope-label components remain; tests cover success/failure and captured fact emission.
