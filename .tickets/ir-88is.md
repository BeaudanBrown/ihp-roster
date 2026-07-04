---
id: ir-88is
status: closed
deps: [ir-f7ho]
links: []
created: 2026-07-04T03:20:00Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-888o
tags: [agent-loop, surfaces, interaction, typescript]
---
# Implement manifest-backed browser interaction runtime beside legacy runtime

Add the new mounted-surface-instance interaction runtime while legacy semantic marker runtime remains transitional.

## Design

Add mounted `FrontendSurface` instance interaction hydration, parse generated manifest/static schema, resolve role-specific refs inside the closest mounted surface, and implement activation plus pointer session lifecycle using manifest semantics. Continue DOM-owned HTMX form submission by resolving the matching form in the mount, validating emitted fields against generated schema and form fields, then dispatching the generated trigger. Keep the old semantic runtime temporarily for unmigrated paths only.

## Acceptance Criteria

- Frontend unit tests cover activation, pointer sessions, dropzone hit testing, effects, and form bridge through new refs.
- Old runtime remains only as explicitly transitional code.
- No custom mutation `fetch`, URL construction, or browser-owned mutation transport is introduced.
- Runtime is surface-instance-centric and handles duplicate/nested mounts through nearest mounted surface resolution.
