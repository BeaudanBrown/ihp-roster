# Operation-Local Frontend Contract Evidence Rollout

GitHub issue: `#347`

Affected living contracts:
`Application/Helper/FrontendContract/README.md`,
`Application/Helper/FrontendContract/Surface/README.md`

## Unresolved Intent

Roll out ADR 0006 from the Roster Action reference seam to every remaining
Action and Intent family. A caller that needs one request operation must not
carry or reduce its owning complete `SurfaceSpec`.

## Rollout Constraints

Each generated request declaration receives a kind-specific nominal operation
token. Action and Intent tokens remain distinct when their declaration markers
match. The caller-visible families expose only compact owner, canonical marker,
and one operation's ordered field specs. Builders, named presence witnesses,
metadata, exact parsers, read-only lookup, and serialization all use that same
token and opaque bundle.

Production facades continue to expose named operations. They do not expose token
constructors, evidence constructors, raw field bundles, re-indexing functions,
or APIs accepting protocol names and fields as strings. Migrated signatures and
implementations may not retain `SurfaceActionFields`, `SurfaceIntentFields`,
`SurfaceActionFieldSpecs`, `SurfaceIntentFieldSpecs`, full-Surface reflection, or
generic request parsing.

Term request evidence is generated from canonical checked IR. Generated
TypeScript continues to render from the same IR and must remain byte-identical
unless an explicit contract change is separately approved. No handwritten
operation metadata, field inventory, or compatibility seam may become a second
authority.

Each migrated Surface/request kind retains one verification-only aggregate
proof. The proof checks canonical declaration and generated-token set equality,
compact ownership, canonical markers, and exact ordered presence/wire specs. It
is typechecked with the complete staged generated set before publication but is
never managed application source, installed into `app-lib`, imported by a
facade, or rooted as runtime code.

The mandatory all-kind generator remains failure-atomic. One inventory decision
owns home and operation eligibility; rollout must not add a parallel home,
request, or proof registry. Existing typed exclusions and their reasons remain
intact.

## Guarantee Matrix

`Config/nix/frontend-operation-evidence-matrix.tsv` maps every registered
compile-failure fixture to its guarantee, current seam, full-rollout seam, and
pilot-equivalent provenance. `frontend-surface-compile-fail-check` rejects
missing, duplicate, stale, or malformed rows.

#347 must move every row marked `operation-local-action`,
`operation-local-intent`, or `operation-kind` without weakening its intended
failure. Required classes remain:

- nominal owner and operation identity;
- exact field marker, order, presence, recursive wire, and closed domain;
- opaque bundles with no raw rebinding;
- Action/Intent lane separation;
- matching builder, presence witness, metadata, parser, and TypeScript IR;
- private whole-Surface completeness.

Diagnostics must name the compact owner/operation, affected marker, and expected
local shape without printing an expanded `Surface ...` primitive list.

## Evidence Boundary

Authoritative baseline and Roster reference evidence:

- `Config/nix/baselines/production-build/staging-ea144503-grill.json`
- `Config/nix/baselines/production-build/issue-346-operation-local-roster.json`

Each rollout slice must run focused generator/Hspec/compile-failure checks before
migration expands. Final rollout evidence must include generated drift,
TypeScript parity, source guardrails, exact request-facade closures, focused E2E,
and a matched production profile.

New measurements use the same builder, GHC/Nix configuration, cores, configure
flags, and derivation identity reporting. The final state must keep each
installed interface at or below 16 MiB unless an explicit reviewed exception is
recorded, reduce complete interface/app-lib cost consistently, and admit no
private proof into the installed module set.

## Migration And Rollback Boundary

Migrate one atomic generated/facade/caller slice at a time. A migrated family has
only the operation-local seam; do not retain a whole-Surface compatibility path.
Non-migrated families may keep the old seam only within #347.

Stop and revert the active slice if a compile guarantee weakens, generated
TypeScript drifts unexpectedly, caller closure acquires registry/generator/proof
modules, an interface misses budget, or production memory/wall evidence regresses
without an explained and approved tradeoff. No schema, customer data, routes, or
browser protocol should change as part of this rollout.

## Reconciliation

Delete this workstream after #347. Move final authoring and verification rules
into `Application/Helper/FrontendContract/Surface/README.md`; retain ADR 0006 as
rationale and the bounded profile JSON as measurement evidence. GitHub remains
the status tracker.
