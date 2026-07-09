---
id: ir-hh99
status: open
deps: [ir-kjhs]
links: []
created: 2026-07-09T05:06:02Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-7wsy
tags: [agent-loop, docs, roster, interaction]
---
# Document reusable typed drag/drop and roster staff drop behavior

Update living docs for the final multi-source drag/drop pattern and roster staff drop behavior.

## Design

Update Web/RosterWeeks/SPEC.md, Web/RosterWeeks/README.md if useful, Application/Helper/Interaction.SPEC.md, FrontendContract Surface authoring docs, and roster page help if user-facing drag instructions changed. Explicitly document non-goals: no touch drag and no day-column whitespace create target for staff drag.

## Acceptance Criteria

Docs describe final staff drag/drop behavior and the reusable typed source/dropzone compatibility pattern. Existing roster move/copy behavior remains documented. doc-drift-check passes.

