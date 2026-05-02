---
id: ir-2usx
status: closed
deps: []
links: []
created: 2026-04-29T04:41:30Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [area:view, area:maintenance, source:plans-61]
---
# View helper split

Repo-local epic migrated from docs/archive/plans/61-view-helper-split.md. Reduces Application.Helper.View to a compatibility re-export wrapper and moves mixed helper implementations into focused modules.

## Design

source_plan: docs/archive/plans/61-view-helper-split.md
status: closed

2026-04-30 consolidation note:

- The helper split remains a prerequisite for later view ergonomics work.
- Keep the first pass mechanical and behavior-preserving; follow-on helper API
  additions are tracked separately in `ir-esmn` and OOB rendering cleanup in
  `ir-2vyr`.
- New helper implementations should not be added to
  `Application.Helper.View`; place them in the focused module that owns the
  concern and re-export only through the compatibility wrapper.

## Acceptance Criteria

Application.Helper.View contains no helper implementations, focused modules have explicit export lists, call sites compile, and rendered forms/labels remain unchanged.
