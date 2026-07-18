# FrontendContract Authority Hardening

Status: active

GitHub issues:

- `#136` - Make FrontendContract the executable runtime authority and retire stale runtime code
- Contract authority: `#161`-`#166`
- Haskell adapter ergonomics: `#180`-`#192`
- Shared browser capabilities: `#167`-`#173`
- Roster browser capabilities: `#174`-`#178`
- Final reconciliation: `#179`
- Post-reconciliation hardening: `#193`-`#196`

GitHub owns live status, native sub-issue relationships, and blocker state.

Living docs to update as slices land:

- `Application/Helper/FrontendContract/README.md`
- `Application/Helper/FrontendContract/Surface/README.md`
- `Application/Helper/Interaction.SPEC.md`
- `Application/Helper/LiveUpdate.SPEC.md`
- `Application/Helper/View/AGENTS.md`
- `Web/RosterWeeks/AGENTS.md`
- `frontend/AGENTS.md`
- `static/AGENTS.md`

Durable decision:

- `docs/adr/0003-frontend-contract-runtime-authority.md`

## Goal

Finish the repository-wide move to `FrontendContract` as the sole authority for
app-owned server/browser vocabulary. Contract-bound production code must use
marker-indexed, declaration-complete interfaces; transport carriers must be
opaque; browser-visible names and exact parsers must be generated; checked IR
must carry semantics without downstream string redispatch.

This work preserves site behavior. The obsolete Surface Lab is removed, while
the currently disabled roster week overview remains retained and is migrated
without being re-enabled.

## Why This Work Exists

A post-refactor audit found that the typed DSL and accessors exist, but important
callers still reconstruct declared identities from text. Concentrated examples
include live scopes/fragments, Surface resources, action and intent fields,
controller request parsing, wire tagged unions, interaction effects,
authorization policies, and generator reachability exceptions.

The browser boundary also contains at least 53 explicit custom attribute names
shared between production Haskell and TypeScript, before accounting for
`dataset.*` spellings. Some are simple roles or opaque correlation keys; others
are shallow clusters that should become exact generated payloads. Shared
semantic classes also couple Haskell, TypeScript, and CSS.

## Language

- **Contract identity**: a canonical name declared by `FrontendContract`, such
  as a Surface, scope, fragment, resource, action, intent, field, ref, schema,
  union case, event, DOM role, or closed effect.
- **Contract-bound use**: a value crossing the particular boundary governed by
  a declaration. An unrelated route or domain payload may use the same English
  spelling without becoming owned by that declaration.
- **Browser role**: an app-owned generated attribute identifying an element's
  capability or relationship to a browser adapter.
- **Opaque key**: a server-issued dynamic correlation value the browser may
  compare or return but must not parse as business authority.
- **Presentation hook**: HTML/CSS vocabulary not consumed by TypeScript and not
  carrying business or runtime meaning. It remains outside the DSL.
- **Semantic redispatch**: reflecting a marker to text and later switching on
  that text to recover behavior. Checked IR constructors must replace it.
- **Boundary golden**: a focused test that intentionally asserts one canonical
  literal spelling. Ordinary behavior tests consume typed/generated values.

## Authority Rules

1. Haskell-to-TypeScript semantic vocabulary and TypeScript-to-Haskell
   intent/form vocabulary are generated from checked contracts.
2. Haskell-to-CSS presentation hooks remain local. Generic TypeScript-to-CSS
   ephemeral state may remain module-owned.
3. Shared semantic state uses native/ARIA state where correct, otherwise a
   generated closed app state. Classes remain presentation-only except for
   canonical closed runtime effects.
4. Standard and vendor vocabulary stays behind focused adapters. Existing typed
   HTMX action primitives and render helpers own `hx-*`; custom app DOM attrs do
   not duplicate HTMX.
5. A DSL field owns only contract-bound uses. Route context, native forms,
   external payloads, and database values retain their own owners.
6. Surface-owned browser attributes use
   `data-bepis-<surface>-<role>`; focused global capabilities use
   `data-bepis-<capability>-<role>`. Naming is derived, collision-checked, and
   has no ordinary exact-name override.
7. Element roles use generated attrs; cross-element relationships use opaque
   keys; cohesive multi-field data uses exact generated DTOs and parsers rather
   than one scalar attribute per property.
8. Static guarantees extend through typed serialization. At the unavoidable DOM
   boundary, one generated exact parser rejects malformed input for that
   element, emits a structured diagnostic, and leaves server-rendered HTML
   intact. Feature code must not guess or supply handwritten fallback data.
9. Reflected names may be rendered, transported, identity-compared, or validated,
   but behavioral choices use closed checked-IR constructors.
10. No compatibility shim or replaced raw interface survives a completed slice.

## Typed Interface Contract

### Surface and live identities

