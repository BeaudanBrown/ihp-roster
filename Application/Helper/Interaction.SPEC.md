# Typed Interaction Surface Specification

This is the durable contract between typed `FrontendSurface` declarations,
Haskell views/controllers, live updates, generated browser contracts, and the
generic TypeScript interaction runtime.

## Authority And Vocabulary

Server-rendered HTML is authoritative. Haskell owns Surface/scope/mount identity,
server layers, fragments and containment, disposable layers, generated refs,
intents and exact fields, HTMX form metadata, and conflict policy. TypeScript
consumes generated contracts and owns generic browser mechanics only.

- **Mount**: one Surface/scope occurrence with a mount key.
- **Server layer**: authoritative Haskell-rendered business DOM.
- **Fragment**: replaceable server-owned target with an authorized GET route.
- **Disposable layer/session**: temporary local UI/state safe to clear.
- **Intent**: typed committed user action submitted through a server-rendered
  form.
- **Conflict policy**: typed decision to apply, defer, or cancel when a fragment
  changes during a disposable session.

See `Application/Helper/FrontendContract/Surface/README.md` for declaration and
adapter seams. Generated contract IR, registries, helpers, and tests—not this
file—own current inventories and implementation detail.

## DOM And Meaning Ownership

TypeScript may read generated refs from server DOM and mutate only declared
disposable layers or adapter-local/native state. It must not persistently mutate
business DOM, parse opaque keys into domain meaning, construct mutation URLs,
invent `data-bepis-*` names, or infer behavior from text/classes/position.

Intent forms are ordinary Haskell-rendered HTML/HTMX. Mount JSON is not mutation
transport. The browser bridge finds the matching form inside the same mount,
validates generated field metadata, fills only declared fields, refuses missing
required/unknown fields, and dispatches the generated trigger. Controllers parse,
authorize, and validate every field as untrusted input.

Focused global capabilities (overlay, toggle, picker, ordered range, horizontal
scroll, SidePanel, passkey, PWA install, filters) own reusable exact contracts
only. SidePanel owns nearest-root visibility, ARIA/icon/focus/Escape mechanics,
and replacement reconciliation; features own panel content and authorization.
Haskell owns values, routes, workflow/error copy, and server validation; adapters
keep browser/platform mechanics local and leave malformed boundaries untouched.
Capabilities compose through generated roles/native state rather than importing
one another's feature meaning.

Concrete mount keys participate in IDs, targets, layer/form IDs, and runtime
lookup. All discovery stays within the nearest owning mount and must not cross a
nested Surface. Reconciliation from an inner HTMX replacement still resolves its
actual owner.

## Sessions, Effects, And Commit

The default lifecycle is local until commit:

1. start establishes typed session/anchor state
2. preview mutates disposable UI only
3. cancel clears all local state
4. commit submits exactly one generated intent form

Pointer and activation refs carry generated static identities plus dynamic opaque
keys. Shared DSL aliases define common drag/drop shapes. Modifier variants are
semantic, Haskell-declared intents/effects; TypeScript maps platform keys to those
variants but does not send raw modifier state as business authority.

Effects come from the closed semantic interaction IR. Session-global and
contextual-target effects must clean up on commit, cancel, Escape,
`pointercancel`, timeout, HTMX cleanup, and runtime stop. Unknown effects fail at
contract/check time; runtime switches over generated closed unions use
`assertNever`.

Use standard HTMX forms, triggers, sync/disabled controls, and lifecycle events.
Do not add feature fetch persistence, custom mutation transports, extensions, or
custom elements without a separate typed contract and demonstrated reusable
need.

## Live Coordination

Disposable sessions publish mount/session lifecycle. Live updates consult the
Haskell-owned conflict policy for the same concrete mount. Non-conflicting swaps
may apply; conflicting swaps apply, defer latest-per-target, or cancel/refetch as
declared. Deferred fragments refetch immediately after session end. A bounded
timeout is only a watchdog; missing/ambiguous policy prefers cancel and fresh
server state.

Actor success and passive invalidation share typed semantic fragment keys.
Successful migrated mutations refresh authoritative server fragments and clear
local disposable state; validation failures rerender their submitted form/dialog
directly. Interaction code does not become a second live-update or DOM-diff
owner.

## Server Validation

Intent fields are browser strings, never trusted domain values. Controllers use
required checks and total parsers, then validate venue/scope membership, record
ownership, ordering/time constraints, conflicts, and permissions. `fill` alone
is insufficient for required request-derived fields. Browser affordances and
opaque keys do not authorize a mutation.

## Extension And Verification

Add interaction behavior at the Surface DSL/helper seam, generate contracts,
consume only generated refs/registries in generic TypeScript, and add tests at
the narrowest authority. Do not add raw feature attributes/forms or historical
compatibility protocols.

```bash
bash ./bin/in-env frontend-contracts-check
bash ./bin/in-env frontend-surface-compile-fail-check
bash ./bin/in-env frontend-surface-guardrails
bash ./bin/in-env frontend-check
bash ./bin/in-env hspec-test --match "FrontendSurface" --match "RosterInteractionWorkflow"
bash ./bin/in-env ./bin/doc-drift-check
```

Use focused Playwright only when real pointer/keyboard/HTMX/live behavior changes.
