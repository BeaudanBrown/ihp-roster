# Runtime verification iteration

Proposed design for [#579](https://github.com/BeaudanBrown/ihp-roster/issues/579)
under [epic #576](https://github.com/BeaudanBrown/ihp-roster/issues/576).
[#580](https://github.com/BeaudanBrown/ihp-roster/issues/580) owns cross-pipeline
ranking; compiler reuse is covered by
[the compiler workstream](verification-compiler-evidence.md).
These options are not implemented. Measurements, benefit bounds, interruptions
and current status belong to #579; local artifacts remain under
`.pi/tmp/verify-profile/issue-579/`.

## Ranked design options

### 1. Prove optional-presence completion instead of timing absence

For `e2e/support/session.ts`, establish that the response/shell owning the prompt
and necessary mount work are complete before inspecting optional presence.
Use the rendering authority in `Web/View/RosterWeeks/Show.hs` to define that
boundary. An unchecked immediate count is not a substitute for completion.
Keep present-prompt dismissal and mandatory authentication as separate outcomes;
an unexpected navigation/mount error must not masquerade as ordinary absence.

For `e2e/support/passkeys.ts`, replace generic network quiescence only with a
proven registration/session outcome. Do not weaken the acknowledgement/resync
contract owned by `e2e/support/runtime.ts` to make either optimization appear
faster. Test absent/optional/mandatory prompts, delayed rendering, restored and
stale cookies, logout, registration/recovery and impersonation. Confidence in
the delay diagnosis is high; safe replacement semantics still need proof.

### 2. Schedule duration-weighted isolated groups

Consider whole file/project groups before splitting browser files. Assignment
must account for hooks, cached sessions, serial suites and mutable fixture
ownership—not merely test durations. Retrospective greedy allocation provides
an optimistic hypothesis, not a benchmark: grouping overhead and cache locality
change when assignments move. Compare exact test/project identity sets before
and after, including retry and device-selection policy from `e2e/AGENTS.md`.

Refresh Hspec weights at their owner, `Test/Suite.hs`, rather than reordering
source lists. Represent external calculator cost explicitly without changing
its required tier membership. Splitting a heavy suite needs independent cleanup
and unchanged invariant ownership; new weights alone cannot parallelize it.
Rebalance after wait removal, rather than adding overlapping hypothetical gains.

### 3. Reuse immutable executables, not runtime state

Apply the compiler workstream's identity/publication protocol to executable
reuse at `Config/nix/scripts/e2e/e2e`. Copy/reflink validated outputs into private
run paths; avoid writable hardlinks and replacement of executing binaries.
Keep this opportunity distinct from runtime lifecycle changes governed by
`e2e/AGENTS.md` and the managed runtime owners.

Before selecting a reuse or sequencing change, capture launch-to-ready/failure
intervals individually for MailHog, Stripe mock, app, worker and browser/shard
launch. Capture linker completion independently: a “Linking” message marks a
start, not completion. Report overlapping intervals as critical-path and
aggregate measurements separately. Unknown launch boundaries remain unknown,
not inferred from a later readiness message. Verify owner-scoped cleanup after
startup failure, interrupted setup and successful report publication.

### 4. Batch calculator lifecycles with document isolation

Explore a batch protocol around
`Config/nix/scripts/payroll-workbook/libreoffice-recalculate.py`, retaining one
private office/profile while closing each document before the next. Preserve
one genuine cold-start compatibility check and the formula/save/reopen authority
in `Test/PayrollWorkbookSpec.hs`; no cached values or library-only substitute.

Bound both document and total batch duration so restarting a per-document timer
cannot create an unbounded run. Preserve watchdog and outer timeout escalation
through failure and cleanup. Test invalid documents, wrong formulas/values,
save/reopen corruption, connection failure, hangs and failure between documents.
A failed document fails the gate even when cleanup succeeds. Contamination and
hang risks make batching lower priority than deterministic optional UI waits.

### 5. Experiment with rollback only at a proven connection seam

For reset changes, follow `Test/AGENTS.md` and preserve the authority of
`Application/Fixture/Reset.hs`. Committed-visibility metadata is necessary but
insufficient to authorize rollback: prove that every operation uses the
bracketed connection and no worker, listener, pooled controller or other process
needs committed state. Account explicitly for sequences, DDL and external side
effects. Otherwise retain canonical reset.

Measure DB template creation/clone, per-example reset and disposal independently.
A cheap creation path does not imply cheap teardown when connections remain.
Require fixture-manifest and adversarial cross-example/venue leakage tests;
no production durability changes belong to this optimization.

### 6. Remove redundant sequencing before parallelizing orchestration

Prefer compatible focused-filter batching and reuse of proven static handoffs.
A later explicit DAG must keep runtime results fresh, respect the compiler
workstream's writer/lock boundaries, and preserve fast/full authority distinctions
from the local test guides. Do not treat wrapper entry as dominant without
command-only measurements or optimize it by concurrent wrapper entry.

## Acceptance and integration points

Use matched before/after runs with identical revision class, tier, project,
shard membership, cache definition and host state. Report command elapsed time,
slowest shard, aggregate test/phase time, resource pressure and all failures,
retries and flakes. Per-process launch/readiness and DB evidence must distinguish
linking, setup, test and cleanup. Publish missing attribution explicitly.
A resumed interrupted run is a new observation, not an immediate warm repeat.
Calculator tracing overhead and sparse timing boundaries must remain explicit.

Retain existing complete authorities plus the adversarial cases above. Validate
suite metadata, exact browser membership and managed cleanup. A failed
optimization falls back to the original complete owner; diagnostic probes do
not establish production acceptance. Implementation requires separately approved
work, not changes hidden inside this investigation.

Affected living documents if implemented: `e2e/AGENTS.md`, `Test/AGENTS.md`,
`Config/nix/README.md` and `docs/runbooks/performance-profiling.md`. Retire this
workstream when those owners or a superseding decision absorb the unresolved
design; GitHub remains the findings and work-selection authority.