Live scopes, fragment keys, resources, mounted target IDs, action fields, and
intent fields are built through marker-indexed helpers and declaration-ordered
fields. Raw transport/resource constructors are opaque to feature code. Typed
matchers replace feature-name and JSON-field switches. Generic live and planner
modules contain no feature catalog.

### Controller request fields

Controllers parse a complete declared action or intent field bundle in one
operation. Required, optional, and nullable presence follows the DSL. Missing
or malformed required fields enter normal structured validation; required text
never silently becomes an empty string. Route/CSRF parameters outside the
contract remain valid request context.

### Global wire carriers

Ergonomic Haskell carrier ADTs remain. Schema-indexed record and tagged-union
builders derive discriminator, case, and field names plus presence and wire
types. Inbound JSON is checked against IR before a validated declared case is
mapped to a carrier constructor. Carrier modules do not repeat wire literals.

### Browser DOM boundaries

Add Surface-owned browser role/state attributes when one mounted Surface owns
the vocabulary. Reusable capabilities use focused global contracts. Explicitly
browser-reachable DTOs generate types and exact parsers; server-only Surface
DTOs remain absent from browser output. The active toggle capability is the
first generated role/config payload slice because the handwritten bridge has a
confirmed event-time stale-value regression. The time-picker capability follows
as the owner of picker-internal roles/configuration; it does not recreate toggle
submission or break-region authority. The retained dormant week overview is
migrated only after the active foundations exist.

### Interaction and authorization semantics

Effects and authorization policies lower directly to closed checked IR. Unknown
or incomplete effects fail validation instead of disappearing. Required layer
or option references are typed and validated. Feature declarations select
closed effects; they cannot inject arbitrary selectors or callbacks. Browser
projection is derived from inherently browser-facing primitives or explicit
exceptional boundaries, never a generated Surface name.

## Capability Slices

The native sub-issues under `#136` are grouped as follows. Each slice includes
its typed interface, all current consumers, tests, deletion of replaced paths,
guardrails, and living-doc updates.

### Contract authority

1. `#161` - Remove Surface Lab and replace necessary coverage with test-only fixtures.
2. `#162` - Make live scopes and fragment keys typed, opaque, and feature-owned.
3. `#163` - Make Surface resources typed, opaque, and feature-owned.
4. `#164` - Add complete typed action/intent field construction and request parsing.
5. `#165` - Add schema-indexed Haskell record/tagged-union builders and migrate carriers.
6. `#166` - Replace semantic string redispatch with closed checked IR.

### Haskell adapter ergonomics

These follow the typed authority slices. They generate only deterministic,
checked-IR projections; feature-local business semantics remain handwritten.
They run after their native blockers and in parallel with browser capability
slices, and all block final reconciliation.

7. `#180` - Improve compact type diagnostics for marker-indexed Surface APIs.
8. `#181` - Add deterministic Haskell Surface adapter generator foundation after
   schema-indexed carrier/source-type mapping.
9. `#182` - Generate feature-owned typed Surface resource adapters, beginning
   with a representative locality/net-deletion checkpoint.
10. `#188` - Extract the shared kind-indexed adapter generation core while
    preserving resource output byte-for-byte.
11. `#183` - Track typed Surface live identity adapters through native
    sub-issues:
    - `#190` - Add the focused generated Live renderer, checked normalization
      seam, compiled fixture, atomic output composition, and identity goldens.
    - `#189` - Migrate production scope/fragment adapters through private
      `.Generated.Live` modules and curated `Live` facades.
12. `#184` - Track typed Surface action and intent adapter facades through native
    sub-issues:
    - `#185` - Add the kind-separated generated action/intent renderers and
      compiled fixture.
    - `#186` - Coordinate the all-or-nothing Action migration through:
      - `#191` - Capture the independent Profile/Staff boundary and split the
        focused request-adapter test seam without publishing partial homes.
      - `#192` - Publish the complete Action home set and migrate all production
        Action callers.
    - `#187` - Publish and migrate the complete Roster Intent set, then make
      every Action/Intent output lane mandatory. **Complete.**

### Shared browser capabilities

13. `#169` - Reliable toggle submission/presentation and timesheet break controls, including the active roster live-status regression.
14. `#167` - Time picker roles and exact configuration payload, consuming but not duplicating the toggle/break boundary.
15. `#168` - Dialog/toast overlay DOM vocabulary.
16. `#170` - Ordered-range shift preferences.
17. `#171` - Horizontal drag/snap scrolling.
18. `#172` - PWA installation adapter.
19. `#173` - Xero candidate filtering adapter.

### Roster browser capabilities

20. `#174` - Surface-owned linked-highlight roles and stale interaction class cleanup.
21. `#175` - Staff-panel sorting/tabs and browser-reachable Surface DTOs.
22. `#176` - Fullscreen and column-edit controls.
23. `#177` - Image-export annotations and configuration.
24. `#178` - Retained dormant week overview.

### Reconciliation

25. `#179` - Run the zero-legacy audit, finish dynamic CSS/source guardrails,
    reconcile living docs, and verify the full repository before closing `#136`.

