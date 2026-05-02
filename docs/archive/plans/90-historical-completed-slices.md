# Historical Completed and Superseded Slices

This file preserves completed or superseded detail that no longer belongs in the root roadmap.

## Completed Foundation Slices

### 0.1 Core schema skeleton
- **Status:** [x]
- Expanded `Application/Schema.sql` from auth-only to core domain skeleton.
- Added `Test/SchemaSpec.hs` to assert generated model types compile.
- Verification run: `regen-types`, `typecheck`, and `test` passed.

### 0.2 Venue config singleton and bootstrap seed
- **Status:** [x]
- Historical note only. This reflected the pre-venue-scoped config shape and bootstrap seed work.

### 0.3 Enum/value normalization for statuses and roles
- **Status:** [x]
- Added normalized constraints/helpers for legacy user-role and leave-status handling.
- Some of this work now needs migration toward membership-scoped authority.

## Completed Auth Slices

### 1.2 Mandatory profile completion gate
- **Status:** [x]
- `ProfilesController` and required profile flow are implemented.

### 1.3 Role-based authorization helpers
- **Status:** [x]
- Helpers exist, but should be migrated away from `users.user_role` for venue business permissions.

## Superseded Slice

### 1.1 First-user bootstrap admin
- **Status:** [!]
- Implemented historically, but superseded by founder-managed venue bootstrap.
- Remove this behavior from live code and tests as part of pipeline 00.

## Completed Cross-Branch Work

### 60.1 Template extraction backport to `master`
- **Status:** [x]
- The template-extraction pipeline is complete and has been archived out of the active roadmap.
- This work backported reusable infrastructure from `roster` to `master` only; no roster domain code crossed over.
- Landed on `master` in these commits:
  - Phase 1 tooling/build fixes: `138f3c2`, `a266d95`, `11af962`, `21c5f38`, `43ffa4b`
  - Phase 2 theme/layout foundation: `3faa95c`, `f23d928`
  - Phase 3 overlay system: `c72d2a3`
  - Phase 4 generalized `AGENTS.md`: `24b7691`
  - Phase 5 generic controller helpers: `9634255`
  - Optional Phase 6 quarter-hour time picker: `7771436`
- See `master` history for the code-level detail; the dedicated `docs/archive/plans/60-template-extraction.md` file is no longer needed on `roster`.
