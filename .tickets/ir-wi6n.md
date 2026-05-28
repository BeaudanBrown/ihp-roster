---
id: ir-wi6n
status: in_progress
deps: [ir-zrpb, ir-uhsd]
links: []
created: 2026-05-27T23:58:34Z
type: task
priority: 2
assignee: beaudan
parent: ir-5n96
tags: [area:e2e, area:test]
---
# Regression-test unified toggle behavior

Add/update tests for shared toggle rendering and behavior after migration.

## Design

Use Hspec markup assertions for representative server-rendered controls and Playwright for key interactive paths. Avoid brittle full-page text assertions; prefer stable ids/data attributes.

## Acceptance Criteria

Tests verify active buttons render green, inactive buttons render outline green, aria state tracks checked state, and HTMX/form submissions continue to work for roster live, timesheet filters, and at least one admin/Xero toggle.

