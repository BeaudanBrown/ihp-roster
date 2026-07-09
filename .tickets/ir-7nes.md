---
id: ir-7nes
status: open
deps: []
links: []
created: 2026-07-09T02:39:01Z
type: bug
priority: 2
assignee: Beaudan Brown
parent: ir-z20h
tags: [agent-loop, frontend, overlays]
---
# Fix dialog backdrop mouseup close behavior

Prevent dialogs from closing when a pointer starts outside the modal and releases inside it.

## Design

Update the dialog overlay runtime so backdrop close is based on a valid same-target backdrop click/pointer sequence rather than mouseup alone. Preserve explicit close buttons and escape behavior.

## Acceptance Criteria

Click-hold outside then release inside a dialog no longer closes the modal. Normal backdrop click, close button, and escape behavior still work. Frontend test or focused E2E covers the regression if practical.

