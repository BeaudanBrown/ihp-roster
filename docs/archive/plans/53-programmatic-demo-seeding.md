# Pipeline 53 — Programmatic Demo Seeding

Read after `IMPLEMENTATION_PLAN.md`, `docs/archive/plans/49-roster-groups-and-venue-bootstrap.md`, and `docs/archive/plans/45-payroll-report-exports.md`.

## Goal

Replace the current one-off manual dev seed with a scenario-driven, deterministic seed system that can generate realistic demo environments for client presentations, manual QA, and targeted exploratory testing.

The first success bar is practical rather than abstract: by `2026-04-10`, the app should be able to load a believable staffed venue with realistic roster density, role mix, pay settings, leave/timesheet activity, and support/bootstrap state without hand-editing fixture code for each demo.

## Why This Exists

The repo already has useful but fragmented seed surfaces:

- `Application/Fixtures.sql` provides minimal bootstrap state and must stay safe for fresh database initialization
- `Application/Support/DevFixtures.hs` builds a richer development environment, but it is one hard-coded scenario
- `Application/Support/PayrollFixtures.hs` provides deterministic payroll-focused fixtures
- `e2e/fixtures/seed.sql` provides a fixed, stable browser-test dataset

That is enough for development, but not enough for repeatable demos where the operator needs to control:

- how many users/staff exist
- how many managers versus workers exist
- which roster groups exist and how busy they look
- pay rates, pay levels, and shift types
- how full the roster appears
- whether the surface emphasizes payroll, leave conflicts, support access, or ordinary weekly operations

The main design constraint is that realism must not come from ad hoc SQL strings alone. The project already has Haskell helpers that enforce venue bootstrap and payroll setup invariants; the new seed system should build on those helpers instead of duplicating business logic in raw SQL.

## Current Constraints

- `Application/Fixtures.sql` is also used by deployment/bootstrap paths, so it must remain minimal and conservative.
- `e2e/fixtures/seed.sql` must stay deterministic and stable; dynamic scenarios must not silently change browser-test assumptions.
- Venue bootstrap and roster defaults already converge on shared helpers. The new seed system must keep using that path rather than reintroducing direct table-by-table venue setup.
- For demos and exploratory QA, determinism matters as much as realism. The same named scenario and RNG seed must reproduce the same environment.

## Settled Direction

- keep `Application/Fixtures.sql` as bootstrap-only SQL
- move manual/dev richness into a scenario-driven Haskell seed planner
- generate a concrete in-memory seed plan first, then apply it
- keep the planner deterministic by explicit RNG seed
- allow named scenarios plus CLI overrides
- support SQL rendering from the same concrete plan as a secondary output, not as the primary source of truth
- keep the existing fixed e2e SQL seed separate from the demo/manual seed path

## User-Facing Outcomes

The operator should be able to do things like:

- seed one realistic cafe venue with `18` staff, `2` managers, mixed FOH/BOH groups, and a mostly-filled current week
- seed a busier venue with heavier payroll/timekeeping data for export demos
- seed a conflict-heavy week with leave overlaps and underfilled slots for roster management demos
- keep using one command for manual setup instead of editing Haskell source each time

Representative command shapes:

```bash
bash ./bin/in-env seed-dev --scenario realistic-demo
bash ./bin/in-env seed-dev --scenario realistic-demo --users 18 --seed 20260410
bash ./bin/in-env seed-dev --scenario payroll-heavy --emit-sql build/demo-seed.sql
```

Exact flag names may change during implementation, but the model should support named scenarios, deterministic seeds, and selective overrides.

## Architecture

Split the seed system into four layers.

### 1. Scenario definition

A user-facing configuration record describing intent, not tables:

- venue count
- total users and/or staff counts
- role counts or ratios
- roster-group definitions
- slot template definitions per roster group
- pay-level and shift-type presets
- current-week activity levels
- leave/timesheet/invitation probabilities
- target fill density for rosters
- deterministic RNG seed

