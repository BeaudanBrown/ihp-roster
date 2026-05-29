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
tags: [agent-loop, research, confirmation]
---
# Confirm final cleanup inventory after all migrations

Research the final state and confirm what cleanup remains before making broad guardrail changes.

## Design

Search for hx-swap-oob, render.*Oob, setTypedLiveSurfaceActorRefresh, live Page fragments, direct successful hx-target outerHTML forms, and docs that still describe the older split. Confirm any intentional exceptions.

## Acceptance Criteria

Ticket note lists remaining paths by category: migrate now, intentional exception, or separate future ticket; no production behavior changes are made.

