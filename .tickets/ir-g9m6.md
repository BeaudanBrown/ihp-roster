---
id: ir-g9m6
status: closed
deps: [ir-xua1]
links: []
created: 2026-07-10T05:30:27Z
type: task
priority: 1
assignee: beaudan
parent: ir-zyk3
tags: [agent-loop, area:live-fragments, area:controllers, area:docs]
---
# Define actor-local invalidation-first mutation response pattern

Lock down the shared response contract for HTMX mutations so future forms do not mix business OOB, actor refresh headers, and validation rerenders ad hoc.

## Design

Document and, where useful, add narrow helpers for the pattern: validation failure returns the submitted form/fragment directly with errors; success returns actor-local invalidation instructions plus extras such as toast/dialog clear; touched resources drive actor and passive refresh wherever possible. State that successful business fragment/OOB responses are legacy/temporary unless a UI is not yet a live/refetchable surface.

## Acceptance Criteria

Controller/live-surface docs explain 'success invalidates; validation rerenders'. Later implementation tickets use this pattern or explicitly mark a temporary seam. No broad abstraction hides section-specific validation or domain mutation logic.

