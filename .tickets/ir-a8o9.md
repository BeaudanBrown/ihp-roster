---
id: ir-a8o9
status: open
deps: [ir-grmo]
links: []
created: 2026-06-28T12:17:09Z
type: feature
priority: 1
assignee: beaudan
parent: ir-osr3
tags: [agent-loop, live-surfaces, lazy-loading, htmx]
---
# Render reusable lazy live fragment mounts

Add a generic view helper that renders a live fragment either eagerly or as a lazy HTMX placeholder using the typed surface fragment metadata.

## Design

Create helper(s) that take a TypedLiveSurfaceDefinition, scope, fragment, and eager Html renderer. For FragmentEager, render the eager Html. For FragmentLazy, render a root element using the fragment contract/ref target id and URL: id, data-bepis-lazy-surface/fragment, hx-get, hx-trigger, hx-target=this, hx-swap=outerHTML, hx-push-url=false, aria-busy=true. The loaded fragment endpoint must continue returning the real root with the same id. Keep helper usable from existing view modules without circular imports.

## Acceptance Criteria

A caller can replace ad-hoc eager rendering with the helper; generated lazy placeholders use the existing fragment URL/target id; eager mode output remains unchanged except for unavoidable wrapper decisions documented in code; fragment permission/authorization remains on the server endpoint.

