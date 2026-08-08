# ADR 0007: Explicit Production Haskell Package Boundary

Date: 2026-08-08

## Context

The production package previously inherited every registered Haskell package,
compiled development-only sources, changed hashes for test-only edits, and
emitted both static and shared app-library ways. That broad implicit boundary
made clean builds larger and allowed unrelated development growth to affect
production without review.

Build memory is useful diagnostic evidence, but sampled RSS, daemon-cgroup
memory, service load, file cache, and swap vary by builder and run. A stable
release policy therefore cannot use a machine-global reading as if it were an
app-owned artifact.

## Decision

Production Haskell packaging is closed over reviewed executable and script
roots. Generated inventories own the reachable module closure and map its
external imports to reviewed direct Cabal packages. The production source seam
excludes tests while retaining runtime modules, schema, migrations, static
assets, and deployment inputs. Development-only generators use a separate
frontend-contract tooling package and cannot become production-reachable.

Build the app library static-only. Packaged executables must not retain or
load the app library dynamically. Stable regression gates enforce installed
output size, interface limits, artifact kinds and counts, and reviewed
module/package/executable inventories. Profiling retains clean-build RSS,
cgroup, swap, timing, and builder context as comparative evidence; those
machine observations neither cap GHC nor block a release.

All boundaries fail closed. A new source, import, package, executable, artifact
kind, or generated-tool dependency requires an explicit ownership decision
rather than inheriting ambient availability.

## Consequences

Production changes receive smaller, reviewable invalidation and dependency
boundaries. Test and tooling changes remain usable in development without
silently widening production. Static-only output avoids duplicate interfaces
and an unused shared library, while runtime packaging remains independently
smoke-tested.

Inventory maintenance and pinned-IHP source transformations are additional
build-system responsibilities. Machine-memory regressions require comparable
profiling and diagnosis rather than a single portable threshold; deterministic
artifact and inventory growth remains blocking.

## Alternatives Considered

- Keep IHP's ambient source/package discovery: rejected because development and
  transitive availability would remain production declaration authority.
- Maintain handwritten Cabal and module lists independently: rejected because
  they would drift from reachable imports and deployment consumers.
- Enforce a NAS RSS ceiling: rejected because the sampled metric is
  builder-global, variable, and not an app-owned output.
- Keep shared app-library output for symmetry with development: rejected
  because packaged production executables do not consume it.

## Links

- Tickets: GitHub #339, #341–#344, #348–#351
- Living docs: `Config/nix/README.md`,
  `docs/runbooks/production-build-profiling.md`
- Related typed-authority decision:
  `docs/adr/0006-operation-local-frontend-contract-evidence.md`
