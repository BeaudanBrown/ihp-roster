# ADR 0002: Haskell Owns Browser Business Authority

Status: accepted

Date: 2026-07-12

## Context

Bepis needs browser behavior that is reusable without moving business authority into TypeScript. Making all browser code feature-free would require a speculative and overly broad UI DSL, while generating only wire DTOs would leave business relationships and choices duplicated in feature scripts.

## Decision

Use an authority-only generic frontend. Haskell owns business relationships, choices, routes, payloads, canonical tags, and server/browser schemas. TypeScript may retain feature-local presentation mechanics, but consumes server-declared business meaning rather than deriving it from feature DOM structure.

Persisted app-owned finite domains use PostgreSQL enums and generated Haskell constructors; provider-owned vocabularies remain open at named adapters. Non-persisted finite request values use `WireClosed` over a finite Haskell type. Surface and AppShell mutations are nominal exact operations rather than text discriminators with optional supersets. Open tagged references may remain text only when their payload is intrinsically open, such as provider ids or UUID-tagged selections; their field names and parsers still belong to the nominal operation.

Promote a capability into the Haskell DSL and generated contracts immediately when TypeScript would otherwise interpret business authority, even for its first use. Keep presentation-only mechanics local until a second independent surface demonstrates a shared pattern; do not add speculative DSL vocabulary.

Use two declaration tiers. Closed reusable semantics—capability kinds, role and reference names, supported effects, policies, and legal combinations—belong in the surface DSL and generated manifest. Typed Haskell render helpers attach dynamic instance values such as opaque relationship keys, mount-local IDs, labels, and configuration. Pure HTML/CSS structure stays outside the DSL when the browser does not consume it.

Copy follows the same ownership rule. Haskell owns feature, workflow, compliance, and business-state copy. Generic TypeScript runtimes may provide default copy for generic browser mechanics, with Haskell-provided overrides where context changes the meaning. Browser-native failures are mapped to server-declared or generic categories rather than becoming business messaging directly.

All app-owned overlays participate in the declared `dialog`, `picker`, or `toast` lane. A generic lane runtime owns lifecycle, body locking, dismissal, loading, and focus restoration from generated configuration; feature code renders content and policy but cannot create a parallel modal lifecycle. Bootstrap can remain an internal rendering adapter, and passkey flows move through the dialog lane.

Haskell owns semantic widget configuration: customer-facing date/time formats and locale, allowed ranges and steps, workflow defaults, and labels/copy. Generic TypeScript and CSS own mechanical defaults such as animation timings, pointer thresholds, and internal scheduling, with typed Haskell overrides only when a demonstrated capability needs them.

Generated browser events contain semantic, serializable metadata only. Generic TypeScript event carriers compose that metadata with ephemeral DOM objects such as `Element` or the original `Event`; the contract DSL does not pretend browser objects are cross-language wire values. Typed constructors replace misleading empty generated event-detail types and independently handwritten semantic payloads.

For browser-platform protocols such as WebAuthn, Haskell owns exact server HTTP envelopes and generated TypeScript parsers/encoders, while a platform adapter converts base64url wire values to native browser objects. A narrowly scoped opaque-JSON field is permitted only for browser-defined extension output that the application does not interpret; it is not a general feature-contract escape hatch.

Generated semantic interaction policy is the sole current conflict-policy representation. The browser matches the active session and mounted fragment’s semantic key against generated policy, then uses the mount descriptor only for local target and URL execution. The separate resolved conflict-policy DOM attribute and handwritten parser are removed; mount-specific policy enters the exact mount contract only if a future demonstrated requirement needs it.

The browser `FrontendSurfaceRegistry` is a minimal production runtime projection, not an architecture catalog. Complete actions, dependencies, topology, authorization, DOM tokens, and other semantic facts remain in checked Haskell IR and deterministic architecture facts/queries. TypeScript contract tests cover browser-consumed fields; architecture-only assertions move to Haskell architecture tests.

Custom DOM attributes are classified by producer and consumer. Haskell-to-TypeScript attributes are browser contracts declared through the checked model and typed render helpers; TypeScript-to-Haskell work uses generated intents/forms. Generic TypeScript-to-CSS ephemeral state may remain module-owned, while Haskell-only presentation attrs and vendor/standard attrs stay outside browser contract generation. TypeScript discovers business identity, relationships, capabilities, and actions through generated roles/refs and opaque keys from the closest typed mount; local structural selectors are allowed only within an adapter-owned subtree, and vendor selectors stay in platform adapters.

TypeScript may own discardable, mount-local presentation state that is reconstructable from authoritative HTML/configuration and cannot affect business outcomes without a generated committed intent. Persisted browser state is limited to explicitly non-authoritative platform or UX hints; business preferences and workflow state remain server-owned.

Roster staff sorting remains a generic client-side presentation capability while the complete sortable set is rendered. Haskell declares keys, value types, ordered comparators and tie-breakers, defaults, and typed row/control roles; TypeScript applies the generated specification per mount. Pagination or incomplete client data requires a server-side sort action instead.

