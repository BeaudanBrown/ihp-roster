# Roster Weeks Specification

This file describes implemented roster-week behavior. Future roster-group,
pilot, or payroll prediction work belongs in `docs/workstreams/` until it
lands.

## Current Contract

- `weekOffset` in the URL is the source of truth for the viewed week.
- `RosterWeeksAction` resets to the current week.
- `ShowRosterWeekAction { weekOffset }` is the canonical explicit week route.
- HTMX week navigation swaps the stable roster shell and pushes canonical URLs.
- Missing weeks may be materialized when an authenticated venue member visits
  them; staff see hidden/unpublished draft shells when appropriate.
- Staff users cannot edit unpublished roster weeks.
- Managers, venue admins, venue owners, and support-mode super admins can use
  manager/admin roster controls according to the controller capability checks.
- Publishing a roster is the visibility gate for staff-facing roster content.
- Roster forms must submit full cell payloads so single-field edits do not
  clear sibling slot fields.

## Scheduling Data

- Roster weeks are venue-scoped and may be roster-group-scoped as the group
  model lands.
- Roster days group slots by day offset.
- Roster days store their visible open-day row count independently of slots.
- Roster slots are sparse positioned data records. Blank editable cells are
  rendered from the day row count and active slot definitions; active blank
  slots should not be stored.
- Slot rows use `row_index` to align early/mid/late-style visual rows in the
  default table layout.
- Day-column layout renders actual slots compactly in column-major order and
  ignores holes in the default table layout.
- Slot names and shift types are venue configuration, not free-form authority.
- End-time and explicit shift-type pilot behavior is tracked through
  `docs/workstreams/rooks-pilot.md` until the full contract is settled here.

## Conflict And Availability Rules

- Late-to-early conflict uses start-to-start gap.
- The threshold is venue-level configuration.
- Staff shift preferences are recurring weekday availability windows.
- Leave/unavailability conflicts affect roster availability according to the
  approved-state rules in the leave subsystem.

## Live Updates

- The roster shell stays subscribed even when a week is empty or hidden so
  create/copy/publish transitions can update passive viewers.
- Actor browser responses return HTMX fragments or OOB swaps.
- Passive viewers receive websocket invalidations with structural fragment refs.
- Fragment GET routes must enforce the same venue/visibility rules as the full
  page.
- Focused roster note inputs use live-fragment protection so remote updates do
  not clobber active editing.

## Extension Rules

- Do not store last-viewed week in the database without a new product decision.
- Do not add feature-specific JavaScript for generic live-surface behavior.
- If a mutation fans out across many possible weeks, intersect with active live
  subscriptions before querying cold historical scopes.
- Preserve stable DOM ids from `Web/RosterWeeks/Dom.hs` when changing views or
  responses.

## Verification

Use focused checks for roster work:

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "RosterWeeks"
bash ./bin/in-env e2e e2e/roster-live-fragments.spec.ts
bash ./bin/in-env e2e e2e/roster-mobile.spec.ts
```
