---
id: ir-uy4o
status: open
deps: [ir-4gm9, ir-p81g, ir-dvoi, ir-hreg]
links: []
created: 2026-07-08T04:59:57Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-5146
tags: [frontend-contracts, guardrails, htmx]
---
# Remove raw HTMX helper escape hatches

Remove helper APIs that expose arbitrary app-owned request-side HTMX after their callers have migrated.

## Design

Remove raw appToggleHx* fields or make them private/transitional only, replace remaining users with generated Surface/AppShell attrs, remove legacy raw OverlayFormAction, and tighten raw HTMX guardrails.

## Acceptance Criteria

No production helper exposes arbitrary request-side HTMX fields; guardrails catch raw request-side hx-* in app views/helpers; generated/custom-declared HTMX remains allowed.

