---
id: ir-6bqb
status: open
deps: [ir-1nps]
links: []
created: 2026-05-29T03:16:10Z
type: task
priority: 2
assignee: beaudan
parent: ir-oxnj
tags: [agent-loop, xero, nested]
---
# Migrate Xero staff mapping pay item and timesheet panel responses

Move nested Xero fragment actor responses to shared OOB fragments.

## Design

Use staff mappings, pay items, and timesheets fragments directly where dependencies are section-specific; normalize parent/child overlaps when shell is also returned.

## Acceptance Criteria

Nested Xero actor responses share fragment renderers with live GETs; no duplicate shell+child OOB responses are emitted; focused Xero specs pass.

