---
id: ir-ap3i
status: closed
deps: []
links: []
created: 2026-06-30T07:48:30Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-flq7
tags: [architecture, bepis-actions, agent-loop]
---
# Add feature-specific mutation specs for high-risk controllers


## Notes

**2026-06-30T07:57:18Z**

Added named feature-level BepisMutationSpec values for admin/xero, roster week/preferences, timesheets, leave requests, staff, staff documents, billing, support, auth passkeys, user signup, feedback, profiles, passkey management, and sessions. Remaining generic mutation spec usage is limited to the E2E-only helper action. typecheck and strict architecture check passed.
