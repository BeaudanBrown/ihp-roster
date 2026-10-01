# Venue recipient groups

`Application.RecipientGroups` owns authorised group reads and mutations;
`Validation.hs` shares address syntax/normalisation with legacy payroll settings.
Groups confer no application permissions. Venue admins/owners and platform support
with a real current venue may manage them; membership authority stays separate
from support authority.

Writes serialize on the same venue row as payroll preparation and settings
changes. A revision protects drafts, and active group names are unique per venue,
case-insensitively. Address lists are private: do not print request inputs or
record addresses in operational diagnostics. Validation is not mailbox ownership
verification or permission to share payroll information.

Editing a group changes future preparations only. Prepared run recipients and
artifacts are immutable; retry must not resolve the group's latest addresses.
Deletion archives the group rather than removing historical identity. Explicit
confirmation is required when a schedule references it; deletion then clears the
selection, disables automation and cancels only unstarted automatic work.
Prepared manual/updated sends remain eligible. SMTP already underway cannot be
recalled. Payroll settings own this narrowly scoped cancellation operation.

Admin → Recipient groups is a separate accordion section. `Web.RecipientGroups`
owns typed dialog requests/responses; `Web.View.Admin.RecipientGroups` owns
server-rendered drafts and confirmation copy. Native email validation blocks
malformed Add/Enter submissions; the shared typed default-Enter target activates
Add rather than Save. Remove bypasses pending-entry validation, and Cancel never
submits. Empty pending input permits saving a valid list. Server validation,
venue authority, bounds and revision checks remain mandatory.

Successful writes and the recipient-group Surface invalidation commit together;
actor feedback refreshes the same fragment and passive viewers use the durable
outbox. The `*InCurrentTransaction` domain APIs let this outer owner retain atomic
publication. DELETE confirmation fields are non-private typed URL values because
IHP does not parse DELETE request bodies. Browser evidence lives in
`e2e/recipient-groups.spec.ts`; HTTP authority in
`Test/Controller/RecipientGroupsSpec.hs`.

Migration `1793068000` adds storage and nullable schedule links. It does not invent
groups from legacy lists, retime schedules, or alter existing report snapshots.
Upgrade through the normal migration procedure, preserving tables on application
rollback. Before changing selection authority, verify the expected absence of
legacy schedules; unexpected lists need an operator-approved mapping, not a reset.
