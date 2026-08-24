# Roster Templates

`Application.RosterTemplates` owns the roster-group-scoped detached snapshot aggregate.

- A template is the aggregate root. Days, columns, and shifts reference it directly; there are no private drafts, designs, versions, source links, or restore history. Its roster group, scale, and internal completion identity are immutable after creation.
- Persistence retains the Day/Week scale discriminator, but the current creation primitive accepts complete Week snapshots only.
- Week content contains all seven unique day indexes and durable weekday identities, at least one valid column, unique cells, valid row placement and times, and explicit Staff/Open assignments. A deferred completion witness invalidated by every child mutation prevents incomplete aggregates from committing, including through direct SQL.
- Staff and Shift type identities remain direct foreign keys. Names are resolved from current records rather than copied into snapshots.
- Names are trimmed, required, at most 120 characters, and case-insensitively unique among active templates in one roster group. Soft deletion releases the name.
- Authorized reads and writes require manager-or-higher roster-edit capability and an explicit current-venue/roster-group match, including support-mode policy supplied by `currentRosterTemplateActor`.
- Content replacement rewrites children inside the caller's transaction and retains no previous snapshot. Week application resolves an ISO anchor to one complete all-Draft date-native window, maps saved weekdays to matching operational weekdays, resolves repeated Melbourne boundaries to their first occurrence, and rejects nonexistent boundaries.
- Application-time durable Staff and stale Shift-type remediation replaces template content inside the same date-locked transaction as target replacement. Approved leave changes only the target assignment; durable cleanup changes both template and target. Existing Timesheet snapshots and their source roster-slot provenance remain untouched while replaced roster slots are soft-deleted.
- `Application.RosterTemplates.Mutations` isolates row and advisory locks. Ordinary reads use IHP QueryBuilder.

Migration `1789000000.sql` performs the direct-snapshot cutover. It aborts if any legacy template rows exist, preserves unrelated Roster and Timesheet data, and is operated under `Application/Migration/roster-template-snapshot-cutover-397-runbook.md`.
