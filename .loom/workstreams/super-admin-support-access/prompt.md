Implement the `super-admin-support-access` workstream in `ihp-roster`.

Read first:

1. `AGENTS.md`
2. `IMPLEMENTATION_PLAN.md`
3. `plans/00-auth-bootstrap-memberships.md`
4. `plans/48-super-admin-support-access.md`
5. `.loom/workstreams/super-admin-support-access/context.md`
6. `.loom/workstreams/super-admin-support-access/handoff.md`

Objective:

- add founder-only platform super-admin support access
- allow the founder to switch into any active venue via a dedicated support page
- reuse the existing `currentVenueId` session slot
- preserve venue memberships as the only business-role source for ordinary users
- distinguish support-mode actions in audit and UI

Implementation order:

1. platform role and venue access context (`coordinator-xga.3`)
2. support page and switching (`coordinator-xga.1`)
3. audit/UI distinction (`coordinator-xga.4`)
4. verification (`coordinator-xga.2`)

Constraints:

- no synthetic venue memberships
- no UI path to grant additional super-admins
- no ordinary-user multi-venue switching in this lane
- no impersonation

Verification target:

- schema/helper coverage for platform role and venue resolution
- controller coverage for support-page auth and switching
- one browser flow proving founder cross-venue switching
