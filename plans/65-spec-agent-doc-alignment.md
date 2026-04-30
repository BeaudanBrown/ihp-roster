# Spec and Agent Documentation Alignment

Read after `IMPLEMENTATION_PLAN.md`, root `AGENTS.md`, and the relevant local
`tk` ticket. This plan records the 2026-04-30 documentation/specification audit
and turns it into implementation and documentation work.

## Goal

Bring active specs, agent instructions, planning notes, and repo-local `tk`
status back into agreement with the current implementation without losing the
historical value of older plan files.

The audit found two classes of divergence:

- implementation gaps where the code does not yet meet the spec and should be
  fixed
- stale documentation/planning text where the implementation is now the intended
  behavior and the docs should be updated or marked superseded

## Tracker

Primary epic:

- `ir-m8hc` - Align specs and agent docs with current implementation

Child tickets:

- `ir-3vc6` - Implement pay snapshot reproducibility for approved/exported payroll
- `ir-z5dj` - Update payroll specs and agent docs to the award-level model
- `ir-gz6l` - Align export access docs with admin-only implementation
- `ir-r2pp` - Annotate Xero owner-only access as superseding older venue-admin plan text
- `ir-nin6` - Update roster auto-create specs and tracker status
- `ir-e3o5` - Refresh AGENTS navigation and frontend asset guidance
- `ir-f8tn` - Reconcile completed maintenance tickets and stale plan findings
- `ir-tqnr` - Add lightweight documentation drift checks

Related existing tickets:

- `ir-caf4` / `ir-lz0x` - schema and snapshot hardening
- `ir-5o6t`, `ir-59gm`, `ir-y8mj` - roster materialization and week controls
- `ir-nn8p`, `ir-59ps`, `ir-6vvh` - maintenance cleanup and stale findings

## Source of Truth Policy

Use this priority order when resolving drift:

1. `Application/Schema.sql`, controller/domain code, and passing tests describe
   current implementation behavior.
2. `specs/` describes product intent. If product intent still matters and code
   is behind it, create/keep an implementation ticket instead of weakening the
   spec.
3. `AGENTS.md` files describe current agent operating rules and should not
   contain stale historical behavior.
4. `plans/` are durable design history. Prefer short "Current status" or
   "Superseded by" notes over rewriting old plan history.
5. `.tickets/` is the live status tracker. If status changes, update `tk`; do
   not rely on plan prose as the only status record.

## Findings and Decisions

### 1. Pay snapshot reproducibility

Current status, 2026-04-30: superseded by
`plans/68-append-only-pay-config-versioning.md` and `ir-hw2v`.

The implementation direction has changed from making JSON
`pay_config_snapshots` drive payroll calculations to replacing that system with
append-only relational pay config versions and approval/export/Xero locking
gates. Treat `ir-3vc6` and `ir-lz0x` as problem/audit context, not the current
implementation path.

Original audit decision: implementation should move toward the spec.

The spec requires approved/exported payroll output to resolve against immutable
pay/config snapshot context. Current SQL pay calculation still resolves important
facts from mutable current tables, especially effective pay level and rate
lookups.

Work:

- Update `calculate_timesheet_pay` and range/export paths so
  `pay_config_snapshot_id` drives historical resolution when present.
- Keep draft/unapproved calculations on current config.
- Add regression tests that approve an entry, mutate pay-relevant config, and
  prove approved/exported output remains unchanged.

Ticket: `ir-3vc6`

### 2. Payroll terminology and schema docs

Decision: docs are stale and should match current schema unless a new product
decision reintroduces day-specific pay overrides.

Docs still mention `pay_levels` and `pay_level_day_rules` as current schema. The
current schema uses `award_levels`, `award_level_base_rates`,
`award_level_penalty_rates`, `staff.default_award_level_id`, and
`shift_types.override_award_level_id`.

Work:

- Update `specs/02-domain-model.md`, `specs/06-pay-engine.md`, and
  `Application/AGENTS.md`.
- If day-specific overrides are deferred, describe them as future work only.

Ticket: `ir-z5dj`

### 3. Export access

Decision: implementation is right; docs/plans are stale.

Current code restricts export generation/download surfaces with `ensureAdminRole`.
Tests deny managers. Some docs/plans still say managers may generate exports.

Work:

- Update active docs to venue-admin/owner/super-admin only.
- Mark old manager-export guidance as superseded where it appears in historical
  plans.

Ticket: `ir-gz6l`

### 4. Xero access

Decision: implementation is right; old plan text is stale.

Current code and tests restrict Xero management to current venue owners and
super admins. Older Xero foundation plan text says venue admins can open/manage
Xero.

