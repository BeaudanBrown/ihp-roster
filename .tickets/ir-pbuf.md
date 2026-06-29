---
id: ir-pbuf
status: closed
deps: [ir-vgwk]
links: []
created: 2026-06-29T13:12:16Z
type: chore
priority: 2
assignee: beaudan
parent: ir-21jr
tags: [agent-loop, docs, htmx, ui-regions]
---
# Audit and document non-fragment HTMX boundaries

Document which current HTMX uses should and should not participate in the UI region lifecycle.

## Design

Categorize declared fragments/regions, dialog/overlay lanes, validation-local responses, partial navigation, and ordinary local controls/autosave. Clarify that only server-declared regions emit Bepis region lifecycle events.

## Acceptance Criteria

Docs state when not to add data-bepis-fragment; dialogs, validation responses, and partial navigation remain out of scope unless future tickets opt them in deliberately; future agents have clear migration guidance.


## Notes

**2026-06-29T13:41:09Z**

Documented UI region/non-region HTMX boundaries in LiveUpdate.SPEC and LiveSurface.COOKBOOK: only server-declared fragments emit Bepis region lifecycle events; dialogs, validation responses, partial navigation, autosave/local controls, and plain HTMX remain out of scope. Verification: doc-drift-check passed.
