---
id: ir-acd3
status: closed
deps: [ir-5653, ir-7b4c, ir-l8l8, ir-7o5p]
links: []
created: 2026-05-21T03:35:20Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-asw6
tags: [agent-loop, roster, docs]
---
# Document roster shift type badge and colour contract

Update living roster/admin docs for the implemented badge, colour assignment, and publish validation contract.

## Design

Update Web/RosterWeeks/SPEC.md with day-column badge behaviour, standard day-boundary expectation, and publish-time shift-type requirement. Add local agent/spec notes near admin shift type code if the colour assignment helper introduces reusable invariants. Note that manual colour configuration is intentionally out of scope and should be a future ticket.

## Acceptance Criteria

Living docs describe the implemented behaviour and non-goal of manual colour configuration. Future agents can find the colour uniqueness/default rule without reading the whole implementation.


## Notes

**2026-05-21T04:10:55Z**

Updated Web/RosterWeeks/SPEC.md with shift type badge, colour assignment/default, publish validation, day-boundary, and manual-colour non-goal contract; added a helper note near the colour assignment policy. Verification: bash ./bin/in-env ./bin/doc-drift-check failed on pre-existing AGENTS.md nav text mismatch (expects leave vs current unavailability).
