# Typed Interaction Surfaces

Status: active; durable implementation contract lives in `Application/Helper/Interaction.SPEC.md` and `Application/Helper/FrontendContract/Surface/README.md`.

This workstream now tracks the generated `FrontendSurface` interaction architecture. Historical typed-live-surface planning has moved to archive/history and must not guide new production work.

## Goal

`FrontendSurface` declarations are the source of truth for live fragments and interaction semantics. A surface declaration owns:

- surface, scope, fragment, resource, intent, field, session, layer, effect, and conflict-policy names;
- generated source, dropzone, and activation refs;
- generated TypeScript manifests consumed by generic browser runtimes;
- Haskell render helpers that attach role-specific refs plus opaque dynamic keys to server-rendered DOM;
- server-rendered HTMX intent forms used for mutation transport.

TypeScript remains generic and surface-instance-centric. It resolves refs through the generated manifest, manages disposable sessions/effects, validates payloads/forms, and dispatches generated HTMX triggers. It must not invent canonical `data-bepis-*` names, business rules, mutation URLs, fragment keys, layer names, intent names, field names, or target ids.

## Current Contract

- Render a surface with `renderFrontendSurfaceMount` and a `SurfaceImpl`.
- Declare interaction refs in the `FrontendSurface` spec.
- Render role-specific DOM refs via `Application.Helper.FrontendContract.Surface.Interaction` helpers:
  - source refs carry a generated source ref and an opaque server-owned source key;
  - dropzone refs carry a generated dropzone ref and an opaque server-owned target key;
  - activation refs carry only the generated activation ref unless a concrete control needs normal form values.
- Submit mutations through generated/server-rendered HTMX forms. Mount JSON is not a mutation transport contract.
- Keep all business authorization and validation server-side.
- Coordinate live updates through generated surface subscriptions and conflict policies.

## Guardrails

- Do not reintroduce `TypedLiveSurfaceDefinition`, `LiveSurfaceConfig`, `LiveSurfaceManifest`, `data-live-update-surface`, or feature-local dependency mirrors.
- Do not reintroduce legacy semantic interaction markers such as `data-bepis-marker`, `data-bepis-pointer-session`, `data-bepis-session-kind`, `data-bepis-session-intent`, `data-bepis-activation-intent`, or broad `data-bepis-item`/`data-bepis-dropzone` runtime parsing.
- Do not add feature-specific JavaScript adapters for roster/profile/timesheet behavior.
- Do not handwrite production surface config, subscription, or interaction attributes in views; use generated helpers.

## Verification

Use the focused checks relevant to a change:

```bash
bash ./bin/in-env frontend-contracts
bash ./bin/in-env frontend-check
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "FrontendSurface"
```
