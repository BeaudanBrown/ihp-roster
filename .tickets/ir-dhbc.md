---
id: ir-dhbc
status: open
deps: [ir-ot1h]
links: []
created: 2026-07-03T02:45:01Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-rjfp
tags: [agent-loop, frontend, surfaces, interactions]
---
# Harden nearest-owner nested surface request handling

Ensure nested child controls bind to the closest mounted surface for request decoration and interaction boundaries.

## Design

Add frontend tests and any runtime fixes so HTMX request decoration, live-update client id, interaction/focus conflict behavior, and child/parent controls use the nearest containing surface mount unless future explicit bridge semantics are added.

## Acceptance Criteria

Child HTMX requests get child scope/client metadata; parent controls get parent metadata; child interactions do not leak to parent by default; Roster/Timesheets interaction tests do not regress.