Work:

- Add a current-status note to `plans/58-xero-connection-foundation.md`.
- Keep root `AGENTS.md` owner-only guidance as the active rule.

Ticket: `ir-r2pp`

### 5. Roster week auto-materialization

Decision: implementation appears intentional; docs and tracker status need
reconciliation.

Current code materializes a missing roster week when any authenticated venue
member visits it, while staff see masked/unpublished draft content. Tests cover
staff materialization and hidden draft shells. Specs still say only managers,
venue admins, and owners auto-create missing weeks.

Work:

- Update `specs/04-roster-and-conflict-rules.md`.
- Reconcile `ir-59gm` and related roster tickets so the remaining work is clear:
  copy-overwrite verification and reusable controls, not basic materialization.

Ticket: `ir-nin6`

### 6. AGENTS navigation and frontend assets

Decision: docs are stale.

The implemented global nav includes `xero` between `leave` and `admin`. The
root JavaScript split list is missing newer app-owned files. Old CDN concerns
for HTMX and Bootstrap Icons are resolved by vendored assets loaded through
`assetPath`.

Work:

- Update `Web/View/AGENTS.md` nav order.
- Update root `AGENTS.md` frontend asset list.
- Annotate old CDN findings in `plans/59-code-smell-remediation.md` if they are
  still presented as active work.

Ticket: `ir-e3o5`

### 7. Completed maintenance findings

Decision: verify, then close or narrow stale tickets.

The audit found code that appears to have already landed for durable invitation
delivery and production venue bootstrap helper extraction, while old tickets and
plan findings still describe them as open.

Work:

- Verify no request-thread `forkIO` invitation delivery path remains.
- Verify production controllers do not depend on destructive `Application.Support`
  helpers.
- Close or narrow `ir-nn8p` and `ir-59ps` accordingly.

Ticket: `ir-f8tn`

### 8. Drift prevention

Decision: add only lightweight checks.

Avoid brittle prose tests, but add a cheap guard where it protects a high-value
invariant such as nav order, protocol scope names, or script asset lists.

Ticket: `ir-tqnr`

## Suggested Execution Order

1. Fix or ticket-confirm pay snapshot reproducibility first. This is the only
   high-risk implementation gap.
2. Update payroll specs and agent docs after the intended schema/snapshot model
   is clear.
3. Update low-risk authorization/navigation/frontend docs.
4. Reconcile stale maintenance and roster ticket statuses.
5. Add any lightweight drift checks.

## Verification

Documentation-only changes:

```bash
bash ./bin/in-env typecheck
tk ready
```

Pay snapshot implementation changes:

```bash
bash ./bin/in-env regen-types   # only if schema changes
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Payroll export parity" --match "Exports"
```

Roster tracker/spec reconciliation with code changes:

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "RosterWeeks"
```

Frontend/AGENTS-only changes generally do not need E2E unless behavior changes.

## Fresh-Agent Prompt

Use the prompt below when handing this work to a new agent:

> You are working in `/home/beau/documents/projects/ihp-roster`. Read root
> `AGENTS.md`, then `plans/65-spec-agent-doc-alignment.md`, then `tk show
> ir-m8hc` and the child ticket you choose to work on. The goal is to bring
> specs, agent instructions, plans, and `tk` status back into agreement with the
> current implementation after the 2026-04-30 divergence audit.
>
> Treat `Application/Schema.sql`, current controller/domain code, and tests as
> implementation truth. Treat `specs/` as product intent. If code is behind
> product intent, do not paper over it in docs; keep or create an implementation
> ticket. If docs/plans are stale and implementation is now intentional, update
> active docs and add short current-status/superseded notes to old plans.
>
> Prioritize `ir-3vc6` first unless the user asks for documentation-only work:
> approved/exported payroll must resolve against immutable
> `pay_config_snapshots` rather than mutable current pay config. Add regression
> tests that mutate pay-relevant config after approval/export and prove old
> output is stable. Then handle doc-only tickets: payroll terminology
> (`ir-z5dj`), export admin-only access (`ir-gz6l`), Xero owner-only access
> (`ir-r2pp`), roster auto-materialization docs/tracker (`ir-nin6`), AGENTS nav
> and JS asset guidance (`ir-e3o5`), stale maintenance ticket reconciliation
> (`ir-f8tn`), and lightweight drift checks (`ir-tqnr`).
>
> Do not overwrite unrelated dirty work. Use `tk` for live status updates. Run
> `bash ./bin/in-env typecheck` after code/doc-adjacent Haskell changes, and run
> focused Hspec for behavioral changes.
