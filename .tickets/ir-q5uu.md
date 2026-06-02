---
id: ir-q5uu
status: open
deps: [ir-ha1c]
links: []
created: 2026-06-02T07:20:13Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:providers, area:schema]
---
# Add provider-neutral payroll connection schema foundation

Introduce provider-neutral connection persistence that can represent Xero now and MYOB later while preserving venue scope and auditability.

## Design

Add tables or columns for payroll provider connections, OAuth states, token expiry/rotation metadata, selected remote organisation/company-file identifiers, connection status, provider-specific raw metadata, and one-active-provider-per-venue enforcement. Preserve historical connections and submitted records with soft-delete/retention guardrails.

## Acceptance Criteria

Schema supports exactly one active payroll provider per venue, stores encrypted OAuth token material without provider-specific table coupling, preserves historical provider records, passes regen-types and typecheck, and includes venue-integrity and hard-delete protections matching existing Xero safety patterns.

