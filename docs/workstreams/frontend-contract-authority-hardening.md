# FrontendContract Authority Hardening

Status: active

GitHub issues:

- `#136` - Make FrontendContract the executable runtime authority and retire stale runtime code
- Contract authority: `#161`-`#166`
- Haskell adapter ergonomics: `#180`-`#192`
- Shared browser capabilities: `#167`-`#173`
- Passkey browser capabilities: `#210`-`#211`
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

13. `#169` - Reliable toggle submission/presentation and timesheet break controls, including the active roster live-status regression. **Complete.**
14. `#167` - Time picker roles and exact configuration payload, consuming but not duplicating the toggle/break boundary. **Complete.**
15. `#168` - Dialog/toast overlay DOM vocabulary. **Complete.**
16. `#170` - Ordered-range shift preferences. **Complete.**
17. `#171` - Horizontal drag/snap scrolling.
18. `#172` - PWA installation adapter. **Complete.**
19. `#173` - Xero candidate filtering adapter. **Complete.**

### Passkey browser capabilities

- `#210` - Passkey DOM roles and exact tagged flow configuration. **Complete.**
- `#211` - Exact passkey server/browser begin, credential, finish, recovery, and
  error DTOs. This follows the DOM/configuration slice and retains native
  WebAuthn conversion in the handwritten adapter. **Complete.**

### Roster browser capabilities