Recommended module boundary:

- `Application/Support/Seed/Scenario.hs`

### 2. Seed planning

Expand a scenario plus RNG seed into a concrete `SeedPlan` containing fully decided entities and assignments:

- venue names
- users and staff personas
- venue memberships and platform roles
- roster-group applicability
- pay levels, shift types, and day rules
- roster weeks/days/slots
- leave requests
- timesheet entries and approval states
- invitation/bootstrap artifacts

This layer owns pseudo-randomness, weighting, and realism heuristics. It should not write to the database directly.

Recommended module boundary:

- `Application/Support/Seed/Planner.hs`

### 3. Seed execution

Apply a `SeedPlan` through the existing helper layer and project invariants:

- venue creation via shared bootstrap helpers
- memberships/staff through `Application.Support`
- payroll snapshots through `Application.Support.PayrollFixtures`
- roster-group applicability through `Application.Helper.RosterGroups`

This layer should be thin. It translates the plan into DB records while reusing existing safe creation flows.

Recommended module boundary:

- `Application/Support/Seed/Executor.hs`

### 4. SQL rendering

Render a concrete `SeedPlan` into SQL for inspection, sharing, or loading elsewhere. This is useful for demo reproducibility and debugging, but it should derive from the plan, not bypass it.

Recommended module boundary:

- `Application/Support/Seed/Sql.hs`

## Data Model Direction

### Scenario record

The first scenario record should support both coarse and fine control:

- exact counts where the operator cares about totals
- ratios/probabilities where realism is more important than exact identity
- optional named presets for pay and roster templates

Recommended shape:

- `scenarioName`
- `seedValue`
- `venueSpec`
- `staffingSpec`
- `rosterSpec`
- `payrollSpec`
- `activitySpec`
- `outputSpec`

### Named scenarios

Ship with a small set of built-in named scenarios:

- `realistic-demo`
- `busy-roster`
- `payroll-heavy`
- `conflict-heavy`

The first milestone only needs one or two scenarios if the override model is solid. The important part is that the current hard-coded dev seed becomes one named scenario rather than remaining embedded in source.

## Roster Realism Model

The roster should look intentionally busy rather than mechanically full.

### Inputs

- roster groups with slot templates
- eligible staff per roster group
- ideal shifts per week per staff member
- role suitability such as manager-capable versus ordinary worker
- fill-density target per day/group
- optional conflict probabilities

### Assignment heuristics

Use weighted deterministic selection instead of fully uniform randomness.

Candidate score should consider:

- staff eligibility for the roster group
- whether the staff member is already on leave that day
- whether the staff member already holds another slot in the same day/group
- how far the staff member is from their target weekly shift count
- role suitability for the slot or day
- recent assignment density to avoid one person appearing everywhere

### Intentional imperfection

The demo environment should not look unnaturally perfect.

Allow controlled probabilities for:

- some empty slots
- a few shift-note abbreviations
- some leave-driven gaps
- some pending versus approved timesheets
- a small number of cross-group staff assignments where eligibility allows it

## Demo-Ready Scenario Requirements

The minimum demo slice should prioritize one convincing operator workflow over complete generality.

### Minimum scenario: `realistic-demo`

It should generate:

- one active venue for ordinary manager/worker demo flows
- founder support access into that venue
- two roster groups such as front of house and back of house
- approximately `12` to `20` staff with a believable manager/worker mix
- a current-week roster that is mostly, but not completely, filled
- some leave requests in mixed states
- some approved and pending timesheets
- usable pay levels and shift types
- one payroll-capable venue surface or embedded payroll data suitable for export/admin walkthroughs
- one pending invitation or bootstrap artifact to show admin setup state

This scenario should be the default recommendation for tomorrow's client demo.

### Optional second scenario: `payroll-heavy`

