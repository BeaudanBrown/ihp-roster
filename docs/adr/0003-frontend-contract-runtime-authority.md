# ADR 0003: FrontendContract Is the Runtime and Wire Authority

Status: accepted

Date: 2026-07-13

## Context

Interactive server-rendered features need the same names, field shapes,
reachability rules, HTMX metadata, mount targets, subscription scopes, fragment
keys, and interaction refs in Haskell and TypeScript. Parallel evaluators and
browser manifests allowed these facts to drift, while transport metadata could
accidentally become executable browser authority.

## Decision

Use the closed Haskell `FrontendContract` DSL as the sole declaration language
for browser-visible and Surface contracts.

- Explicit typeclass reflection is the sole evaluator.
- The checked unified IR is the input to validation, runtime metadata,
  architecture facts, and TypeScript rendering.
- Reflected names may be rendered, transported, compared as identities, and
  validated, but downstream code must not switch on them to recover semantics;
  reflection produces closed IR constructors for behavioral choices.
- Marker-indexed values and declaration-ordered `SurfaceFields` are the Haskell
  runtime interface.
- Every fragment declares one typed `MountTarget`; mounted descriptors and
  rendered DOM IDs use `surfaceFragmentTargetId` over the same typed fields.
- Generated TypeScript exposes only explicitly reachable operations and the two
  minimal production registries for fragments and interactions.
- Live transport carries authorized semantic scope and fragment keys. A
  browser executes only the URL, target, and protection metadata from its local
  server-rendered mount.
- Unknown properties, Surface disagreement, undeclared fields, and ownership
  mismatches fail at generated parser, IR-validation, or compile time.
- App-owned Haskell-to-TypeScript roles, state, keys, and payloads are reflected
  contracts with generated names and exact boundary parsers. Standard/vendor
  vocabulary and presentation-only HTML/CSS hooks remain behind focused adapters.

## Consequences

A contract change has one evaluator and one checked model to inspect. Haskell
and TypeScript drift is caught deterministically, raw target-ID drift is not a
production construction option, and the browser cannot turn websocket payloads
into executable request authority.

The DSL remains deliberately closed. New wire or HTMX vocabulary requires a
reflection instance, checked-IR representation, rendering behavior, and focused
property/compile-fail coverage. Browser reachability must have a real production
consumer. A completed migration removes its raw/open interface rather than
retaining a compatibility path.

## Alternatives Considered

- Inspect compiler internals as a second evaluator: rejected because parity and
  compiler-version coupling create another source of truth.
- Keep compact Surface adapters beside the unified IR: rejected because copied
  fields can diverge.
- Emit complete action and Surface manifests to the browser: rejected because
  server-only facts become ambient browser authority and unused bundle weight.
- Accept raw mounted target IDs in feature code: rejected because action,
  descriptor, and rendered IDs can drift independently.

## Links

- Tickets: GitHub #136, #143–#152
- Living docs: `Application/Helper/FrontendContract/README.md`,
  `Application/Helper/FrontendContract/Surface/README.md`,
  `Application/Helper/LiveUpdate.SPEC.md`, `Application/Helper/Interaction.SPEC.md`
