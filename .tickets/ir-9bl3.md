---
id: ir-9bl3
status: open
deps: [ir-q5uu]
links: []
created: 2026-06-02T07:20:13Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:providers, auth, jobs]
---
# Build generic payroll provider token refresh and keepalive service

Move provider token refresh and connection keepalive behavior out of Xero-specific code into a reusable Payroll provider service.

## Design

Implement refresh-on-demand before API calls plus scheduled keepalive jobs with provider-specific cadence. Preserve Xero refresh-token rotation semantics and add MYOB support for short access tokens and short-lived refresh tokens. Deduplicate refresh jobs, avoid concurrent rotation races, and distinguish reauthorization_required from provider credential/update failures.

## Acceptance Criteria

Active provider connections refresh reliably without user action. Xero keepalive behavior is preserved. MYOB can refresh OAuth without company-file credentials. Invalid_grant/revocation marks the connection for reauthorization and triggers Payroll live invalidation without leaking token material.

