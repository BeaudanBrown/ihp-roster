# Verification performance baseline — 2026-09-16

This evidence supports [epic #576](https://github.com/BeaudanBrown/ihp-roster/issues/576)
and baseline issue [#577](https://github.com/BeaudanBrown/ihp-roster/issues/577).
Use the protocol in `docs/runbooks/performance-profiling.md` for comparisons.
The baseline exists to support the compiler/tooling investigation in #578 and
the runtime/orchestration investigation in #579; it is not a verification gate
or an implementation plan.

## Provenance and method

Measurements used revision
`f7ea54ebccf4d73c65ef53ff3d8baded58af0653`. Both the tracked binary diff
and NUL-delimited untracked-name list had SHA-256
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` for
every observation. The dedicated epic worktree was
`/home/beau/documents/projects/ihp-roster-verification-profiling`, epic 576,
slot 1. Commands entered through that worktree's `bin/in-env`, serially.

The host had 12 logical CPUs and 62.7 GiB RAM and ran Linux 6.18.40. Tooling was
GHC 9.10.3, Node 22.22.3, and Nix 2.34.7. Existing workspace, Nix, package, and
OS caches were retained unless a row says output-cold. Output-cold means a new
empty command-owned build directory; package, Nix, and OS caches remained warm.
No shared cache was deleted.

A diagnostic recorder timestamped command output, sampled `/proc` every two
seconds, and retained command metadata, child resource usage, host load and PSI.
Child CPU excludes work performed by the Nix daemon and pre-existing services;
selected host processes in samples are contention context, not command
attribution. Raw local evidence is under `.pi/tmp/verify-profile/current/`.
Those paths are intentionally not remote evidence or committed artifacts.

Each row below retains the recorder's UTC start, exact argument vector, and exit
status. Workspace identity was epic 576, slot 1 for every row.

| Observation | UTC start | Exact argv | Exit |
|---|---|---|---:|
| 01 | 2026-09-16 03:43:45Z | `bash ./bin/in-env verify-fast` | 0 |
| 02 | 2026-09-16 03:58:49Z | `bash ./bin/in-env verify-full` | 1 |
| 03 | 2026-09-16 04:19:27Z | `bash ./bin/in-env verify-fast` | 0 |
| 04 | 2026-09-16 04:29:08Z | `bash ./bin/in-env true` | 0 |
| 05 | 2026-09-16 04:29:11Z | `bash ./bin/in-env true` | 0 |
| 06 | 2026-09-16 04:29:14Z | `bash ./bin/in-env true` | 0 |
| 07 | 2026-09-16 04:29:17Z | `bash ./bin/in-env typecheck` | 0 |
| 08 | 2026-09-16 04:29:25Z | `bash ./bin/in-env hspec-pure --match WageSourcePolicy` | 0 |
| 09 | 2026-09-16 04:29:31Z | `bash ./bin/in-env hspec-pure --match WageSourcePolicy` | 0 |
| 10 | 2026-09-16 04:29:37Z | `bash ./bin/in-env frontend-check` | 0 |
| 11 | 2026-09-16 04:33:27Z | `bash ./bin/in-env frontend-check` | 0 |
| 12 | 2026-09-16 04:35:44Z | `bash ./bin/in-env e2e e2e/auth.spec.ts` | 0 |
| 13 | 2026-09-16 04:36:19Z | `bash ./bin/in-env e2e e2e/auth.spec.ts` | 0 |
| 14 | 2026-09-16 04:37:07Z | `bash ./bin/in-env env TYPECHECK_BUILD_DIR=/home/beau/documents/projects/ihp-roster-verification-profiling/.pi/tmp/verify-profile/cold/typecheck typecheck` | 0 |
| 15 | 2026-09-16 04:38:55Z | `bash ./bin/in-env env TYPECHECK_BUILD_DIR=/home/beau/documents/projects/ihp-roster-verification-profiling/.pi/tmp/verify-profile/cold/typecheck typecheck` | 0 |

## End-to-end observations

| Command and cache state | Result | Wall | Child CPU | Peak child RSS |
|---|---:|---:|---:|---:|
| `verify-fast`, first retained-cache observation | pass | 898.54s | 2,487.92s | 7,541 MiB |
| `verify-full`, retained caches after fast | fail | 1,230.03s | 2,297.21s | 9,852 MiB |
| `verify-fast`, immediate warm repeat | pass | 571.80s | 1,067.70s | 1,628 MiB |

The first fast run regenerated generated Haskell types and compiled a broad
working-tree graph. The immediate repeat is the useful no-change warm
observation; it was still 9m32s.

### Fast stage boundaries

| Stage | First observation | Warm repeat |
|---|---:|---:|
| Script freshness | 0.15s | 0.15s |
| HTTP policy | 0.66s | 0.73s |
| Migration enum policy | 0.08s | 0.08s |
| Typecheck | 100.46s | 6.14s |
| Owned application warnings | 515.88s | 375.87s |
| Typed error boundaries | 35.70s | 32.20s |
| Pure Hspec | 77.64s | 14.67s |
| Fast Playwright | 165.24s | 139.00s |

Both fast runs preserved the same selection: 743 pure Hspec examples with zero
failures, then 251 Playwright tests across eight isolated shards with no
reported retries, flakes, or skips. Fast remains additive feedback, not merge or
release authority.

### Full stage boundaries and stopping point

`verify-full` passed its inventory preflight at 585 production modules and then
reached the optimized production inspection stage:

| Stage in canonical order | Result | Wall |
|---|---:|---:|
| Script freshness | pass | 0.14s |
| Production manifest | pass | 0.16s |
| IHP integration | pass | 4.46s |
| HTTP policy | pass | 0.90s |
| Migration enum policy | pass | 0.09s |
| Typed-contract authority | pass | 0.45s |
| Wage authority | pass | 0.05s |
| Date-native authority | pass | 0.11s |
| Date-native readiness | pass | 1.23s |
| Documentation authority | pass | 0.39s |
| GHCi bootstrap | pass | 0.53s |
| Typecheck | pass | 6.95s |
| Owned application warnings | pass | 402.68s |
| Typed error boundaries | pass | 33.95s |
| Complete Hspec | pass | 46.48s |
| Weeder and reachability evidence | pass | 251.19s |
| Frontend-contract tooling package | pass | 117.95s |
| Frontend-contract warnings | pass | 55.23s |
| Generated frontend, TypeScript, browser unit and negative checks | pass | 47.74s |
| CSS authority | pass | 2.26s |
| Architecture authority | pass | 2.69s |
| Optimized production package and inspection | fail | 251.37s |

Complete Hspec passed 2,129 examples across six shards; shard execution ranged
30.83–43.20s. The frontend section passed 126 browser-unit tests and all 65
registered negative compilation fixtures. Production package smoke passed all
10 packaged executables.

The run then failed the production build budget: app-library modules were 576
against budget 574, `.hi` artifacts were 576 against 574, and production rows
were 585 against 583. This revalidates that the `f7ea54eb` inventory correction
fixed the earlier missing-module preflight/build failure; a separate budget
prerequisite remains. The run therefore did **not** reach billing contracts,
deployment modules, or complete Playwright. It is an honest end-to-end failed
pipeline observation, not complete `verify-full` evidence. The remote Nix
builder also failed SSH connection twice, at recorder times 765.96s and
990.22s. No start marker exposes either SSH-attempt duration, so isolated
builder/network wait is unavailable rather than inferred. Nix continued with
cache substitution and local building; the tooling and production stage totals
include those effects. No verification-cache lock wait was reported.

## Focused observations

CPU is aggregate descendant user plus system time; RSS is the maximum reported
for a descendant. As above, neither includes pre-existing service or Nix-daemon
work.

| Observation | Cache definition | Wall | Child CPU | Peak child RSS |
|---|---|---:|---:|---:|
| Environment entry 1 | immediate repeat | 2.80s | 2.91s | 73 MiB |
| Environment entry 2 | immediate repeat | 2.80s | 2.92s | 73 MiB |
| Environment entry 3 | immediate repeat | 2.83s | 2.95s | 73 MiB |
| Warm typecheck | retained output | 8.91s | 15.32s | 687 MiB |
| Focused Hspec 1 | retained output | 5.70s | 10.76s | 829 MiB |
| Focused Hspec 2 | immediate repeat | 5.84s | 10.89s | 853 MiB |
| Frontend check 1 | retained caches | 227.95s | 692.21s | 3,186 MiB |
| Frontend check 2 | immediate repeat | 128.61s | 382.57s | 3,183 MiB |
| Focused E2E 1 | retained caches | 34.98s | 42.46s | 1,628 MiB |
| Focused E2E 2 | immediate repeat | 30.21s | 81.93s | 1,629 MiB |
| Isolated typecheck | output-cold | 107.21s | 518.49s | 8,120 MiB |
| Isolated typecheck | immediate repeat | 8.73s | 536.71s | 8,120 MiB |

The recorder's descendant counters for the second isolated typecheck include
inherited child accounting from the preceding cold command, so its CPU/RSS
values are conservative upper bounds; its wall time is valid. The output-cold
run compiled 1,201 subjects from 7.66s to 105.68s without deleting shared state;
the immediate repeat emitted no compilation rows. Warm retained typecheck
completed generated/inventory checks by 3.10s and returned at 8.91s. Focused
Hspec spent about 2.8s after environment entry preparing the executable, then
ran 13 examples in 0.01s.

Frontend run 1 compiled its reflected generator by 34.15s, reached managed
adapter/proof typechecking at 96.60s, began 65 negative fixtures at 141.16s, and
finished 126 browser-unit tests at 227.72s. The repeat reached the same markers
at 12.88s, 23.49s, 79.42s, and 128.53s. Focused browser runs linked the app,
worker, and Stripe mock by 22.67s/17.93s, completed setup by 28.02s/22.91s, and
then passed five desktop tests in 5.5s/5.8s in one shard with no reported retry,
flake, or skip. No focused command reported a cache-lock, network, or builder
wait.

Focused host context was also contended: sampled busy CPU / I/O wait averaged
30%/22% for warm typecheck, 29–36%/19–22% for focused Hspec, 77–79%/6% for
frontend, 36–48%/14–20% for E2E, and 26–64%/12–24% for isolated typecheck.
Environment-entry runs were too short for a two-second delta; load-one was
7.2–7.6.

## Contention and interpretation

This was not a quiet-host benchmark. Across the three pipeline runs, sampled
host busy CPU averaged approximately 32–53%, sampled I/O wait averaged 8–16%,
load-one peaked between 16 and 25, and I/O PSI `some avg10` reached 56–67%.
Focused frontend runs averaged about 77–79% host busy CPU. These are host-wide
observations and include unrelated work. No verification-cache lock wait was
reported. Nix substitution, failed remote-builder connection, local daemon
build work, and filesystem waits cannot be reconstructed from child CPU alone.
Do not add aggregate parallel CPU seconds and present them as removable wall
seconds.

The evidence is sufficient to identify investigation owners and establish
command/cache semantics, but not to set regression budgets. It has only one
full observation, two fast observations, and two observations of selected
focused commands. It has no destructive machine-cold run, controlled network or
remote-builder state, quiet-host median/tail distribution, or complete current
full-browser handoff. Two-second process sampling can miss short processes.
Future remediation acceptance should use at least three matched successful runs
per state on a quiet host and report median, tail, and peak memory.

## Coverage and handoff limitation

The focused observations and successful fast runs were diagnostic/additive
only. This particular full run stopped before billing, deployment and complete
Playwright, so it supplied no successful complete-gate result or later browser
handoff evidence.
