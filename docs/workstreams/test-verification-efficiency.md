# Test Verification Efficiency

Status: active

GitHub issues:

- [#124](https://github.com/BeaudanBrown/ihp-roster/issues/124) - parent epic
- [#125](https://github.com/BeaudanBrown/ihp-roster/issues/125) - reproducible baseline and coverage inventory
- [#126](https://github.com/BeaudanBrown/ihp-roster/issues/126) - Hspec fixture construction
- [#127](https://github.com/BeaudanBrown/ihp-roster/issues/127) - Hspec execution lanes
- [#128](https://github.com/BeaudanBrown/ihp-roster/issues/128) and [#129](https://github.com/BeaudanBrown/ihp-roster/issues/129) - database-isolation prototype and implementation
- [#130](https://github.com/BeaudanBrown/ihp-roster/issues/130) - GHC compilation reuse
- [#131](https://github.com/BeaudanBrown/ihp-roster/issues/131), [#132](https://github.com/BeaudanBrown/ihp-roster/issues/132), [#133](https://github.com/BeaudanBrown/ihp-roster/issues/133), and [#134](https://github.com/BeaudanBrown/ihp-roster/issues/134) - E2E audit, isolation, layering, and concurrency
- [#135](https://github.com/BeaudanBrown/ihp-roster/issues/135) - tooling, CI, documentation, and closeout

Living docs to update:

- `Test/AGENTS.md`
- `e2e/AGENTS.md`
- `README.md`
- `docs/workstreams/maintenance.md`

## Goal

Reduce median same-host wall time for the complete Hspec and Playwright gates by
about 30% without changing application behavior or weakening behavioral
coverage. `bash ./bin/in-env hspec-test` and `bash ./bin/in-env e2e` remain the
complete canonical gates. Faster focused lanes are additive.

## Baseline Protocol

The initial baseline was captured at commit `2c08eb78c002` on 2026-07-11 on an
8-core x86_64 Linux host with 39.1 GiB RAM. Each complete gate received one
warm-up followed by three measured runs. All measured runs passed without
retries or failures. Wall time is measured around the repository wrapper; test
execution time comes from Hspec or Playwright's reporter. The difference is
fixed compilation, database, process startup, and report overhead.

Use the same protocol for closeout: same host, default shard settings, one
warm-up, three successful measured runs, and median wall time. Report retries
and failures separately instead of including a failed run in the median.

| Gate | Coverage per run | Measured wall seconds | Median | Dominant execution path | Fixed/setup evidence |
| --- | ---: | --- | ---: | --- | --- |
| Full Hspec, 8 shards | 938 examples | 184.125, 181.461, 176.861 | **181.461s** | `DevSeed`, 168-175s; `AdminController`, 159-169s; roster shard, 153-161s | median wall minus slowest shard **8.411s** |
| Full E2E, 2 shards | 176 project-tests | 351.979, 308.979, 310.152 | **310.152s** | both shards balanced at 4.8-5.5m | wall minus reported browser duration **20.979-22.152s** |
| Focused pure Hspec (`FrontendContract`) | 10 examples | 6.349, 6.277, 6.455 | **6.349s** | median Hspec execution **0.059s** | median compile/DB/runner overhead **6.290s** |
| Focused DB Hspec (`SessionsController`) | 16 examples | 12.964, 12.993, 12.859 | **12.964s** | median Hspec execution **6.489s** | median compile/DB/runner overhead **6.475s** |
| Focused E2E (`homepage.spec.ts`) | 3 tests | 50.438, 50.110, 49.478 | **50.110s** | median Playwright execution **5.4s** | dev server/DB/report overhead **44.710s** |

A compiled-server single-shard trace of the focused E2E selection took 26.806s:
5.4s was Playwright execution, GHC relinking was warm and sub-second, and the
remaining approximately 21s was primarily database reset/schema setup, server
readiness, seed setup, report generation, and cleanup. These child processes do
not emit phase timestamps, so the aggregate is trustworthy but narrower phase
figures are bounds rather than exact values.

## Coverage Inventory

The Hspec registry in `Test/Suite.hs` contains 57 named suites and the complete
run reports 938 examples. The source tree contains 65 `*Spec.hs` modules because
some registered suites aggregate split modules. At baseline there are 596
`withCleanDb` call sites and heavy repeated builder use: 525 `createUserRecord`,
476 `createVenueWithConfig`, 466 `createVenueMembershipRecord`, and 261
`createStaffRecord` references. The registry label and example description are
the stable identities to cite when an assertion is consolidated or moved.

The default Playwright inventory is 176 project-tests across 43 files:

| Project | Tests | Behavioral role |
| --- | ---: | --- |
| `desktop-chromium` | 116 | auth, onboarding, admin, roster workflows, exports, live fragments, venue scope, Xero, and responsive desktop contracts |
| `mobile-chromium` | 20 | 10 general mobile experience plus 10 roster-mobile contracts |
| `galaxy-s9-plus` | 20 | the same 20 contracts at the narrow Android baseline |
| `tablet-chromium` | 20 | the same 20 contracts at the tablet baseline |

`roster-mobile-screenshots.spec.ts` is opt-in and is not part of the 176-test
canonical default. The exact baseline can be regenerated without starting the
app:

```bash
bash ./bin/in-env node ./node_modules/@playwright/test/cli.js test --list --reporter=list
```

When tests are consolidated or moved to another layer, the implementing issue
must identify the old suite/file and example title, the replacement suite/file
and title, and whether project multiplication changed. This keeps coverage
accountable even when raw example counts fall.

## Current Hspec Lanes

Issue #127 split the two large aggregate registrations into independently
shardable child suites and classified the resulting 63 registry entries. The
20 pure suites contain 238 examples and run through `hspec-pure` without a
PostgreSQL reset or connection. The 43 database suites contain the remaining
700 examples and run through `hspec-db` with the same per-shard database
isolation as the canonical command. The canonical all lane remains 938 examples.

The shared `AdminController`, `RosterWeeksController`, and `Xero` description
prefixes intentionally remain broad Hspec match terms across the split suites.
Automatic DB-backed fan-out is capped at eight unless `TEST_SHARDS` explicitly
overrides it. On the baseline host, an all-lane six-shard run took 211.516s
versus 186.329s for the comparable eight-shard run; the six-shard critical path
was balancing-limited rather than uniformly database-saturated.

Issue #126 replaced repeated test-user hashing with one fixed valid fixture hash;
real password verification remains covered by Sessions and runtime hash creation
remains covered by Users controller tests. Nine read-only default DevSeed
examples were consolidated into one example that constructs the expensive
fixture once while retaining every assertion; the scenario-override behavior
remains independently isolated. The DevSeed median Hspec time fell from
168-175s to 17.689s. The complete suite now reports 930 examples, and its first
post-change full run passed in 85.343s wall time, 53.0% below the 181.461s
baseline median.

## Initial Bottlenecks And Interventions

1. `DevSeed` alone controls full Hspec wall time despite having only 10 examples.
2. `AdminController` and the roster controller shard are the next Hspec critical
   paths; broad per-example cleaning and repeated venue/auth builders dominate
   their setup shape.
3. A focused pure Hspec run spends about 99% of wall time outside its assertions,
   showing the value of a true pure lane and compilation reuse.
4. Full E2E shards are balanced, so increasing shard count before isolating data,
   auth, and MailHog would trade correctness risk for limited benefit.
5. Focused E2E startup costs about 45s for 5.4s of browser work in dev-server
   mode. Reusable compiled startup and auth state are high-value interventions.
6. The mobile contracts are intentionally executed on three device projects;
   later audit must distinguish genuine cross-device behavior from assertions
   that can be proven once at a faster layer.

## Intended Contract

- Canonical commands remain complete and conservative.
- Pure and focused feedback commands do not silently omit required full-gate
  coverage.
- Every parallel Hspec or E2E worker owns isolated mutable state.
- Dedicated auth and passkey browser tests continue to exercise real browser
  authentication.
- Server/controller/contract assertions move out of Playwright only when the
  replacement is explicit and the remaining browser test still protects the
  user-visible integration boundary.

## Exit Criteria

- Same-host median full Hspec and E2E wall times improve by approximately 30%,
  or measured evidence records the residual critical path and correctness cost
  of further reduction.
- Complete Hspec and E2E gates pass with no unexplained coverage loss.
- Fast-feedback commands and isolation rules are documented in the nearest
  living agent guides.
- Durable implementation facts are moved to living docs and this workstream is
  archived.
