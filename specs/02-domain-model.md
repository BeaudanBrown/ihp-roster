# Domain Model

## Core entities

## Venue boundary and identity

- `venues`
  - Current customer account and top-level data ownership boundary.
  - Holds venue lifecycle, status and top-level settings.
- `users`
  - Global auth identity.
  - May belong to one or more venues over time.
- `venue_memberships`
  - Links a `user` to a `venue`.
  - Holds venue-scoped role and membership lifecycle.
- `business_accounts` / `tenants` (future, optional)
  - If needed later, sit above venues for multi-venue customers.
  - Must be additive to the current venue-owned operational model rather than a rewrite of existing records.

## Worker records

- `staff`
  - Venue-scoped worker profile used by roster, timesheet and pay logic.
  - May reference a `user_id` for login-enabled workers.
  - May exist without `user_id` for placeholders.
  - Must not become a dumping ground for sensitive or unrestricted free-text data.

## Governance and audit

- `audit_events`
  - Immutable audit trail for security-sensitive and employment-record actions.
  - Includes actor, venue, event type, timestamp, target record and before/after metadata.
  - Event names and source channels come from the closed typed vocabulary in
    `Application.Helper.Audit.Vocabulary`; its exhaustive renderers own the exact
    persisted and telemetry wire text.
- `export_jobs`
  - Venue-scoped record of generated exports, scope, file metadata, requestor and lifecycle.
- `venue_billing_customers`
  - Venue-scoped Stripe Customer reference.
  - One Stripe Customer per venue for launch.
  - Stores the validated Stripe mode and optional initiating-user audit
    reference, but no payer payment details.
- `billing_checkout_attempts`
  - Venue-scoped durable Checkout correlation and recovery record.
  - Stores initiating user, validated Stripe mode, bounded provider IDs,
    lifecycle timestamps/status, and bounded sanitized failure metadata.
  - PostgreSQL permits at most one open attempt per venue and requires unique
    non-null Stripe Checkout Session IDs.
  - The attempt is committed before provider Session creation. Venue-row locking
    serializes concurrent create/resume decisions, and Stripe creation reuses an
    idempotency key derived from the durable attempt ID.
  - Success and cancellation returns are accepted only when authenticated venue,
    local attempt, and stored Session identity correlate; returns do not grant
    subscription state.
  - Does not store hosted URLs, raw provider payloads, payment methods, billing
    addresses, or tax details.
- `venue_subscriptions`
  - Venue-scoped Stripe subscription state mirror.
  - Stores Stripe subscription/price IDs, validated mode, status, current period
    timestamps, cancellation flag, last-applied provider ordering cursor and sync
    timestamps.
  - Signed Stripe webhooks are the normal state-transition path. Read-only
    reconciliation may refresh only a known Session/Subscription after exact
    Customer, mode and venue-metadata validation.
- `billing_events`
  - Durable Stripe webhook/API event processing ledger.
  - Deduplicates by Stripe event ID and retains Stripe event creation time for
    ordered Subscription updates.
  - Stores event type, provider object IDs, processing status, timestamps and
    concise summaries, not full raw sensitive Stripe payloads by default.
- Billing reconciliation `app_jobs`
  - Target a known local Checkout attempt or Subscription and deduplicate while
    active.
  - Persist only bounded target metadata, result summaries, and sanitized
    terminal errors; provider payloads and payer details remain outside Bepis.
- `venue_billing_controls`
  - Venue-scoped billing control record.
  - Holds `billing_required`, manual read-only state, manual reason, setter and
    timestamps.
  - Separate from `venues.status`; billing writability and venue lifecycle are
    different concerns.
- `record_corrections` or equivalent event/version tables
  - Additive correction history for payroll-adjacent records.
- `pay_config_versions` / `venue_config_snapshots` or equivalent
  - Immutable versions of pay-relevant venue configuration created from venue admin bulk-save actions.
  - Referenced by approved payroll-adjacent records and exports.

## Scheduling

- `roster_weeks`
  - Venue-scoped `week_offset`
  - `is_live` (published visibility gate)
- `roster_days`
  - `roster_week_id`
  - `day_offset` (0..6)
- `roster_templates` and `roster_template_designs`
  - Roster-group-scoped Day/Week template identity plus immutable saved versions.
  - Active names are trimmed and case-insensitively unique per roster group across both scales.
  - A design is either one saved template version or the single private recoverable draft owned by an effective user globally.
  - Template days, columns, and shifts are child content; shifts require valid local minute boundaries, a Shift type, and explicit Staff/Open assignment.
  - Blank and confirmed live/draft roster references initialize only the private design copy. Designer autosaves never mutate the reference and reject incomplete or currently invalid shift references before persistence.
  - Saved templates soft-delete; discarded unsaved designs may be permanently removed.
  - Applying a Day version replaces one draft roster day while preserving unrelated week structure; applying a Week version replaces the complete draft week. Target-local clocks resolve under Melbourne DST rules. Stale Staff assignments become Open through a new immutable template version in the same transaction as target replacement; stale Shift types block. Replaced roster shifts remain soft-deleted Timesheet provenance.
