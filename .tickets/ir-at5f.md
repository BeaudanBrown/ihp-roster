---
id: ir-at5f
status: open
deps: [ir-89ds]
links: []
created: 2026-07-01T02:44:57Z
type: feature
priority: 2
assignee: beaudan
parent: ir-ao41
tags: [agent-loop, frontend, typescript, interaction]
---
# Implement dropzone-highlight contextual pointer effect

Add a generic contextual effect that highlights the active dropzone during pointer sessions.

## Design

Implement dropzone-highlight as a contextual effect driven by existing hit-testing for data-bepis-dropzone markers. The runner activates/updates it for the current target and cleans the previous target when the pointer leaves or switches. It applies only the configured class/ephemeral attrs and never changes business content or interaction/HTMX contract attrs. Submission field behavior for targetDropzoneKey remains unchanged.

## Acceptance Criteria

Frontend unit/DOM tests cover no target, entering a target, switching between targets, leaving targets, and session-end cleanup. Previous highlights never leak. Existing targetDropzoneKey commit fields remain unchanged. frontend-test/frontend-check pass.

