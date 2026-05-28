---
id: ir-uhsd
status: closed
deps: [ir-1d53]
links: []
created: 2026-05-27T23:58:34Z
type: task
priority: 2
assignee: beaudan
parent: ir-5n96
tags: [area:admin, area:xero, area:billing, area:ui]
---
# Convert admin, Xero, and billing toggles to shared buttons

Apply the shared button-toggle pattern to lower-frequency switch-style controls across admin configuration, Xero mapping/preparation, and billing support controls.

## Design

Migrate Admin.Common show inactive, VenueSettings booleans, Xero show matched toggles, Xero preparation show matched, and Billing manual read-only while preserving methods, routes, and HTMX behavior.

## Acceptance Criteria

App-wide search for form-switch only returns intentionally documented exceptions; admin/Xero/billing toggle actions still submit/refetch correctly; focused controller or browser coverage validates representative toggles.