- `roster_slots`
  - One structurally complete roster shift positioned by `roster_day_id`,
    `roster_week_slot_definition_id`, and non-negative `row_index`.
  - Authoritative `starts_at` / `ends_at`, `Australia/Melbourne` timezone
    snapshot, and required `shift_type_id` for every active row.
  - Closed `assignment_state`: `staff` requires exactly one venue-valid
    `staff_id`; `open` requires no `staff_id`. Nullable staff storage is never
    itself an assignment state.
  - Deleted historical rows remain retained and may preserve legacy incomplete
    structure; active legacy incomplete rows were soft-deleted during the
    explicit-assignment migration.

## Time and approval

- **Timesheet suggestion**
  - A transient read model derived from an eligible shift on a live roster.
  - It has no table and is not a Timesheet entry status.
- `timesheet_entries`
  - Staff, venue, date/day reference, start/end/break, approval status.
  - Optional immutable `source_roster_slot_id` records roster provenance.
  - At most one active entry may reference a source slot; deleted historical
    snapshots do not block a later active snapshot.
  - Inputs use exact 15-minute increments by default or whole-minute precision when enabled for the venue.
  - Must support additive correction or version history.
  - Hard deletion is not the normal correction path once business use begins.

## Leave and roster preferences

- `leave_requests`
  - Staff, start/end dates, status (`pending | approved | denied`).
  - Must support status history and actor attribution.
- `staff_shift_preferences`
  - Recurring global weekday availability preferences for a staff member.
  - Each active row means the staff member is available on that weekday, across roster groups.
  - `preferred_start_hour` and `preferred_end_hour` store the preferred shift start window as whole-hour values (`5..23`, start <= end).
  - A staff member with no preference for a weekday is treated as unable to work that roster day for V1 filtering.

## Configuration

- `venue_config` or equivalent venue-scoped configuration
  - Timezone.
  - Week start/day naming preferences.
  - `week_offset_epoch` (global fixed epoch value unless later re-specified).
  - `late_to_early_min_start_gap_minutes` (venue-level threshold).
  - Current editable configuration surfaced on the venue admin page.
  - `auto_timesheet_creation_enabled` is a deprecated, false, inert compatibility
    column and is not current editable configuration.
- Supporting config tables:
  - `slot_names`
  - `day_names`
  - `shift_types`
  - `award_levels`
  - `award_level_base_rates`
  - `award_level_penalty_rates`
  - `staff.pay_assignment_mode`, `staff.default_award_level_id`, and `staff.imported_xero_pay_item_id`
  - `shift_types.pay_assignment_mode`, `shift_types.override_award_level_id`, and `shift_types.imported_xero_pay_item_id`
  - append-only `staff_pay_versions` and `shift_type_pay_versions`, which capture the same mode and references

Pay-assignment mode makes nullable rate references unambiguous. Staff modes are
Award, imported Xero, roster-only, and migration-only legacy-unresolved. Shift
modes are staff default, Award/Xero override, and roster-only. Database checks
require exactly the reference shape for each mode; normal application mutations
cannot select legacy-unresolved. Staff roster-only is absolute; otherwise shift
roster-only wins, then a shift override, then the staff rate.

The current pay configuration model does not include day-specific pay-level
override rows. A shift type Award/Xero override applies to every entry using
that shift type. Reintroducing day-specific overrides would require a new schema
and pay-engine change.

## Data classification requirements

- Ordinary profile data, payroll-adjacent data, security/audit data and restricted future data must be modelled distinctly.
- Sensitive categories such as health, banking, TFN, superannuation, biometrics or government identifiers require dedicated tables and a separate spec before introduction.
- Free-text note fields must be narrowly defined and export-reviewed.
- Billing integration data is provider metadata, not payment detail storage.
  The app must not store card details, bank details, ABNs, billing addresses,
  tax IDs, or full raw Stripe payloads by default.

## Data integrity requirements

- Soft-delete or active/inactive flags for config that may be referenced historically.
- Historical timesheet/pay rows must remain calculable even if config entries are disabled later.
- All venue-owned records must be venue-scoped at the schema level.
- Business roles belong to `venue_memberships`; `users` is identity, not venue authority.
- Employment-record changes must preserve provenance, including actor and timestamp.
- Export generation must produce a durable audit trail and versioned output metadata.
- Pay-relevant configuration must be historically reproducible through immutable snapshot/version records created by venue admin save actions.
- Approved payroll-adjacent records and exports must reference the pay/config snapshot version used.
- Subscription status must not automatically change venue writability in v1.
  Founder super-admin manual read-only controls are the only billing-driven
  write restriction until an explicit future ticket changes that contract.
