---
id: ir-kjhs
status: open
deps: [ir-j08r, ir-3t6e]
links: []
created: 2026-07-09T05:06:02Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-7wsy
tags: [agent-loop, tests, roster, interaction]
---
# Cover roster staff drag/drop and interaction compatibility

Add focused frontend and Haskell coverage for source/dropzone compatibility and roster staff drop semantics.

## Design

Add frontend tests for compatibility filtering and modifier regression. Add RosterWeeks Hspec/controller coverage for staff assignment replacement, modal prefill, ineligible/cross-scope/live/closed rejection, and existing shift move/copy regression. Add focused E2E only if browser hit-testing or modal behavior cannot be adequately covered by unit/controller tests.

## Acceptance Criteria

frontend-test or frontend-check covers generic compatibility behavior. Focused RosterWeeks Hspec covers server semantics. Existing roster drag/drop regression coverage remains green. Any added E2E is focused and documented in the ticket notes.

