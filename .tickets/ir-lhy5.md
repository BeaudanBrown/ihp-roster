---
id: ir-lhy5
status: open
deps: [ir-8usq, ir-mjos]
links: []
created: 2026-05-08T04:22:38Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9u78
tags: [area:xero, area:payroll, ui]
---
# Build Xero preparation modal UI and controller flow

Replace the current timesheet panel preview/submit buttons with a period selector and modal-driven preparation/resolution workflow.

## Design

Use the shared dialog overlay mount. Panel action opens the modal via HTMX. The modal shows loading/progress, proposed actions, manual staff dropdowns, not-paid and skip-this-time controls, pay-item creation approvals, blockers, preview rows, and final submit/cancel controls. Keep OAuth reconnect as native navigation when required. Do not add a separate staff match button; automated proposals appear directly as approval rows and manual dropdowns can override them.

## Acceptance Criteria

The modal fits phone-sized viewports, uses shared overlay footer patterns, preserves owner/super-admin auth, and can resolve all preparation decisions without leaving the Xero panel except for OAuth reconnect.

