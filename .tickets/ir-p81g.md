---
id: ir-p81g
status: open
deps: [ir-83ct]
links: []
created: 2026-07-08T04:59:57Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-5146
tags: [frontend-contracts, app-shell, chrome]
---
# Migrate app chrome partial navigation to AppShellAction

Move app shell partial navigation request metadata out of handwritten HTMX and into AppShellAction.

## Design

Migrate Application/Helper/View/Chrome.hs partial navigation. Verify page-content swaps continue to reconcile mounted FrontendSurface instances/subscriptions. Add or adjust guardrails/tests for chrome HTMX.

## Acceptance Criteria

Chrome partial navigation renders through AppShell helpers; no raw request-side HTMX in Chrome.hs; surface lifecycle after page-content swaps remains covered.

