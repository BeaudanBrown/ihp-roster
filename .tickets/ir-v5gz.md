---
id: ir-v5gz
status: open
deps: [ir-bs0c]
links: []
created: 2026-05-28T05:42:04Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-kjc9
tags: [area:roster, area:ui, agent-loop]
---
# Highlight missing roster fields after failed go-live

Make failed live attempts visually identify required roster fields that need attention.

## Design

When ToggleRosterWeekLiveStatusAction fails because staffed shifts are missing required start time, end time, or shift type, re-render the roster with an explicit publish-attempt/error state. Mark the specific missing controls/cells with warning/red classes and accessible labels/messages. Keep ordinary draft editing neutral until a live attempt fails.

## Acceptance Criteria

After a failed live attempt, missing required fields are visibly marked and accessible; fields are not marked before a failed live attempt; fixing fields and going live clears the state; Hspec or Playwright coverage verifies the failed-publish rendering.

