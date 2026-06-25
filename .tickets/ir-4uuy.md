---
id: ir-4uuy
status: closed
deps: []
links: []
created: 2026-06-16T13:45:27Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jsyd
tags: [agent-loop, docs, frontend, htmx, interaction, live-fragments]
---
# Document typed interaction surface contract

Write the shared contract for typed disposable interaction surfaces, generated intent events/forms, server/live ownership boundaries, and mobile/pointer behavior.

## Design

Use `docs/workstreams/typed-interaction-surfaces.md` as the planning source and move the actionable contract into living docs near the implementation seams. At minimum update or create docs under `Application/Helper/` for the Haskell contract, and update `frontend/AGENTS.md`/`static/AGENTS.md` so future agents know the rules before editing runtime code.

Capture the full vocabulary and hierarchy: surface family, surface scope, concrete mount, server layer, live fragment type/ref, containment path, disposable layer, disposable session, intent type, intent field schema, intent form contract, conflict policy, generated TypeScript contract, and generic runtime. Make clear that interaction capabilities attach to the same typed surface origin as live fragments, initially empty for existing surfaces.

Document the golden path:

1. Feature code declares closed Haskell types for disposable layers and intents.
2. Haskell contracts define intent field schemas, HTMX form metadata, and live-fragment conflict policy.
3. Haskell helpers render surface mounts, server layers, disposable layers, markers, and forms.
4. Generated TypeScript exposes browser-boundary DTOs/unions.
5. Generic TypeScript manages disposable sessions, emits intents, fills generated forms on commit, and never mutates business DOM or constructs persistence URLs.
6. IHP validates, mutates, and returns authoritative fragments/OOB responses.

Include the HTMX decision: start with standard HTMX forms, custom event `hx-trigger`, lifecycle events, `hx-sync`/`hx-disabled-elt` where useful, and OOB swaps; do not start with HTMX extensions/custom elements. Include the live-update policy: non-conflicting swaps may apply behind disposable UI, conflicting swaps defer/cancel according to typed policy, actor responses win and clear disposable UI, and timeouts prevent indefinite deferral.

## Acceptance Criteria

- Living docs define the typed interaction hierarchy and distinguish server-owned DOM, live fragments, disposable UI, local widget DOM, and intent forms.
- Docs state that Haskell owns canonical surface/fragment/layer/intent names, field schemas, HTMX attrs, target ids, and conflict policy; TypeScript consumes generated contracts.
- Docs explain surface portability and duplicate mounts through concrete mount keys.
- Docs describe intent phases, commit-only default submission, strict field validation, and examples for click/select, drop, resize, and non-drag disposable UI such as menus/selection overlays.
- Docs describe live-fragment conflict policy and actor/passive update behavior.
- `static/AGENTS.md` or a local SPEC points future work to the contract.
- No code behavior change is required beyond docs, but `bash ./bin/in-env ./bin/doc-drift-check` should pass if doc drift checks cover touched files.

