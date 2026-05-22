---
id: ir-jh3g
status: closed
deps: [ir-qcsm]
links: []
created: 2026-05-22T01:41:01Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-gd3q
tags: [area:docs, area:roster, area:timesheets, agent-loop]
---
# Document roster timesheet cancellation semantics

Document how roster-to-timesheet jobs behave when a roster week returns to draft.

## Design

Update the living roster/timesheet specs to state that pending/retry roster-to-timesheet jobs are cancelled on live-to-draft, running jobs rely on execution-time checks, republish creates fresh jobs from current slot state, and generated timesheets remain authoritative records that are not mutated by roster changes.

## Acceptance Criteria

Web/RosterWeeks/SPEC.md and/or Web/Timesheets/SPEC.md describe the cancellation and race-safety contract without implying a generic app-job cancellation feature.


## Notes

**2026-05-22T02:48:59Z**

HANDOFF: Documented roster-timesheet cancellation semantics in Web/RosterWeeks/SPEC.md and Web/Timesheets/SPEC.md, including pending/retry cancellation result, running-job safety checks, republish behavior, and generated-timesheet authority; verification: bash ./bin/in-env ./bin/doc-drift-check failed on pre-existing AGENTS.md nav text mismatch (expects leave vs current unavailability wording); remaining risk: doc-drift gate still needs separate cleanup.
