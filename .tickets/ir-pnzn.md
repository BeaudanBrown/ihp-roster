---
id: ir-pnzn
status: open
deps: [ir-hgx0, ir-6d99]
links: []
created: 2026-06-02T07:20:13Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:xero, area:providers, timesheets]
---
# Port Xero preparation readiness preview submission and correction seams

Migrate the existing Xero guided timesheet flow onto provider-neutral preparation, readiness, preview, submission, and correction abstractions.

## Design

Refactor Xero preparation runs/decisions, readiness blockers, period selection, duplicate checks, preview payload persistence, submission runs/submissions/entries, idempotency, retry, and draft update/correction hooks so downstream Payroll flow is provider-neutral and Xero adapter owns Xero request/response construction.

## Acceptance Criteria

Xero draft timesheet preparation, preview, submission, retry, duplicate blocking, posted pay-run blocking, and correction/update seams remain functional through provider-neutral Payroll services. Xero-specific payloads and remote IDs are isolated to adapter/provider metadata and audit snapshots.

