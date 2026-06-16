---
id: ir-patj
status: open
deps: []
links: []
created: 2026-06-16T01:03:30Z
type: task
priority: 1
assignee: beaudan
parent: ir-3qq9
tags: [agent-loop, db, invites]
---
# Add staff adoption target to venue invitations

Add the schema and helper foundation for venue invitations to optionally target a trial staff row for account adoption.

## Design

Add nullable staff/adoption target FK to venue_invitations, index it, regenerate types, and add helper predicates for adoption eligibility. Enforce venue scope in application code initially and add tenant-integrity trigger coverage if the schema guard pattern supports it in this area.

## Acceptance Criteria

Generated types include the new optional adoption target; schema tests cover default/null behavior and same-venue/adoption eligibility expectations; normal invitation rows remain valid.

