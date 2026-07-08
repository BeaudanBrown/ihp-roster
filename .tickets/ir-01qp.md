---
id: ir-01qp
status: open
deps: [ir-2yh1]
links: []
created: 2026-07-08T08:24:31Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-5udu
tags: [area:xero, area:maintenance, cleanup-refactor]
---
# Split Xero client and timesheet preparation internals

Split the largest Xero helper and preparation modules into focused internals while preserving public behavior.

## Design

Split Application/Helper/Xero.hs into focused client/config/crypto/request/response-oriented modules while preserving facade exports initially. Split Application/Xero/Timesheets/Prepare.hs by workflow step where safe, such as staff decisions, period selection, pay item decisions, remote refresh/snapshot, readiness/view assembly, and submit/preview orchestration. Coordinate with active Xero payroll/provider tickets including ir-176p, ir-mjov, and provider-migration overlap. Keep access rules, Xero API behavior, audit/history rows, error text, and controller response shape unchanged.

## Acceptance Criteria

Main Xero helper/preparation files are materially shorter and more focused. Existing imports can still use compatibility exports where useful. bash ./bin/in-env typecheck passes. bash ./bin/in-env hspec-test --match "Xero" or a documented focused equivalent passes.