The authority foundations through #182 are complete. The #182 implementation
used Timesheets as its first representative resource migration, recorded the
feature-local import, handwritten-line deletion, and focused compile checkpoint
in the Surface authoring guide, then registered every remaining unique resource
home. #188 extracted the kind-indexed shared core, fixed the four private
output/facade pairs, and retained byte-identical resource output. #190
established the checked Live renderer/output lane, compiled fixture, atomic
all-kind composition, and independent identity goldens. #189 then accepted a
Timesheets Live checkpoint, registered every production scope/eligible fragment
home, and migrated all curated Live facades behind seven private generated
modules, completing #183. #185 established separate checked Action and Intent
renderers, operation-complete production inventories, curated compiled fixtures,
and atomic all-kind composition while retaining all 14 Resource/Live outputs.
#191 captured the independent Profile/Staff boundary, focused request-adapter
spec, deletion estimate, and cold compile/import baseline without publishing a
partial home set. #192 then atomically published all 48 eligible Action homes
behind six curated facades, migrated every production builder/metadata/parser
consumer, made Action output mandatory, and installed zero-generic-parser and
zero-generic-metadata guards while preserving the five typed declaration
exclusions. #187 then published all five Roster intents together behind one
private generated module and curated facade, migrated every production caller,
made all four generated lanes mandatory, removed the temporary publication and
parent-expiry abstractions, and installed final zero-generic-parser/metadata
guardrails. #184 follows #164 and #181.
Shared browser slices depend on typed schema builders. `#169` is the next
priority: it must distinguish rendered presentation state from submitted target
state, generate the checked/unchecked mapping, retain one generic form-local
browser adapter, remove semantic inline handlers and duplicate responsive ids,
and prove event-time payload plus authoritative persistence on desktop/mobile.
Ordered ranges also depend on toggle presentation. `#167` owns picker internals
whereas `#169` owns toggle submission and break-region activation.
Roster linked highlighting depends on closed interaction IR. Staff-panel work
establishes the browser-reachable Surface DTO path for image export and week
overview. The Haskell adapter slices run in parallel with capability slices and
final reconciliation depends on every preceding slice.

## Behavior Constraints

Except for Surface Lab removal, preserve:

- user-visible workflows and copy;
- routes, form behavior, authorization, and validation;
- live invalidation and interaction behavior;
- appearance and accessibility;
- HTMX replacement behavior and duplicate-mount correctness.

Internal app-owned DOM names may change atomically across Haskell, TypeScript,
CSS, tests, and generated artifacts. Undocumented DOM vocabulary is not an
external compatibility interface. Unrelated UX changes belong in separate
issues.

## Enforcement

Primary enforcement uses hidden raw constructors, marker-indexed builders,
compile-failure ownership/type tests, exact runtime parsers, and generated drift
checks. Targeted source guards reject raw app contract attributes, raw field
construction, feature access to transport constructors, semantic text dispatch,
bypasses of typed HTMX helpers, and inline event handlers that translate
contract values or duplicate generic submission behavior. Simple native
submit-only handlers remain valid when they carry no contract mapping. A blanket
scan for every common reflected word is prohibited because unrelated contexts
may share spellings.

CSS checks are deterministic:

- every CSS `data-bepis-*` selector must exist in reflected contracts;
- every emitted closed interaction-effect class must have CSS coverage;
- generated attrs not intended for styling need not appear in CSS;
- module-owned TypeScript/CSS ephemeral classes use focused lifecycle tests.

Canonical literals appear once in focused boundary goldens where useful.
Behavior tests use typed Haskell or generated TypeScript values to avoid churn.

## Verification

Every capability slice runs:

- frontend contract generation and drift checks;
- frontend Surface guardrails;
- Haskell typecheck;
- focused Hspec contract/render/controller coverage;
- focused TypeScript tests;
- compile-failure tests for new typed boundaries;
- focused E2E coverage when DOM behavior changes.

Final reconciliation also runs full Hspec, lint, formatting, E2E, and
documentation-drift gates. No database schema or migration work is expected.

## Exit Criteria

- All child issues are closed and native blocker relationships reconcile.
- Production Haskell and TypeScript contain no handwritten app-owned
  cross-language attribute names.
- Shared semantic state/classes follow the native/ARIA, generated state, or
  closed-effect hierarchy.
- Generated interactive controls use mount-local relationships, unique ids, one
  generic adapter, and browser tests that prove event-time submitted values
  converge to authoritative server state.
- Surface scopes, fragments, resources, action/intent fields, and global wire
  cases have no feature-facing open constructors.
- Checked runtime/generator code performs no semantic redispatch on reflected
  names.
- Surface Lab and its production route/registry output are gone; only unregistered
  test fixtures remain.
- The retained week overview complies but remains disabled.
- No compatibility shims or legacy DOM names remain.
- Living docs describe the implemented interfaces, and the full repository gate
  passes.
