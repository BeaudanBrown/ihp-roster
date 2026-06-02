---
id: ir-b76j
status: open
deps: [ir-0o6u, ir-ktxt]
links: []
created: 2026-06-02T07:20:13Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:xero, area:providers, reference-sync]
---
# Port Xero reference sync and mappings to payroll provider tables

Migrate Xero employee, earnings-rate, account, payroll-calendar, pay-run, staff mapping, and local bucket mapping behavior onto the provider-neutral reference model.

## Design

Refactor Xero sync/read-model/controller code so Xero adapter performs API calls and provider-neutral services persist/query reference data. Preserve stale mapping detection, account selection, payroll calendar selection, sync run audit state, and raw payload snapshots.

## Acceptance Criteria

After sync, the Payroll UI can render Xero reference and mapping state from provider-neutral read models. Existing Xero mapping and readiness behavior remains functionally equivalent. Venue-scoped uniqueness and stale detection still protect remote changes.

