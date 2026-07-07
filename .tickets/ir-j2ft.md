---
id: ir-j2ft
status: open
deps: [ir-ni05]
links: []
created: 2026-07-07T03:24:11Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-elys
tags: [frontend-contracts, haskell, htmx]
---
# Add generic Haskell FrontendSurface action render helpers

Render HTMX request attrs from generated surface action metadata plus term-level route/path handlers.

## Design

Add reusable helpers in `Application.Helper.FrontendContract.Surface.Runtime` or a nearby module. Helpers combine declared action metadata with Haskell-supplied route/path functions and dynamic field values. The DSL/IR owns browser-visible action semantics; Haskell owns IHP `pathTo`/`appendQueryParams` construction.

Provide helper modes for at least:

- form actions: render standard `method`/`action` where appropriate plus `hx-*` request attrs;
- submit button actions: render `formaction` where appropriate plus `hx-*` attrs;
- link actions: render `href` where appropriate plus `hx-get` attrs;
- HTMX-only actions: render only declared HTMX attrs and generated metadata.

Support declared custom HTMX attrs only through the explicit `CustomHtmx` lane. Document that standard HTML attrs preserve browser semantics but do not guarantee a full no-JS UX unless the controller returns full-page/redirect fallbacks.

## Acceptance Criteria

- Generic helpers render declared methods, request attrs, hidden fields, and generated `data-bepis-surface-action` metadata.
- Route construction is supplied by typed Haskell functions/handlers rather than the type-level DSL.
- Helpers can represent existing Admin Roster Groups create/update/move/toggle controls.
- Undeclared custom HTMX attrs are not part of the helper API.
