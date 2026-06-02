---
id: ir-acnv
status: open
deps: [ir-45ed, ir-6d99]
links: []
created: 2026-06-02T07:20:14Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:myob, area:providers, ui]
---
# Integrate MYOB into shared Payroll UI flows

Expose MYOB setup, sync, mappings, pay items, preparation, preview, submission, and corrections through the shared Payroll interface.

## Design

Add provider selection/setup screens, MYOB connection state, reference sync controls, staff/pay item mappings, wage-category readiness, period selection, preparation modal steps, preview tables, submission status, retry/update affordances, and credential prompts according to provider capabilities.

## Acceptance Criteria

Venue owners/super-admins can complete the MYOB direct API setup and timesheet submission workflow from Payroll without Xero-specific labels. Shared components handle provider labels/capabilities and tests cover mocked MYOB happy path, blocker path, and credential-required path.

