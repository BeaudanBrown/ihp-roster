---
id: ir-ktxt
status: open
deps: [ir-q5uu, ir-9bl3]
links: []
created: 2026-06-02T07:20:13Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:xero, area:providers, auth]
---
# Port Xero connection lifecycle to payroll provider foundation

Adapt Xero OAuth, tenant selection, reconnect, disconnect, and connection-state behavior to the provider-neutral connection schema and service boundary.

## Design

Move Xero connection logic behind the Payroll provider adapter while preserving full-page OAuth security flows, encrypted token handling, connected tenant metadata, delete/disconnect semantics, reauthorization state, and owner/super-admin access.

## Acceptance Criteria

Xero can connect, refresh, reconnect, and disconnect through the Payroll page/provider foundation. Existing Xero connection tests pass or are migrated to provider-neutral names. No Xero token material is logged or stored outside encrypted fields.

