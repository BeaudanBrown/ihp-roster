---
id: ir-5dd9
status: open
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

