# Live Fragment Cookbook

Use this checklist when adding or changing collaborative server-rendered
fragments. The source of truth for production authoring is the type-level
`FrontendSurface` system documented in
`Application/Helper/FrontendSurface/README.md`.

## Vocabulary

- **Surface**: an independently mounted UI owner rendered with
  `data-bepis-surface` and `data-bepis-surface-config`.
- **Scope**: the authorized subscription identity for a mounted surface.
  `Scope` fields define the wire payload and scope key inputs; auth is declared
  with exactly one `Authorize ...` or `NoAuth` marker.
- **Live fragment**: a `Fragment ... '[ ..., Live, ... ]` whose currently
  mounted instance can be invalidated over the websocket.
- **Resource**: a generated `SurfaceResourceValue` emitted by mutation
  or domain code to describe concrete data that changed.
- **Dependency planning**: active subscriptions provide mounted wire fragments;
  generated `DependsOn` declarations turn scope/fragment params into concrete
  resource values; touched resources intersect those dependencies to choose the
  affected fragments.
- **Actor response**: the immediate HTMX response for the browser that made a
  mutation.
- **Passive invalidation**: the websocket message that tells other mounted
  browsers to refetch authorized fragments.
- **Contained child surface**: an independently mounted child surface rendered
  inside a parent fragment. The browser reconciles actual DOM mounts after page
  loads and swaps.

## Adding Or Changing A Live Fragment

1. Update the relevant type-level surface spec under
   `Application.Helper.FrontendSurface.*`.
2. If the fragment participates in passive websocket invalidation, add `Live`
   and exactly one invalidation mode:
   - `DependsOn SomeResource '[ 'FromScope Field, 'FromFragment Field, ... ]`,
     or
   - `ResyncOnly` for fragments that have no passive business-resource
     dependency.
3. Add or update generated resource declarations when the fragment depends on a
   new concrete data shape.
4. Implement/update the `SurfaceImpl` fragment handler with the target id, GET
   URL, focused-field protection, load policy, and renderer.
5. Render mounts/fragments with FrontendSurface runtime helpers; do not handwrite
   live-update attrs or construct wire DTOs in feature views.
6. Make mutations emit generated `SurfaceResourceValue` smart constructors for the
   concrete values they changed. Keep any broad domain expansion producer-side or
   in a small feature-owned helper before invalidation.
7. Add focused Hspec/frontend/E2E coverage for mount config, subscription
   validation, dependency planning, actor response behavior, and passive
   refetches as applicable.
8. Run the frontend surface checks and relevant test slices.

## Guardrails

Do not add new `TypedLiveSurfaceDefinition`, `data-live-update-surface`,
legacy registry/catalog adapters, `SurfaceProjection` cache plumbing, custom
FrontendSurface dependency hooks, or handwritten live transport case lists.
Surface metadata comes from `RegisteredFrontendSurfaces`; runtime subscriptions
are surface-native `LiveUpdateSubscription` values; passive invalidation is
planned in `Web.SurfaceInvalidation` via generated FrontendSurface
resources and dependencies.
