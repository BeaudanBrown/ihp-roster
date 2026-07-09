---
id: ir-o8nm
status: open
deps: [ir-o1rw]
links: []
created: 2026-07-09T03:12:56Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-sli3
tags: [agent-loop, page-help, chunk]
---
# Add Profile Timesheets and Unavailability help topics

Add and wire role-aware page help for Profile, Timesheets, and Unavailability/leave requests.

## Design

Use the shared page-help infrastructure. Keep topic copy close to implemented behavior in the relevant local SPEC/README docs. Gate manager/admin review sections separately from staff self-service sections.

## Acceptance Criteria

Profile, Timesheets, and Unavailability pages render title-adjacent help triggers. Profile help covers personal details, preferences/availability, security/passkeys, and documents/RSA when visible. Timesheets help covers week navigation, creating/editing entries, break fields, approval/review where role permits, and approved-entry constraints. Unavailability help covers adding unavailable periods, user-friendly end-date semantics, pending/approved/denied lifecycle, and manager approve/deny where role permits. Staff-only viewers do not see manager-only review guidance. Typecheck and focused help registry/filtering tests pass.

