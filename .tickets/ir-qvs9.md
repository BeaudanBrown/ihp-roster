---
id: ir-qvs9
status: in_progress
deps: []
links: []
created: 2026-05-28T00:17:34Z
type: feature
priority: 2
assignee: beaudan
tags: [feedback, launch]
---
# Add in-app feedback collection

Implement launch-ready in-app feedback submission with founder support review and unread badge.

## Design

Phase 1: schema and generated types; user feedback dialog; support page review/status/read actions; tests after chunks.

## Acceptance Criteria

Signed-in users can submit one-field feedback; support admins see unread badge and can mark/read/update feedback in Support; focused tests pass.


## Notes

**2026-05-28T00:36:28Z**

Implemented schema, user feedback dialog, support review panel, unread badge context, and focused controller coverage. Verification: regen-types/typecheck passed after schema; focused hspec FeedbackController+SupportController passed. Full hspec-test currently has an unrelated pre-existing roster week controls failure: /RosterWeeksController/manager roster pages render reusable week controls in the header/.
