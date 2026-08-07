# ADR 0006: Operation-Local Frontend Contract Evidence

Status: accepted

Date: 2026-08-07

## Context

Generated Action and Intent interfaces currently index fields, metadata, and
parsers by a complete `SurfaceSpec`. A caller needs one nominal operation, but
GHC must expose and reduce the owning Surface's promoted primitive list. This
contributes large installed interfaces and production-build memory pressure.

The compile-time authority established by ADRs 0002 and 0003 remains mandatory.
A smaller interface cannot move ownership, exact fields and wire types, closed
values, TypeScript parity, or whole-Surface completeness to runtime checks.

## Decision

Use generated, kind-specific nominal operation tokens as the request seam.
Action and Intent tokens remain distinct even when their declaration marker is
the same. Operation-indexed evidence exposes only the compact Surface owner and
one operation's ordered fields; it never exposes the complete `SurfaceSpec`.
Generated builders, metadata, parsers, lookup, and diagnostics share that token.
Callers receive named operations and opaque bundles, not constructors or raw
names.

Generate term-level request metadata from the canonical checked IR. Generate a
private aggregate proof that canonical declarations and operation tokens have
equal sets, ownership, and field specs. Blocking generated-code verification
typechecks this proof outside installed `app-lib`; feature callers cannot import
it. TypeScript continues to render from the same checked IR.

Prefer shared operation-indexed bundle representations. Concrete generated
records are the fallback only when measurement shows the chosen interface still
exceeds budget; they remain generated from the same IR and satisfy the same
private proof.

## Consequences

Caller interfaces no longer contain or reduce a complete promoted Surface.
Unrelated operation changes should not alter another operation's evidence.
Operation identity stays nominal, while existing declaration-directed missing,
extra, order, presence, wire, and closed-domain diagnostics apply to one local
field list.

The generator gains private operation-token, evidence, metadata, and proof
machinery. This additional implementation complexity makes the module deeper:
callers learn less while retaining compile-time authority.

## Alternatives Considered

- Keep complete `SurfaceSpec` indices and rely on compiler optimisation:
  rejected because measured interfaces and build memory are already excessive.
- Generate one concrete record per operation: strong caller interface, but more
  per-record declarations and instances; retained as the measured fallback.
- Validate only in checked IR or at runtime: rejected because misuse would stop
  failing at compile time.
- Handwrite operation evidence: rejected as dual authority.

## Links

- Tickets: GitHub #339, #345–#347
- Living docs: `Application/Helper/FrontendContract/README.md`,
  `Application/Helper/FrontendContract/Surface/README.md`
- Matched rollout evidence:
  `Config/nix/baselines/production-build/issue-347-operation-local-all-requests.json`
- Sources: `Application/Helper/FrontendContract/Surface/Values.hs`,
  `Application/Helper/FrontendContract/Surface/Request.hs`,
  `Application/Helper/FrontendContract/Surface/HaskellAdapter/Request.hs`
