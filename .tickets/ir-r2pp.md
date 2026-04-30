---
id: ir-r2pp
status: closed
deps: []
links: []
created: 2026-04-30T06:31:22Z
type: task
priority: 2
assignee: beaudan
parent: ir-m8hc
tags: [area:docs, area:xero, area:authz, source:2026-04-30-audit]
---
# Annotate Xero owner-only access as superseding older venue-admin plan text

plans/58-xero-connection-foundation.md still says venue admins can open/manage Xero, while current code and tests restrict Xero management to venue owners and super admins.

## Design

Add a clear current-status note to plan 58 and any related docs that says owner-only access supersedes the original venue-admin wording. Keep root AGENTS.md owner-only guidance as the active rule.

## Acceptance Criteria

No active Xero guidance tells agents to expose Xero controls to venue admins; plan 58 is clearly marked superseded where it conflicts; tests remain aligned with owner/super-admin-only behavior.
