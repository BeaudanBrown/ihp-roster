---
id: ir-h55v
status: closed
deps: []
links: []
created: 2026-06-16T01:42:51Z
type: task
priority: 1
assignee: beaudan
tags: [trial-staff, invites, ui]
---
# Polish trial staff adoption invite feedback

Show immediate success toast after sending a trial staff adoption invite and update the staff details modal/email area to indicate a pending invite.

## Acceptance Criteria

Sending an adoption invite from a trial staff details modal returns an HTMX success toast and re-renders the modal with the email field replaced by pending-invite state; reopening a trial staff details view with a pending invite also shows pending state; linked staff behavior remains unchanged; focused controller tests and typecheck pass.


## Notes

**2026-06-16T01:45:10Z**

Implemented HTMX success toast and pending-invite modal state for trial staff adoption invites. Sending from staff details now returns the refreshed modal plus toast OOB. Trial staff with a pending staff-linked invitation show the invited email with a Pending invite badge instead of the invite input. Focused StaffController Hspec and typecheck passed.
