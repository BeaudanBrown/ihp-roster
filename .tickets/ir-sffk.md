---
id: ir-sffk
status: open
deps: [ir-gj02]
links: []
created: 2026-05-22T06:52:44Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-h2xi
tags: [area:live-fragments]
---
# Make live fragment dependency choices explicit

Replace bare dependency lists in FragmentContract with an explicit dependency declaration such as DependsOn/ResyncOnly.

## Acceptance Criteria

Each fragment declares either live resources or an intentional resync-only reason; affected-fragment planning remains unchanged for dependent fragments.

