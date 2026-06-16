---
id: ir-olct
status: open
deps: [ir-patj]
links: []
created: 2026-06-16T01:03:30Z
type: task
priority: 1
assignee: beaudan
parent: ir-3qq9
tags: [agent-loop, controller, invites]
---
# Create trial staff adoption invitations

Allow existing invitation senders to generate worker-only invitations linked to a chosen trial staff placeholder.

## Design

Add a mutation for creating a pending worker invitation with the adoption target after checking current venue, active/unarchived trial status, and normalized email. Reuse existing durable invitation delivery job and admin-invite touched resources. Add a UI entry point from the trial staff edit/management flow rather than changing role selection semantics.

## Acceptance Criteria

Authorized normal invite senders can send an adoption invite for current-venue trial staff; unauthorized users and cross-venue/already-linked staff are rejected; delivery job/mail uses the existing invite link; admin invite surfaces refresh.


## Notes

**2026-06-16T01:07:49Z**

UI placement decision: add the first adoption invite form where the Email field normally appears in the staff details/profile form for trial staff. For linked staff keep the existing read-only email display. For trial staff render an email address input and submit button that posts a worker-only adoption invite for that staff id.
