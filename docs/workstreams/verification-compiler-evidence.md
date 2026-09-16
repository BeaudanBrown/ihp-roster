# Reusable compiler verification evidence

Proposed design for [#578](https://github.com/BeaudanBrown/ihp-roster/issues/578),
within [epic #576](https://github.com/BeaudanBrown/ihp-roster/issues/576).
[#580](https://github.com/BeaudanBrown/ihp-roster/issues/580) owns the eventual
cross-pipeline ranking; runtime orchestration remains with
[#579](https://github.com/BeaudanBrown/ihp-roster/issues/579).
These are recommendations, not implemented caches or permission to skip gates.

## Evidence and confidence

The [baseline](../archive/verification-performance-baseline-2026-09-16.md)
provides serial stage boundaries on a contended host. #578 retains the bounded
follow-up probe results and failures; raw diagnostic artifacts remain under
`.pi/tmp/verify-profile/issue-578/`. No controlled before/after pipeline
improvement has been measured. Existing compiler fixtures validate today's
semantics, not a future cache or parallel scheduler.

The critical isolation constraint is that a fresh private output directory
alone is insufficient: GHC must still resolve every dependency interface.
Private copies of a prepared graph are a candidate, but require complete
inventory and serial/parallel equivalence tests before adoption.

## Candidate boundaries and benefit bounds

### Strict warning success, before parallelism

The owner is `Config/nix/scripts/haskell/application-warnings`; option/build
preparation is in `Config/nix/scripts/lib/ghc.sh`. Keep the dependency pass and
strict one-shot subject semantics on a miss. `ghc-options.sha256` describes
compiler options, is written before compilation, and cannot certify success.
Warning flags alone do not force already-built subjects. Multi-subject forced
`-c` can produce duplicate instances; forced `--make` can grant generated code
warning authority. Neither is an acceptable shortcut.

Start with a conservative whole-input successful-evidence key. An exact hit
could avoid most of the observed 376–403s stage, minus generation, inventory,
input-hashing and evidence-validation costs. This is an upper opportunity bound,
not a demonstrated saving; “seconds” for an unchanged run remains a hypothesis.
A relevant edit initially invalidates the entire certificate. Source-closure
or per-subject certificates should follow only after proving dependency and
Template Haskell invalidation. Repeated package/interface loading and TH work
are plausible components of one-shot cost; no allocation/TH breakdown was
measured, so do not attribute all 376s to compiler process startup.

For changed runs, consider a two-worker experiment only after a successful
serial baseline using frozen input snapshots. Each worker needs a private
interface/object/temp tree (copy/reflink, never writable hardlinks), preserving
one subject per session. The probe validates only serial private copies, not
parallel equivalence across the full inventory. Bound the dependency build
separately: inherited options contain bare `-j`, so worker count alone is not a
CPU budget. Begin with two workers, explicit one-capability/one-job limits and
a combined 4 GiB experiment ceiling with headroom; abort without evidence on
resource exhaustion. Those are conservative experiment limits, not measured
production defaults. Measure per-worker and aggregate peak memory before
raising them. Two workers can at best halve the parallelizable portion, not
the whole stage, and may lose to memory/I/O contention. Serial execution remains
the fallback, with no weaker warnings.

### Stable generated proof inputs, without skipping proofs

`frontend/surface-adapters-check` adds a fresh `mktemp` directory to GHC options;
`ihp_roster_prepare_verification_cache` hashes that string. Every new path
invalidates its persistent dependency cache. The same helper hashes contents
of every tracked file, so a prose edit also invalidates adapter and
`frontend/surface-compile-fail-check` caches. Generated and untracked inputs
are not fully represented. This is not proof of an existing false pass: both
owners still submit all selected subjects to GHC on every call.

Prefer a workspace-scoped, locked, content-addressed generated/proof tree with
stable logical module paths. Identity must cover generator binary/source,
formatter, generated module/proof contents, flags, compiler/package closure and
dependencies. Do not simply strip random paths out of the key: GHC's own source
path/interface semantics must agree. Generate into staging, format, validate
all managed modules/private proofs, check missing/stale/extra managed outputs,
then compare/publish atomically. Negative fixtures retain the complete default
selection and per-fixture expected/rejected diagnostics; their batching already
amortizes GHC startup. An expected compile failure alone is not a passed gate.

The warm focused frontend command was 128.61 recorder seconds. Its validation
marker was 23.49s and the negative-fixture marker 79.42s: about 55.93s contains
adapter validation and intervening work. That interval is an upper bound on
this cache opportunity, not time all removable; freshness generation, formatting,
comparison and proof checking remain. Full's 117.95s tooling-package stage
mixes build/evaluation/generation/validation and is not additive to the focused
frontend total. Stable paths are a high-confidence defect finding; realized
speedup and GHC recompilation behavior need the complete adapter/proof tests.

Generation manifests in `frontend/generated-state-lib` and
`haskell/generated-state-lib` are existing freshness optimizations, not strict
compiler certificates. Preserve their locks. Hash actual generated outputs for
proof identity rather than trusting HEAD, tracked files, or the schema marker
alone. Multiple code-generation/build graphs have distinct flags and authority;
do not share writable interfaces between typecheck, warnings, generator builds
and Weeder merely because their source sets overlap.

### Reuse Weeder analysis, not stale HIE

`haskell/weeder-check` owns the complete app/test/script/generated sweep, stale
HIE deletion, canonical policy and baseline. `scripts/weeder-reachability.py`
owns the five advisory comparisons. The baseline full stage was 251.19s;
follow-up retained-HIE analysis took 63.42s total. These observations have
different compilation/cache/host state: subtracting them does not yield a
measured compiler cost or saving.

Keep the complete GHC sweep and exact source/HIE inventory checks. Consider
caching analysis after a completed sweep when HIE bytes, source bytes, policy,
root ownership, baseline, tool versions and analysis implementation all match.
Keep canonical result and advisory provenance distinct. A canonical hit cannot
certify an advisory whose inventory/policy changed, nor can advisory success
replace the blocking baseline gate. The measured advisory opportunity is at
most about 53s per matched retained-HIE observation, minus validation overhead;
caching canonical analysis might avoid another 11s. No blanket roots, omitted
modules or stale baseline entries are proposed.

Reports must remain unavailable after failed capture/interrupted analysis;
unchanged bytes may reuse analysis, but revision/dirty/capture metadata must
accurately describe current validated inputs rather than relabel old success.
Input changes during capture, compile or analysis must fail closed. Preserve
`unused-types=false`, narrow reason-bearing roots and category/unknown caveats.

### Executable reuse and Nix boundaries

`e2e/e2e` already reuses the object/interface graph but puts app, worker and
Stripe-mock binaries under a new run-state directory, provoking relinking.
Baseline focused E2E reached completed linking at 22.67s/17.93s; these include
wrapper/preparation time, not isolated linker cost. Reuse only content-identified
immutable binaries, copied/reflinked into private run state; never share running
processes, ports, database fixtures or mutable executable outputs. #579 owns
measuring link-only versus startup/reset/test costs and validating runtime
isolation. Do not promise that the entire 30s focused command disappears.

Nix already has explicit production/tooling source filters and separate schema
identity; see `Config/nix/README.md` and ADR 0007. Prefer the existing package
handoff in `verify-full` rather than rebuilding generators in later stages.
Two matching derivation evaluations per package show 2.6–2.9s evaluation cost,
not hundreds of seconds. The baseline's two remote SSH failures, substitution
and local build work were not separately timed. Do not treat the whole 251.37s
production stage as cacheable evaluation overhead or silently disable builders.
No further build was needed to investigate this boundary.

A future content-aware closure-diff workflow could make intentional production
growth easier to review, but must retain explicit package/executable ownership,
tooling exclusion, artifact kinds/byte ceilings and smoke authority required by
ADR 0007. Exact count policy changes need their own approval; a stale count does
not imply a broken binary, nor does a smoke pass justify unreviewed closure
growth. Specific reconciliation findings belong to #578, not this design.

## Successful-evidence protocol to prove

A future implementation must distinguish disposable dependency caches from
successful verification certificates. Recommended common requirements:

- Key a versioned manifest by purpose, exact subject paths and content,
  inventory/classification, generated/untracked dependency contents, deletions,
  compiler executable/platform, package DB/unit IDs and dependency closure,
  effective flags, include/CPP/plugin inputs, relevant environment, scripts and
  warning/root/fixture policy. GHC's numeric version alone is insufficient.
- Include schema/generator/formatter inputs and TH `addDependentFile` inputs.
  Audit TH file/environment reads; if the closure cannot be proven, disable
  reuse for that case. A Git diff hash is provenance, not a cache identity.
- Generate/resolve dependencies before capturing identity. Freeze the input
  snapshot for the producer or hold the appropriate generation/build locks;
  recheck identity before atomic publication. Before/after checks alone cannot
  exclude transient change-and-restore races in a mutable tree.
- Use workspace/purpose/key-scoped ownership and locks. Acquire once, recheck
  after waiting, never run simultaneous `bin/in-env` wrappers. Existing cache
  helper `flock` protects its purpose root; options-only build preparation has
  no such lock. Do not assume every current compiler owner is concurrency-safe.
- Publish one immutable, complete certificate only after every required subject
  passes, with output hashes and diagnostic provenance. Precompile stamps,
  partial files, kills, failures and resource aborts publish no success. Preserve
  unrelated immutable successful keys without presenting them as current.
- Readers validate completeness and identity under the same protocol. Missing,
  corrupt or schema-incompatible evidence means recompute, not success. Keep
  explicit cache-miss reasons and lock timing to distinguish useful reuse from
  hidden serialization. Runtime test outcomes never inherit static certificates.

## Acceptance experiments for a future implementation

| Boundary | Required regression experiment |
|---|---|
| Strict authority | Existing real-GHC warning fixtures cold and warm; instance imports, partial selectors/dot/update/patterns, unused imports and generated exclusions |
| Source closure | Change subject, transitive dependency, generated/untracked input, schema, inventory add/delete/rename and TH-dependent file; every affected result invalidates |
| Environment | Same GHC version with different package DB/compiler build, flags, plugins, policy or generator; no stale hit |
| Stable paths | Same generated bytes in fresh temp locations preserve semantic cache identity; changed proof bytes miss and unsafe proof fails |
| Negative authority | All registered fixtures still run or have complete valid evidence; unexpected success/wrong diagnostic/missing attribution fails |
| Publication | Kill at generation/compile/analysis/publish boundaries, corrupt/delete output or certificate, edit during capture; no false success |
| Concurrency | Two same-key callers serialize/recheck; different keys isolate all writable paths; serial/parallel full-inventory diagnostics agree |
| Weeder | Complete inventory and fresh sweep; added/deleted module/HIE, changed root/baseline, interrupted advisory and conservative category provenance fixtures |
| Runtime/package | Immutable executable identity changes with linked inputs; disposable services unchanged; source filters, budgets and all packaged smoke checks retained |
| Performance | At least three matched successful runs per state, quiet host, command-only timing, per-process/aggregate memory, hit/miss/lock reasons; report all failures |

A failed optimization must fall back to the original complete owner, not a
reduced gate. Implementation acceptance must also rerun affected canonical
verification; these bounded investigation probes are not substitutes.

Living-document owners if implemented: `Config/nix/README.md` for compiler and
package contracts, `docs/runbooks/performance-profiling.md` for measurement,
and `e2e/README.md` for executable/runtime isolation. Retire this workstream
when unresolved design has moved to those owners or a superseding decision.
