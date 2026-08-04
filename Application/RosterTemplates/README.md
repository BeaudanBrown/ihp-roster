# Roster Templates

`Application.RosterTemplates` owns the roster-group-scoped Day/Week template aggregate.

- Saved names are trimmed and case-insensitively unique within a roster group, across both scales.
- Saved content is immutable by version. Edits use a private copy and commit with optimistic version checking.
- Each effective user has at most one private recoverable draft globally.
- Draft content uses explicit Staff/Open assignments and structurally complete shifts.
- Save converts stale or pay-invalid Staff assignments to Open with typed warnings; stale Shift types block the whole save.
- Saved templates soft-delete. Unsaved drafts and their content may be permanently discarded.
- Access uses the same manager-or-higher and venue-writable capability as roster editing, including support-mode super admins.

`Application.RosterTemplates.Mutations` contains the minimal PostgreSQL row lock used to serialize optimistic commits. All ordinary reads use IHP QueryBuilder.
