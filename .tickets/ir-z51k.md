---
id: ir-z51k
status: closed
deps: []
links: []
created: 2026-04-30T06:29:25Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-5rhn
tags: [area:security, area:validation, area:controllers]
---
# Add shared request validation helpers and harden required fields

Create reusable controller-side helpers for required typed params, optional typed params, field-level parse failures, normalized text fields, and bounded text. Apply them to high-risk forms where IHP fill currently ignores missing params: leave requests, timesheet entries, staff/profile editing, venue onboarding, and admin config names/emails.

## Design

Keep validation inside record builders where possible so errors render next to fields. Preserve existing HTMX validation rerender behavior. Never rely on HTML required/select/hidden controls as the only enforcement.

## Acceptance Criteria

Missing required fields produce validation errors instead of defaults or DB exceptions; malformed typed params do not produce unhandled 500s; focused Hspec coverage exists for leave, timesheets, staff/profile, onboarding, and admin config boundaries.

## Notes

**2026-04-30T07:54:33Z**

Implemented Application.Helper.Controller.Input helpers; applied required-param, text normalization, and bounded text validation to leave, timesheets, staff/profile, onboarding, and admin name/email flows. Added focused Hspec coverage.
