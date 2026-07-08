---
id: ir-lg7p
status: open
deps: [ir-h9xi, ir-qy7c, ir-m6ne, ir-fi5l]
links: []
created: 2026-07-08T09:28:50Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-2nrg
tags: [area:test, area:payroll, area:xero, area:exports, agent-loop]
---
# Add cross-surface award-rate rollover regression coverage

Add an end-to-end-ish Hspec regression suite proving the rollover rule across high-risk surfaces.

## Design

Use fixtures with venue week starting Monday, an old rate from a prior period, a new FWC operative_from on Wednesday, and expected Bepis effective date on the following Monday. Cover dropdown labels, SQL pay calculation, approved-entry stability, roster wage prediction if applicable, export payload parity, and Xero bucket/effective pay-item key behavior.

## Acceptance Criteria

Focused tests fail against stale/open-ended-row behavior and pass only when UI, SQL pay, exports, Xero, and predictions use venue-effective rate resolution; includes approved-entry non-rerating regression.

