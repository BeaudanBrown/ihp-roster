---
id: ir-5dd9
status: closed
deps: [ir-vgwk]
links: []
created: 2026-06-29T13:12:15Z
type: task
priority: 2
assignee: beaudan
parent: ir-21jr
tags: [agent-loop, frontend, lazy-loading, ui-regions]
---
# Refactor lazy retry and error handling onto Bepis region events

Update lazy-surface TypeScript to consume Bepis region lifecycle events instead of directly owning raw HTMX listeners.

## Design

Keep retry/error UI generic and parameterized by server-rendered attrs. Preserve HTMX retry processing and current UX while moving the event dependency to the region seam.

## Acceptance Criteria

Existing lazy error/retry behaviour remains; frontend tests cover response error, send error, timeout, and retry markup; no feature-specific lazy JavaScript is introduced.


## Notes

**2026-06-29T13:32:21Z**

Lazy surface retry/error handling now consumes generated Bepis region lifecycle events instead of raw HTMX listeners, with retry gated by data-bepis-lazy-retry. Verification: frontend-test, frontend-contracts-check, frontend-check, typecheck passed.
