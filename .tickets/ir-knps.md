---
id: ir-knps
status: open
deps: [ir-bub1, ir-n00b]
links: []
created: 2026-05-08T00:01:10Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-xbga
tags: [area:billing, area:ui, area:auth]
---
# Add owner and super-admin billing surfaces

Add authenticated billing routes and views for venue owners to start/manage subscription payments and for super admins to inspect billing state and toggle manual read-only status.

## Design

Use hosted Stripe Checkout and Customer Portal redirects only. Venue owners may create checkout/portal sessions for their current venue. Super admins can inspect any active venue and set manual billing read-only with a reason. Do not grant entitlement from Checkout success redirects; webhooks are authoritative.

## Acceptance Criteria

Owner-only access, support-mode access, passkey/privileged checks where appropriate, success/cancel return pages, and super-admin toggle flows are covered by focused controller tests and UI smoke coverage.

