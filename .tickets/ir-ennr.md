---
id: ir-ennr
status: closed
deps: [ir-8w6w, ir-npm8, ir-g6z3]
links: []
created: 2026-07-02T02:47:03Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces]
---
# Build type-level FrontendSurface lab

Create the type-level DSL foundation and a support-only lab page containing examples of all agreed primitives. This ticket does not own final GHC API TypeScript generation; `ir-xopg` owns generated TypeScript output from the lab spec.

## Design

- Define core promoted primitive constructors and authoring aliases/helpers that normalize to flat primitive normal form. Marker types are nullary data types at kind `Type`; browser wire types use `WireText`, `WireInt`, `WireBool`, `WireUUID`, `WireDay`, `WireList`, `WireOptional`, `WireNullable`, and `WireRef` rather than bare domain names:

  ```haskell
  Surface SurfaceMarker '[ primitive, primitive, primitive ]
  ```

- Core primitives to cover in the lab:
  - `Scope`
  - `Fragment`
  - `HtmxAction`
  - `Intent`
  - `Field` / `OptionalField` / nullable field shape if implemented separately
  - `Session`
  - `DisposableLayer`
  - `InteractionEffect`
  - `ConflictPolicy`
  - `LoadPolicy` / eager/lazy fragment option
  - `OverlayLane`
  - `ClientEvent`
  - `DomToken`
  - `Dto`
  - `MountState`
- Include at least one helper alias/bundle that expands into multiple primitives. Helper composition is allowed, but recursion/cycles are not supported.
- The lab route/page is support-super-admin-only and hidden from ordinary authenticated navigation.
- Lab authoring must use only:

  ```haskell
  type SurfaceLabSurface = Surface ...
  surfaceLabImpl :: SurfaceImpl SurfaceLabSurface
  ```

  not old `FrontendCodec`, DTO schema groups, `TypedLiveSurfaceDefinition`, old registry entries, `Application.Helper.SurfaceProjection`, or manual `InteractionStaticSchema`.
- The lab owns the minimal `SurfaceImpl` scaffold needed to mount a real surface; `ir-4hu6` later strengthens this into full completeness proofs. The lab should render eager and lazy fragments, exercise one HTMX action and one intent path, and emit/consume at least one generated-contract-shaped payload once `ir-xopg` lands.

## Acceptance Criteria

- The lab surface spec compiles and covers every primitive in the initial DSL.
- The lab page mounts through the minimal `SurfaceImpl` scaffold and renders without old author-facing frontend contract machinery.
- At least one eager fragment, one lazy fragment placeholder/refetch path, one HTMX action, one intent, one DTO payload, one DOM token, one client event, one overlay lane, one session/layer/effect, and one conflict policy are represented.
- Generated TypeScript output is not required by this ticket; the lab spec must be structured so `ir-xopg` can extract it without redesign.

## Notes

**2026-07-02T06:02:11Z**

Started foundation implementation after naming, transport, coexistence, and architecture-doc tickets closed. First chunk will add the type-level DSL/spec modules and a compile-only lab spec; likely pause point is the minimal SurfaceImpl runtime/mount shape before adding routes/views.

**2026-07-02T06:04:21Z**

Added compile-only FrontendSurface DSL foundation and support lab spec covering every initial primitive plus helper bundle expansion through Concat/Append. Registered the lab in RegisteredFrontendSurfaces. Verification: hspec-test compiled the new modules but DB reset is blocked by missing local postgres socket; direct build/Test/Main --match 'FrontendSurface DSL' passed. Pausing before runtime lab mount because the minimal SurfaceImpl shape is the next design decision.

**2026-07-02T06:20:25Z**

Added minimal SurfaceImpl runtime scaffold and support-only FrontendSurface lab page/actions. Lab route uses SupportController super-admin gate, mounts via SurfaceImpl SurfaceLabSurface, renders mount-local config (not data-live-update-surface), lazy panel placeholder/refetch, HTMX refresh action metadata, and move-card intent form metadata. Verification: typecheck passed; hspec-test --match 'FrontendSurface DSL' compiles but DB reset is blocked by missing local postgres socket; direct build/Test/Main focused runs passed.

**2026-07-02T06:21:21Z**

Acceptance sweep: lab spec covers Scope, Fragment, HtmxAction, Intent, Field/OptionalField/NullableField, Session, DisposableLayer, InteractionEffect, ConflictPolicy, LoadPolicy/eager/lazy, OverlayLane, ClientEvent, DomToken, Dto, and MountState. Lab page is SupportController-gated, mounts via SurfaceImpl SurfaceLabSurface, uses no TypedLiveSurfaceDefinition/FrontendCodec/SurfaceProjection, and includes eager shell, lazy panel, HTMX refresh action, and move-card intent form.