20. `#174` - Surface-owned linked-highlight roles and stale interaction class cleanup. **Complete.**
21. `#175` - Staff-panel sorting/tabs and browser-reachable Surface DTOs. **Complete.**
22. `#176` - Fullscreen and column-edit controls. **Complete.**
23. `#177` - Image-export annotations and configuration. **Complete.**
24. `#178` - Retained dormant week overview. **Complete.**

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
Shared browser slices depend on typed schema builders. #169 added the global
Toggle contract, declaration-checked scalar/list mapping builders, exact browser
config parser, and one form-local generic adapter. Active consumers now separate
presentation from submitted target state, roster live submission is synchronized
before HTMX serialization, timesheet break controls use a native fieldset, and
responsive week toolbars render canonical controls once. Focused Haskell,
TypeScript, compile-failure, and desktop/mobile browser coverage pins those
boundaries. #168 moved dialog/toast lane ids, roles, auto-submit state, loading
labels, and auto-hide configuration into the focused global Overlay contract.
Shared Haskell render helpers now serialize exact config records; dialog, toast,
and passkey TypeScript consume generated vocabulary, keep transient state out of
the DOM, and retain Bootstrap/native/ARIA behavior inside the adapters. Typed
AppShell/Surface request helpers and the separate picker lane remain unchanged.
Focused render, parser, browser-lifecycle, source-guard, CSS, and drift coverage
pins the migration. #167 added the global TimePicker contract, exact field and
option parsers, declaration-indexed Haskell serializers, and generated modal,
field, value, trigger, label, step, options, option, and clear identities. The
generic adapter now rearranges validated server-rendered option nodes with no
range/value/label/copy fallbacks, rejects malformed fields locally without DOM
replacement, and consumes native disabled state without querying Toggle roles.
Focused render, compile-failure, parser, browser, CSS, contract-drift, and source
guards pin that ownership split. Ordered ranges also depend on toggle
presentation. `#167` owns picker internals whereas `#169` owns toggle submission
and break-region activation. #170 added the global OrderedRange contract, exact
configuration/state parsers, generated root/start/end/availability roles,
position properties, and the closed `clamp-other-endpoint` policy. Profile and
staff rendering now supplies the complete allowed range, step, defaults, label
inventory, initial values, and native accessibility relationships. The generic
adapter validates each local subtree before mutation, keeps initialization state
outside the DOM, and leaves Toggle transport plus server endpoint validation in
their existing authoritative owners. Focused render, semantic validation,
compile-failure, TypeScript, real-browser, CSS, drift, and source guards pin the
slice. #171 added the global HorizontalScroll contract with generated snap/drag
roles and exact nearest-item/equal-group/ignore configuration. Roster and
Timesheets now render the focused runtime attrs, while the generic adapter owns
one controller per mounted scroller, cleans replacement subtrees, and keeps
thresholds, scheduling, click suppression, and transient classes browser-local.
Focused render, parser, pointer/snap browser, CSS, drift, and source guards pin
that boundary. #172 added the global `PwaInstallContract` with generated
page/button/result/installed roles and a closed accepted/dismissed/failed result
state. The public install view now renders every workflow message and native
status/live-region semantics, while the adapter retains prompt events, prompt
objects, display-mode/Apple detection, and `hidden` visibility mechanics. Focused
view/runtime, generated-state, browser outcome/accessibility, CSS, drift, and
source guards pin the boundary and keep platform objects out of wire schemas.
#173 added the global `XeroCandidateFilterContract` with generated root, search,
candidate, config, and filtered-empty roles plus an exact candidate config parser.
Imported-pay-item rendering now selects and normalizes name/account-code
projection fields in Haskell while retaining checkbox identity, validation, and
mutations on the server. The root-local adapter validates the complete boundary,
reports structured diagnostics, then performs only generic query normalization,
fuzzy matching, and native visibility updates; focused render, TypeScript,
single-worker browser, CSS, drift, compile-failure, and source guards pin that
boundary. #210 added the global `PasskeyContract` with generated login,
registration, setup-prompt, action, device-name, status, recovery, and dismissal
roles plus one exact tagged local flow configuration. Session, step-up,
setup-link, setup-dialog, management, and roster prompt views now render typed
Haskell routes, status relationships, closed prompt mode, and workflow/status/
recovery copy. The generic adapter validates each nearest flow root, reports
structured diagnostics without changing malformed HTML, never displays native
exception or untyped response copy, and retains native WebAuthn/base64url/
local-storage mechanics. The generated Overlay semantic dismissal event records
close-control, Escape, and backdrop hints while Overlay alone owns prompt removal
and body locking. The legacy `.js-passkey-*`, scalar URL/status/user/
mode datasets, global status-id lookup, and raw prompt literals are deleted and
guarded. #211 added exact registration/authentication begin records, serialized
credential request records, tagged finish outcomes, and tagged structured
errors to that same contract. Schema-indexed Haskell carriers now bridge the
WebAuthn library without controller field literals, while generated TypeScript
parsers reject malformed server envelopes before native credential calls or
redirects and generated encoders own outbound requests. Native credentials,
responses, navigator calls, extension-result semantics, and base64url conversion
remain in the focused TypeScript adapter; handwritten/open DTOs, casts, fallback
probing, and compatibility error parsing are deleted and guarded. #174 added
checked Surface `BrowserRole`, `BrowserState`, and
`LinkedHighlight` declarations with closed hover/focus/keyboard/pin activations
and matching-source/member/ordered-bounds effects. Roster staff and shift-group
markup now renders generated role attributes with opaque membership/order keys;
the contained day timeline owns a separate shift-group declaration. One generic,
mount-local TypeScript runtime consumes the generated registry, owns transient
`is-linked-highlight-*` classes and pin accessibility state, and reconciles
server-rendered replacements. The old roster-specific runtime, raw staff/slot
attributes, feature highlight selectors, and misleading create-dropzone class
are deleted; focused Haskell/TypeScript/browser coverage, CSS migration, drift,
and source guards pin the boundary. #175 added explicit browser reachability to
Surface DTO declarations and generated only the selected type/guard/parser/
encoder directions. It also added checked `CompleteSetSort` and `TabSet`
capabilities with marker-indexed Haskell rendering helpers and generic,
mount-local runtimes. The roster staff panel now emits one exact typed row
payload plus generated sort/tab roles; name/role/shifts comparator chains,
defaults, tie-breakers, tab keys, and tab default come only from the Roster
Surface declaration. The old global sort enum, per-field data attributes, and
roster-specific parser/comparator/tab modules are deleted; focused reflection,
compile-failure, Haskell render, TypeScript lifecycle, E2E, drift, and source
guards pin the boundary. #176 added Surface-owned closed browser states and the
roster fullscreen root/toggle/label plus column editor/start/done roles. The
curated Haskell chrome renderer supplies initial collapsed/inactive state; the
two mount-local adapters consume generated attributes, value objects, unions,
and guards while retaining icon/focus/Escape and delayed-blur mechanics. HTMX
replacement reconciliation and timer cleanup are covered, and the raw roster
fullscreen/column contracts are deleted across views, CSS, tests, and source
guards. #177 added generated image-export trigger/config/projection/row/cell
roles, a closed JPG format, and exact Haskell policy/cell payloads. The curated
renderer now resolves filename, dimensions, quality, copy, errors, and export
text, while the mount-local adapter retains only measurement, computed styles,
SVG/Canvas encoding, and download mechanics. The trigger is emitted only beside
the supported row-grid projection; day-column and timeline layouts no longer
expose an unusable export action. Raw export/conflict annotations, filename
discovery, and feature-class/cell-position inference are deleted and guarded;
focused render, parser, browser-download, CSS, and drift coverage pin the
boundary. #178 migrated the retained disabled week overview to generated
panel/day/detail-slot roles, exact panel/day payloads, native `aria-pressed`, and
closed availability/closure/calendar state. The adapter rejects malformed days
locally with structured diagnostics and owns no fallback display copy or route.
The active header still renders the static week label, so no normal-page mount,
fetch, or navigation behavior was re-enabled; raw datasets, the handwritten
parser, and shared semantic classes are deleted and guarded.
Roster linked highlighting depends on closed interaction IR. The
browser-reachable Surface DTO path established by staff-panel work now carries
image-export and week-overview payloads. The Haskell adapter slices run in parallel
with capability slices and final reconciliation depends on every preceding
slice.

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
