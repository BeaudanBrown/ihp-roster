---
id: ir-2usx
status: open
deps: []
links: []
created: 2026-04-29T04:41:30Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [area:view, area:maintenance, source:plans-61]
---
# View helper split

Repo-local epic migrated from plans/61-view-helper-split.md. Reduces Application.Helper.View to a compatibility re-export wrapper and moves mixed helper implementations into focused modules.

## Design

source_plan: plans/61-view-helper-split.md
status: planned

## Acceptance Criteria

Application.Helper.View contains no helper implementations, focused modules have explicit export lists, call sites compile, and rendered forms/labels remain unchanged.

