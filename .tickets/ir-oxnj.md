---
id: ir-oxnj
status: open
deps: [ir-3y9k]
links: []
created: 2026-05-29T03:16:09Z
type: epic
priority: 2
assignee: beaudan
parent: ir-cfcr
tags: [agent-loop, xero, admin, live-fragments]
---
# Migrate Admin Xero nested fragments to unified responses

Unify Admin Xero shell and nested section actor refreshes around shared fragment contracts and containment.

## Design

Admin Xero has shell, staff mappings, pay items, and timesheets fragments. Migrate carefully because auto-sync triggers, dialogs, and external API jobs are involved.

## Acceptance Criteria

Xero actor responses use shared fragment renderers; containment avoids duplicate shell/child swaps; existing Xero controller specs and contract tests pass.

