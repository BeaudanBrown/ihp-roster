---
id: ir-96hz
status: closed
deps: []
links: []
created: 2026-05-20T07:39:51Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-sh3h
tags: [agent-loop, area:staff, area:compliance, area:rsa]
---
# Define RSA current-document semantics

Make the RSA current-vs-history behavior explicit before wiring PDF prefill into the upload flow.

## Design

Keep staff_documents append-only for retained history, but present RSA as one current document in the UI. Define how pending replacements, rejected replacements, still-valid previous verified documents, expired documents, and manager/admin visibility interact. Prefer helper functions/read models over broad schema changes unless a status/supersession field is required. Expiry/reminder behavior should target the effective current RSA state and make manager/admin action visible.

## Acceptance Criteria

There is a documented and tested helper/read-model contract for effective current RSA state per staff member; uploading a new RSA is treated as a pending replacement rather than an in-place edit; previous rows remain retained; rejected replacement behavior is explicit when an older verified RSA is still valid; manager/admin compliance views can identify missing, pending replacement, expiring, and expired states; no full history UI is added.


## Notes

**2026-05-20T07:52:57Z**

Implemented RSA effective-state read model with append-only pending replacement/rejected replacement semantics, admin compliance pending-replacement badge, docs, and focused Hspec coverage.
