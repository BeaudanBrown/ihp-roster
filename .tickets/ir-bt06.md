---
id: ir-bt06
status: closed
deps: []
links: []
created: 2026-05-02T01:12:23Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9jap
tags: [area:availability, area:ux, area:pilot, venue:rooks]
---
# Rename leave request UI to availability language

## Design

Rename staff-facing leave request language because the app does not process formal paid leave. Keep the existing unavailability workflow and approval behavior, but present it as Availability / Unavailable period / Add unavailable time. Formal paid leave stays absent from the pilot UI.

## Acceptance Criteria

Staff-facing navigation, page titles, actions, empty states, forms, toasts, and validation copy avoid 'leave request' wording; records are presented as unavailable periods; existing behavior and data model remain intact unless a rename is required for clarity; formal paid leave is not introduced.


## Notes

**2026-05-02T01:45:33Z**

2026-05-02: Completed in commit 2eb2670. Staff-facing leave request language now renders as Availability / unavailable periods / Add unavailable time across nav, pages, forms, toasts/validation, profile, roster conflict copy, and tests. Behavior and data model were left unchanged.
