---
id: ir-j9yz
status: closed
deps: [ir-ypks]
links: []
created: 2026-05-16T01:26:23Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-3pnb
tags: [area:live-fragments, area:billing]
---
# Add billing subscription live surfaces

Add typed live surfaces for venue billing/subscription state so local billing actions and Stripe webhook updates refresh open billing/admin views.

## Design

Define billing surface scopes around current venue billing authority. Fragment refs should cover subscription summary, status badges, and actionable billing controls. Webhook or local billing mutations should broadcast typed invalidations without exposing billing fragments through weaker auth than the billing page.

## Acceptance Criteria

Billing/subscription state changes update mounted billing/admin fragments live. Fragment endpoints use typed authorization. Contract and focused billing controller tests cover config, refs, auth, and rendering.


## Notes

**2026-05-16T02:19:41Z**

Added typed billing status live surface and fragment endpoint; local billing updates and Stripe webhook processing broadcast typed billing invalidations.
