---
id: ir-zmfc
status: open
deps: [ir-kuyy]
links: []
created: 2026-05-29T03:16:11Z
type: task
priority: 2
assignee: beaudan
parent: ir-78cn
tags: [agent-loop, research, confirmation, frontend-surface]
---
# Confirm final actor invalidation cleanup inventory after migrations

Research the final state and confirm what cleanup remains before making broad guardrail changes.

## Design

Search for `hx-swap-oob`, `render.*Oob`, feature actor-refresh helpers, `liveFragmentsRefreshEvent`, direct successful `hx-target`/`outerHTML` forms, and docs that still describe the older actor business-OOB split. Confirm intentional exceptions: validation-local fragments, extras-only OOB, pure fragment GET/refetch endpoints, non-FrontendSurface legacy, and separately ticketed future work.

## Acceptance Criteria

Ticket note lists remaining paths by category: migrate now, intentional exception, or separate future ticket. No production behavior changes are made.
