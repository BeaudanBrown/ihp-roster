# Pipeline 49 — Roster Groups and Venue Bootstrap Defaults

Read after `IMPLEMENTATION_PLAN.md` and `plans/20-roster-and-conflicts.md`.

## Goal

Move the roster domain from one venue-global roster surface toward explicit roster groups, while centralizing an idempotent venue bootstrap path that guarantees sane minimum roster defaults.

## Why This Exists

The current roster model assumes:

- one roster week per venue/week
- venue-global `slot_names`
- venue-global roster UI and live-update scope

That works for the current single-roster shape, but it leaves two structural gaps:

- a venue can exist in a roster-broken state when fixtures or scripts create the venue without active slot names
- the model cannot cleanly support multiple rosters per venue such as front of house and back of house

The future direction should therefore be:

- roster groups as the scheduling boundary inside a venue
- one shared venue bootstrap function for minimum roster defaults
- explicit staff-to-roster-group applicability

Ordinary multi-venue switching remains a separate concern and should stay out of this pipeline.

## Coordinator Tracking

- Epic: `coordinator-wii`
- Related but separate backlog feature: `coordinator-hap`

## Settled Direction

- introduce first-class roster groups under a venue
- treat roster groups, not the whole venue, as the eventual roster-week and slot-definition boundary
- centralize venue bootstrap into one idempotent function shared by fixtures, scripts, and future venue-creation flows
- require sane minimum roster defaults through that bootstrap path
- support staff applicability to one roster group, multiple roster groups, or all groups
- keep ordinary multi-venue switching separate from roster-group architecture

## Minimum Invariants

- every active venue should have at least one active roster group
- every active roster group should have at least one active slot definition
- venue bootstrap should create a default active roster group and default active slots when needed
- roster actions should fail explicitly when those invariants are broken rather than silently doing nothing

## Scope

- `roster_groups` domain model and migration/backfill path
- group-scoped slot definitions
- group-scoped roster weeks and roster actions
- shared venue bootstrap/defaults service
- staff-to-roster-group applicability model
- roster UI, admin flows, and live-update scopes becoming group-aware

## Non-Goals

- ordinary multi-venue switching for users with memberships in multiple venues
- support/super-admin cross-venue access
- payroll/export semantics being split by roster group unless a later lane explicitly requires it
- arbitrary venue creation/self-serve onboarding product work

## Implementation Slices

### 1. Core roster-group model and migration (`coordinator-wii.2`)

- add first-class roster groups under a venue
- make the future roster boundary explicit enough to support `Main`, `Front of House`, `Back of House`, or similar lanes
- move or associate slot definitions and roster weeks with that boundary
- define the migration/backfill path from the current single-roster venue model
- current landed foundation: `roster_groups` exists, `slot_names` and `roster_weeks` now carry `roster_group_id`, and current app flows implicitly target the default roster group until group-aware routing/UI lands

### 2. Centralized venue roster bootstrap defaults (`coordinator-wii.3`)

- create one idempotent ensure/bootstrap function for minimum roster defaults
- route fixture seeding, scripts, and future venue-creation flows through it
- guarantee venue config, day names, a default roster group, and default active slot definitions are created together
- return explicit setup errors or warnings when invariant repair is needed
- current landed foundation: venue/test bootstrap now converges on one helper that ensures venue config, weekday names, a default active roster group, and default slot names for fresh venues

### 3. Staff-to-roster-group applicability (`coordinator-wii.4`)

- add an explicit eligibility mapping between venue staff and roster groups
- support front-of-house-only, back-of-house-only, and multi-group staff
- keep roster-group applicability separate from venue membership and auth authority
- use that mapping to shape the roster staff panel and assignment controls

### 4. Group-aware roster UI, admin flows, and live updates (`coordinator-wii.1`)

- make the active roster group explicit in routes, controller actions, and page state
- scope create/copy/publish flows to roster group plus week
- make slot-name management and roster setup admin surfaces group-aware
- extend live-update scopes so roster freshness keys include roster group, not only venue and week offset

## Recommended File Touchpoints

- `Application/Schema.sql`
- `Application/Helper/Controller.hs`
- `Application/Helper/View.hs`
- `Web/Controller/RosterWeeks.hs`
- `Web/View/RosterWeeks/Show.hs`
- `Web/Controller/Admin.hs`
- `Web/View/Admin/Index.hs`
- `Application/Script/SeedPayrollFixture.hs`
- `Test/Support.hs`
- `Test/Support/PayrollFixtures.hs`
- roster controller specs and e2e roster coverage

## Acceptance Checks

Done when:

1. a venue can own more than one roster group without overloading venue-global slot names and roster weeks
2. one shared bootstrap path guarantees sane minimum roster defaults for newly created or freshly seeded venues
3. staff eligibility can be configured per roster group, including multi-group staff
4. roster UI, admin management, and live-update scopes are group-aware
5. a venue can no longer silently render a roster surface where add-row does nothing because required roster defaults were never created