If time permits, include a second scenario focused on denser approved timesheets and multiple pay levels so the export/admin surface looks richer during a payroll-focused demonstration.

## CLI Direction

Evolve `seed-dev` from a single-purpose script into a scenario runner.

The command should support:

- target database selection, preserving current `app` / `app_test` behavior
- named scenario selection
- deterministic seed override
- count overrides such as total users or staff
- optional SQL emission path
- optional dry-run/summary mode

Recommended examples:

```bash
bash ./bin/in-env seed-dev --scenario realistic-demo
bash ./bin/in-env seed-dev --scenario realistic-demo --seed 20260410
bash ./bin/in-env seed-dev --scenario realistic-demo --staff-count 18 --manager-count 2
bash ./bin/in-env seed-dev --scenario realistic-demo --emit-sql build/realistic-demo.sql
```

The script should still print the important credentials and seeded venue summary so a human can immediately log in and drive the demo.

## Implementation Order

### Slice 53.1 — Scenario extraction

Refactor the current `seedDevelopmentFixtureForWeek` logic so the current hard-coded demo seed becomes an explicit built-in scenario instead of being embedded directly in one long function.

Primary touchpoints:

- `Application/Support/DevFixtures.hs`
- `Application/Script/SeedDev.hs`

### Slice 53.2 — Planner and deterministic randomness

Introduce scenario and plan types plus a deterministic planner that can vary counts, roles, and roster assignments without losing reproducibility.

Primary touchpoints:

- `Application/Support/Seed/Scenario.hs`
- `Application/Support/Seed/Planner.hs`

### Slice 53.3 — Executor integration

Apply planned entities through existing support helpers and keep bootstrap/payroll setup centralized.

Primary touchpoints:

- `Application/Support/Seed/Executor.hs`
- `Application/Support.hs`
- `Application/Support/PayrollFixtures.hs`

### Slice 53.4 — CLI and operator ergonomics

Add scenario flags, override flags, and readable output to the `seed-dev` script and wrapper.

Primary touchpoints:

- `Application/Script/SeedDev.hs`
- `flake.nix`
- `justfile`

### Slice 53.5 — SQL emission

Add optional SQL rendering from the concrete `SeedPlan`.

This slice is useful, but it is not required before tomorrow's demo if direct DB seeding lands first.

### Slice 53.6 — Verification

Add planner/executor tests that prove determinism, count control, and invariant preservation.

Primary touchpoints:

- `Test/DevSeedSpec.hs`
- new `Test/Support/Seed*` helpers as needed

## Verification Strategy

Add tests at three levels.

### Planner-level determinism

Prove that the same scenario plus seed produces the same plan every time.

### Executor-level invariants

Prove that generated seeds still satisfy:

- venue bootstrap defaults exist
- roster groups and slot names are present
- staff assignments respect roster-group eligibility
- pay fixtures produce valid snapshots
- role counts and activity counts match the requested shape

### Manual smoke output

The CLI should print a concise human summary including:

- seeded venue names
- important login emails
- default password
- roster-group names
- counts of staff, leave requests, approved timesheets, and pending timesheets

## Non-Goals

- replacing the fixed e2e SQL fixture with dynamic runtime generation
- changing deployment/bootstrap semantics of `Application/Fixtures.sql`
- building a full public data-import system
- optimizing for arbitrarily large synthetic datasets before the demo/manual-QA path is solid

## Acceptance Checks

Done when:

1. `seed-dev` can generate at least one realistic named demo scenario without editing source code
2. the same scenario and seed reproduce the same environment
3. the demo seed reuses existing venue bootstrap and payroll helper paths instead of duplicating domain logic in ad hoc SQL
4. the operator can vary staff counts, role mix, and roster density through supported scenario inputs or overrides
5. the generated environment includes enough realistic roster, leave, timesheet, and auth/support state to drive a client demo credibly
6. optional SQL rendering exists or is clearly staged as the next slice without blocking the direct demo seed path
