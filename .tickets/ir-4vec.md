---
id: ir-4vec
status: closed
deps: [ir-f8wn]
links: []
created: 2026-05-28T05:42:04Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-1e9i
tags: [area:roster, area:ui, agent-loop]
---
# Move roster wage chrome right and shorten wage labels

Adjust roster wage estimate placement and copy.

## Design

Move the week wage summary to the intended right-side roster header/toolbar area without regressing timesheet toolbar layout. Replace customer-visible labels such as 'Week wage estimate' and 'Wage estimate' with shorter 'Wages' language while preserving accessible meaning. Update day-row/day-column wage labels and tests.

## Acceptance Criteria

Week wage summary appears in the right-side roster header area; day and week wage labels use short 'Wages' copy; manager/staff visibility rules remain unchanged; focused Hspec/e2e assertions are updated.

