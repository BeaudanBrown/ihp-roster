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

`Web.RosterWeeks.TemplateApplication` owns authoritative preview and confirmation application. It:

- replaces one draft day while preserving unrelated week columns, or replaces the complete draft week;
- resolves date-free template minutes against target Melbourne dates and requires explicit repeated-time choices;
- blocks stale Shift types and converts unavailable, group-invalid, or pay-invalid Staff assignments to Open;
- writes assignment cleanup as a new immutable template version in the same transaction as the roster replacement;
- soft-deletes replaced roster source shifts so materialized Timesheet snapshots remain unchanged; and
- returns typed template/target revisions, warnings, resolved shifts, conflicts, and touched roster/Timesheet/template resources.
