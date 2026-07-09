---
id: ir-bfvx
status: closed
deps: [ir-o1rw]
links: []
created: 2026-07-09T03:12:56Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-sli3
tags: [agent-loop, page-help, chunk]
---
# Add Admin Xero and Billing help topics

Add and wire role-aware page help for Admin, Xero, and Billing.

## Design

Use the shared page-help infrastructure. Keep Xero and Billing help aligned with their existing access gates: Xero owner/super-admin, Billing owner/super-admin. Gate founder-only billing controls separately from owner billing controls.

## Acceptance Criteria

Admin, Xero, and Billing pages render title-adjacent help triggers where the pages are accessible. Admin help covers venue settings, invites, staff/admin configuration, shift types, roster groups, and exports where visible. Xero help covers connection, reference sync, staff/pay item mappings, and preparation/submission at a high level. Billing help covers subscription status, Checkout/Portal, webhook/pending status language, and founder manual read-only where super-admin. Typecheck and focused help registry/filtering tests pass.

