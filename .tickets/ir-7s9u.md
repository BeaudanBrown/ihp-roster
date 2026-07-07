---
id: ir-7s9u
status: open
deps: [ir-oxnj]
links: []
created: 2026-05-29T03:16:10Z
type: task
priority: 1
assignee: beaudan
parent: ir-kuyy
tags: [agent-loop, research, confirmation, high-risk, frontend-surface]
---
# Confirm roster semantic invalidation strategy and scroll ownership

Deeply research roster update paths before changing the highest-risk surface.

## Design

Inspect roster live surface, render data, responses, controller actor refresh helpers, grid/header targets, week/group navigation, assignment filters, staff panel, direct/projection backend behavior, interaction conflict policy, and horizontal frame ownership. Decide which semantic fragments each success path should invalidate, how row/day precision is preserved without actor business OOB, and whether week navigation should preserve or reset scroll.

## Acceptance Criteria

Ticket note records migration sequence, scroll owner boundaries, semantic actor-local invalidation replacement strategy, duplicate-mount implications, direct/projection concerns, and any intentionally deferred paths. No production behavior changes are made.