Roster staff and shift-group highlighting consolidate into one closed linked-highlight capability. Haskell declares keyed memberships, activation modes, and allowed effects; generic TypeScript manages mount-local hover, focus, keyboard activation, optional pinning, and cleanup. Initial effects cover matching-member/source classes and first/last ordered-member styling without arbitrary selectors or callbacks.

Toggle and range behavior uses three composable capabilities rather than a form mini-framework: toggle presentation, typed control dependency, and ordered-range presentation. Haskell composes them for timesheets and preferences; each has a focused generic runtime interface. Ordered ranges use a closed Haskell-owned crossing policy; shift preferences explicitly preserve the current `clamp-other-endpoint` behavior while server validation remains authoritative.

Roster week overview remains a feature-local presentation adapter until a second independent surface demonstrates a generic selection capability. Haskell supplies an exact generated payload with rendered copy, values, flags, and navigation target plus typed item/slot refs; the adapter only parses, selects, and projects those declared values.

Roster image export likewise remains a browser-native presentation adapter. Haskell supplies resolved annotations, filename/configuration, and optional export-specific rendered DOM; TypeScript owns measurement, Canvas/SVG, encoding, and download without inferring roster semantics. Do not introduce custom projection kinds, arbitrary selectors, or callback escape hatches until a concrete browser-only requirement proves annotations and server-rendered projection DOM insufficient.

Xero candidate filtering remains a feature presentation adapter until another independent consumer appears. Haskell renders typed filter roles and an opaque normalized search projection; TypeScript performs generic substring/subsequence matching and visibility toggling without knowing which Xero fields contributed to the projection.

## Consequences

Browser-native work can remain in TypeScript without making TypeScript a second domain authority. The DSL grows from demonstrated capabilities rather than anticipated reuse. Reviews must distinguish presentation mechanics from business interpretation. This is a universal consolidation rather than an opportunistic migration: every existing browser path must be classified as a generic runtime, browser-platform adapter, or feature-local presentation adapter and brought into compliance, with no untracked legacy exceptions left behind. A feature-local presentation adapter may consume typed Haskell declarations but cannot own business decisions, validation, canonical cross-boundary names, routes, payloads, or relationships; infer business meaning from DOM structure; or assume a singleton mount.

Generated TypeScript is a checked browser-visible projection, not a complete dump of Haskell contract metadata. A checked projection stage derives visibility for inherently browser-facing primitives and accepts explicit `BrowserBoundary` declarations for exceptional DTOs, then produces browser-visible IR for a decision-free TypeScript renderer. Validation rejects contradictory or unsupported exposure. Generation retains cohesive type/guard/parser/encoder groups and complete discriminated runtime unions, while server-only actions and architecture metadata remain in Haskell IR. Before pruning the projection, audit existing generated groups for parallel handwritten consumers, correct their shapes, and migrate those consumers so an integration gap is not mistaken for server-only metadata.

Enforce objective ownership rules automatically: canonical interaction names remain generated, unknown server JSON crosses generated parsers, TypeScript does not construct persistence URLs, generated unions stay exhaustive, feature adapters are mount-local, every production module has a recognized class, browser-visible contract groups have production consumers, and server-only groups do not leak into TypeScript. Semantic questions that tooling cannot reliably decide remain explicit review and focused-test concerns rather than motivating a speculative proof DSL. Module paths and import rules provide the normal classification, root `app-*.ts` files are thin composition entrypoints, and any exceptional placement requires an explicit guarded reason; unclassified files and stale exceptions fail the frontend checks.

Consolidation preserves documented and tested user behavior, not accidental coupling. Each migration slice identifies undocumented behavior; behavior that conflicts with the ownership or mount model requires an explicit product decision instead of silent preservation or removal. Unrelated UX changes stay outside the consolidation.

Deliver consolidation as complete cross-consumer capability slices rather than file-by-file or feature-by-feature conversions. Each slice carries one concept through the Haskell DSL and checked IR, generated browser projection, typed render helpers, generic TypeScript runtime, every current consumer, layered tests, deletion of replaced paths, and regression guardrails.

The first slice is contract authority rather than visible UI work: audit generated groups and handwritten parallels, correct conflict-policy and event representations, narrow runtime vocabulary types, generate passkey server DTOs, add checked browser visibility and module classification, establish baseline guardrails, and prune only confirmed server-only projections. New UI capabilities build on that foundation.

Every capability slice requires layered evidence: Haskell contract/IR tests, render-helper tests, TypeScript runtime tests, focused real-browser coverage where relevant, deletion guardrails, and focused drift/typecheck gates. Final consolidation requires the full repository and E2E gates with zero legacy exceptions. `typed-contract-authority-check` blocks generic production request seams, finite-value `WireText` regressions, handwritten migrated field names, discriminator envelopes, rendered generated-enum decisions, and unexplained Weeder debt; generated drift and compile-failure gates remain the semantic authorities.

## Alternatives Considered

- Require absolutely feature-free TypeScript, at the cost of an expansive browser behavior DSL.
- Generate only server/browser wire contracts and leave feature-specific business interpretation in TypeScript.

## Links

- Historical workstream: `docs/archive/typed-contract-authority.md`
- Living docs: `Application/Helper/Interaction.SPEC.md`, `Application/Helper/FrontendContract/Surface/README.md`
