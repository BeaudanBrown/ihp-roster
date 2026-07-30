# Architecture-Conformance and Derivation Audit

Architecture drift occurs when locally plausible code stops following the
repository's intended ownership, derivation, and dependency flows. This pass
looks for places where one canonical declaration should drive many consumers,
but hand-maintained copies or bypasses can diverge.

Current code and living local documentation outrank this checklist. Revalidate
all project-specific examples each audit.

## Build a source-of-truth map

Create one row for every important closed-world concept or cross-layer contract:

| Concept | Canonical declaration/DSL | Derived/generated consumers | Intentional independent oracle | Manual copies/bypasses | Drift detection | Finding |
|---|---|---|---|---|---|---|
| Example | path + symbol | paths/artifacts | test or external spec | paths/literals | compiler/generator/check/none | F-NN or none |

Also record:

- owner module and interface;
- extension procedure when a new case is added;
- whether projection is exhaustive;
- whether generated files clearly identify ownership;
- whether the drift check is semantic or merely textual.

## Project-specific source flows to verify

These are scan prompts, not substitutes for current local docs:

- `Application/Schema.sql` is the fresh-schema/model source; generated Haskell
  types must agree, while deployed upgrades still require explicit preserving
  migrations.
- Controller actions originate in `Web/Types.hs`, route through `Web/Routes.hs`
  and `Web/FrontController.hs`, and should be referenced through typed routing
  rather than copied URL strings.
- Haskell owns canonical frontend wire/surface contracts; generated TypeScript
  under `frontend/ts/generated/` and checked-in `static/app*.js` projections
  should follow the documented generator path.
- Surface, disposable-layer, intent, intent-field, conflict-policy, live-resource,
  and data-attribute values should come from their canonical contract/DSL where
  the subsystem has adopted it.
- Server-rendered HTML remains authoritative for live surfaces; actor fragment
  responses and passive invalidation/refetch paths should use the established
  helpers.
- Venue authority comes from venue memberships; platform support authority is a
  separate role and request mode.
- URL query construction, CSV encoding, overlay lanes, and similar cross-cutting
  behavior have owning helpers rather than per-caller string assembly.
- Authenticated navigation policy has one intended owner even when views/tests
  independently verify its externally visible result.
- App stylesheet links and build/audit manifests may be intentionally mirrored;
  where architecture requires a mirror, enforce agreement rather than blindly
  deleting one side.

Read at least root `AGENTS.md`, relevant local `AGENTS.md`/`SPEC.md`,
`Application/Helper/FrontendContract/Surface/README.md`, and
`Application/Helper/Interaction.SPEC.md` before filing frontend-contract drift.

## Drift patterns

### Parallel closed sets

The same enum/role/status/action/intent/field list is manually repeated in
Haskell, TypeScript, tests, SQL, or scripts. Adding a constructor does not force
all projections to update.

Ask whether consumers can derive from:

- an ADT with exhaustive pattern matching;
- schema/reflection metadata;
- a typed DSL/intermediate representation;
- one declarative registry;
- a generator with a checked-in freshness gate.

Do not derive external compatibility expectations from internal code when their
independence is what detects a breaking change.

### Stringly typed seams

Closed concepts cross a seam as arbitrary `Text`/strings, generic UUIDs,
booleans, tuple positions, CSS selectors, JSON keys, or data attributes despite
an established typed owner. Look for smart constructors, domain IDs, sum types,
records, and generated wire codecs that can narrow the interface without
changing serialization.

A string at the final wire/DOM/SQL seam is normal. The smell is that arbitrary
strings remain exposed to internal callers.

### DSL erosion and escape hatches

A DSL/helper exists, but callers reconstruct its behavior manually. Determine
whether:

- the caller is wrong;
- the DSL interface is too shallow or awkward;
- a required capability is missing;
- migration is partial and documented;
- the low-level escape is intentional and tested.

Repeated escape hatches often justify deepening the owning module rather than
adding another wrapper.

### Non-exhaustive projection

Mappings use defaults, wildcard branches, hand-maintained case lists, or partial
lookups so new domain cases silently receive old behavior. Prefer compile-time
exhaustiveness or a generator/check that fails with the missing case.

Do not remove a deliberate forward-compatibility fallback without treating that
as a behavior decision.

### Generated/manual ownership ambiguity

Generated artifacts lack headers, freshness checks, deterministic generation,
or clear source pointers; authored files copy generated declarations; agents can
edit both sides. Fix ownership and verification, not merely file placement.

### Duplicated policy

Authorization, visibility, validation, venue scope, ordering, live invalidation,
or error normalization is reimplemented in controllers, views, frontend, and
tests. Find the domain owner. Keep independent tests of outcomes while removing
production policy copies.

### Architecture tests coupled to text

Tests grep files for strings, count declarations, or assert long source snippets.
Classify each:

- true lexical policy (forbidden import, generated header): text/AST checks may
  be correct;
- structural contract (every action has a wrapper): derive from architecture
  facts/reflection/AST;
- runtime behavior (auth, route, DOM, serialization): exercise the interface;
- exact compatibility/migration requirement: narrow literal checks may be the
  independent oracle.

Replace only when the new check catches the same forbidden drift without
becoming tautological.

### Test cases hard-coded beside a DSL

Tests repeat constructor lists, field names, or expected artifact inventories.
Prefer:

1. derive the **case universe** from the canonical type/DSL;
2. independently assert invariants for every case;
3. keep explicit expected values only where external semantics require them;
4. add an exhaustiveness check so a new case cannot be silently skipped.

Never compute expected behavior with the production interpreter being tested.

## Enforcement ladder

Choose the strongest low-noise mechanism at the owning seam:

1. type system and exhaustive pattern matching;
2. one canonical declarative registry/DSL;
3. deterministic generated artifact plus freshness check;
4. reflection/schema/AST-based structural check;
5. contract or property test through the interface;
6. focused runtime/integration test;
7. textual check only for genuinely lexical requirements.

A periodic audit should promote repeated objective findings upward this ladder.
Subjective judgments—cohesion, naming, seam depth—remain review prompts rather
than hard CI gates.

## Questions for every proposed derivation

- Is there exactly one legitimate owner?
- Does derivation reduce knowledge callers must carry?
- Will adding a new case fail loudly in all necessary projections?
- Is the generated path deterministic and understandable to agents?
- Does the proposal preserve an independent acceptance oracle?
- Does it create a deep module, or just another pass-through layer?
- Can the change be characterized and merged without changing wire, database,
  route, rendering, auth, ordering, or error behavior?
