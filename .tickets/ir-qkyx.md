---
id: ir-qkyx
status: open
deps: []
links: []
created: 2026-05-28T05:42:04Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-pups
tags: [area:profile, area:rsa, area:ui, agent-loop]
---
# Remove duplicate RSA header and default profile accordions closed

Clean profile section chrome.

## Design

Remove the extra inner RSA heading/header from RSA profile panels so the accordion title owns the section heading. Adjust profile accordion logic so sections are closed by default unless the request explicitly selects a section or a validation workflow needs one reopened.

## Acceptance Criteria

RSA section no longer has a duplicate inner header; profile accordions are closed by default for ordinary profile visits; section query/validation flows still open the intended section; tests are updated.

