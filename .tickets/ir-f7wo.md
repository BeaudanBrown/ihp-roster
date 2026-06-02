---
id: ir-f7wo
status: open
deps: [ir-pnzn]
links: []
created: 2026-06-02T07:20:13Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:xero, area:providers, testing]
---
# Verify Xero parity on provider-neutral Payroll foundation

Prove the migrated Xero provider remains usable before MYOB implementation starts.

## Design

Run focused Hspec/E2E coverage for Xero connection, sync, mappings, managed pay items, preparation/readiness, preview, submission, live invalidation, access control, and navigation through the Payroll surface. Document any intentionally changed labels/routes and update local specs.

## Acceptance Criteria

Xero behavior that existed before the migration is verified through provider-neutral Payroll surfaces. The ticket records verification commands and outcomes. MYOB implementation tickets remain blocked until this parity gate passes.

