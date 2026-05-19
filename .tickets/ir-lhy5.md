---
id: ir-lhy5
status: open
deps: [ir-8usq, ir-mjos, ir-l0x7]
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

Use the shared dialog overlay mount. The Xero timesheet panel shows a period selector and one primary Prepare action. The action opens the modal via HTMX and starts/continues the preparation run.

Replace debug-style accordion chores with an end-user decision queue/status flow. The modal should show current progress, next required decision, blockers/warnings, proposed staff matches, manual staff dropdowns, persistent not-paid controls, run-scoped skip controls only for unmapped staff, pay-item creation approvals, preview rows, and final submit/cancel controls. Advanced diagnostic detail may remain secondary/collapsible, but the primary path is Prepare -> resolve required decisions -> show preview -> explicit Submit confirmation.

Keep OAuth reconnect as native navigation when required. Do not add a separate staff match button; automated proposals appear directly as approval rows and manual dropdowns can override them. Do not expose local staff-to-calendar assignment controls.

## Acceptance Criteria

The modal fits phone-sized viewports, uses shared overlay footer patterns, preserves owner/super-admin auth, and can resolve all preparation decisions without leaving the Xero panel except for OAuth reconnect. Users can understand why staff were included, excluded for another Xero calendar, skipped for this run, or marked not paid through Xero. Submit remains an explicit confirmation after preview, not part of the automatic Prepare advance.
