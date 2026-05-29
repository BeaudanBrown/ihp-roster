---
id: ir-ez90
status: open
deps: [ir-zmfc]
links: []
created: 2026-05-29T03:16:11Z
type: task
priority: 3
assignee: beaudan
parent: ir-78cn
tags: [agent-loop, cleanup]
---
# Remove obsolete fragment compatibility helpers

Delete old helper branches and compatibility code superseded by the unified pattern.

## Design

Remove leftover renderMainFragmentOob booleans, page/shell live fragments, actor-only OOB helpers, and unused actor-refresh wrappers in migrated areas.

## Acceptance Criteria

Code search shows no obsolete helpers in migrated surfaces; typecheck passes.

