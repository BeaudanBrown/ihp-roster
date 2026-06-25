---
id: ir-w50d
status: closed
deps: [ir-4uuy, ir-95e7, ir-libm]
links: []
created: 2026-06-16T13:45:39Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jsyd
tags: [agent-loop, haskell, frontend, htmx, interaction]
---
# Add typed surface, layer, and intent-form render helpers

Provide reusable IHP/HSX helpers that render interaction surface mounts, server layers, disposable layers, typed item/slot/handle markers, and HTMX intent forms from Haskell contracts instead of handwritten attributes.

## Design

Use the typed interaction capability and generated contract vocabulary from `ir-fq28`/`ir-95e7`. Helpers should be the supported authoring path for interaction markup. They should render stable, mount-local attributes and ids for:

- concrete interaction surface mounts, including surface family/scope/mount metadata;
- server layers that contain authoritative server-rendered live fragments;
- disposable layers for ephemeral frontend UI;
- typed item, container, slot, dropzone, resize-handle, and activation markers where needed by generic runtime;
- typed intent forms with hidden inputs from field schemas;
- HTMX method/route/action, trigger, target, swap, sync, and disabled-element metadata from Haskell form contracts.

The same surface family/scope must be movable across pages and mountable multiple times. Form targets and DOM ids should derive from a concrete mount key rather than hardcoded global ids.

Add guardrails where practical: tests or static checks should discourage raw `data-bepis-*` interaction attrs and handwritten intent HTMX forms in feature views outside approved helper modules/tests.

## Acceptance Criteria

- Shared Haskell helpers render standard interaction surface mount, server layer, disposable layer, and intent form markup from typed contracts.
- Helper output keeps HTMX method/URL/target/swap/trigger server-rendered.
- Hidden inputs match the Haskell intent field schema.
- Duplicate/moved surface mounts can derive distinct ids and targets.
- Representative helper output has Hspec/golden-style coverage.
- A guard/test documents or enforces that feature views should not handwrite raw interaction attrs/forms.
- Docs examples match helper output.
- `bash ./bin/in-env typecheck` and focused helper/guard tests pass.

