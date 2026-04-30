---
id: ir-qksy
status: open
deps: []
links: []
created: 2026-04-30T06:29:38Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-5rhn
tags: [area:security, area:validation, area:preferences]
---
# Replace unsafe request-derived ID parsing

Remove unsafe textToId use and similar exception-based parsing from user-controlled inputs. The immediate target is staff shift preference composite keys, with a wider scan for any request-derived IDs that can crash or bypass validation UX.

## Design

Use UUID.fromText or ParamReader-based parsing that returns Maybe/Either. Convert malformed composite keys into user-facing validation errors and keep existing allowed-roster-group/slot/weekday checks.

## Acceptance Criteria

Malformed shiftPreferenceKeys and malformed request IDs return validation failures or 4xx/redirect responses without 500s; preference update tests cover invalid UUID text, invalid weekday text, cross-group slot IDs, and cross-venue IDs.
