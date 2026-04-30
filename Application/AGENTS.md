# Application Guidelines

## Schema (`Application/Schema.sql`)
This is the **source of truth** for all database models. Read `/home/beau/documents/projects/ihp/Guide/database.markdown`.

- Edit this file to add/modify tables — IHP auto-generates `build/Generated/Types.hs` from it
- Use `snake_case` for table and column names — IHP converts to `camelCase` in Haskell
- Table names should be **plural** (e.g., `posts`, `users`, `comments`)
- Always include `id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL` as first column
- Use `created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL` and `updated_at` for timestamps
- Foreign keys: `user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE`
- For finite-state columns (statuses, roles, event kinds), prefer PostgreSQL `ENUM` types over `TEXT` + `CHECK (... IN (...))`.
- Reason: IHP reparses `pg_dump` output during startup, and Postgres rewrites `CHECK (col IN (...))` into `col = ANY (ARRAY[...])`; the vendored IHP schema parser does not accept that `ANY (ARRAY ...)` form.
- Verify enum names against IHP's parser quirks:
  - do not start custom enum type names with built-in SQL type tokens such as `time`, `timestamp`, `interval`, etc., because the parser may consume the prefix as a built-in type before it reaches the custom-type fallback
  - watch for generated enum constructor collisions with existing model constructors; e.g. an enum value `staff` collides with the `Staff` model constructor when `Generated.ActualTypes` re-exports enums
- If an enum value would collide with a model constructor and you cannot safely rename the stored value, keep the column as `TEXT` and use an explicit parser-safe check like `(role = 'a') OR (role = 'b')` instead of `IN (...)`.

Example:
```sql
CREATE TABLE posts (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);
```

After editing the schema you must do **two things**:

1. **Regenerate Haskell types** — run `bash ./bin/in-env regen-types` (updates `build/Generated/Types.hs`)
2. **Apply to the running database** — run `make db` while `devenv up` is active in another terminal

`make db` drops and recreates the entire database from `Schema.sql` + `Fixtures.sql`. This is safe in development. **Without running `make db` the app will crash at runtime with "relation does not exist"** even if typecheck passes.

`Application/Fixtures.sql` should also keep a deterministic dev bootstrap login so a fresh `make db` always leaves at least one known manual-test account available. In this repo the intended founder/sysadmin bootstrap email is `beaudan.brown@gmail.com`; the fixture must seed:

- `users.platform_role = 'super_admin'` for the founder account
- an active `venue_memberships` row with `venue_role = 'venue_owner'` or `venue_role = 'venue_admin'` in the default dev venue

Do not assume `users.user_role = 'admin'` is sufficient, because runtime authorization remains venue-scoped for ordinary access.

Treat fixture rows as deliberate bootstrap data, not throwaway local-only seeds. This repo's production Nix config also references `Application/Fixtures.sql`, so bootstrap accounts added here can affect any freshly initialized deployed database as well.

The IHP schema-designer toast `Unmigrated Changes. Your app database is not in sync with the Schema.sql` is not authoritative for this repo by itself. In vendored IHP it is driven by an in-memory toolserver flag that is set when the IDE edits `Schema.sql` and cleared when the IDE migration flow runs; it does not independently prove the database is out of sync after external workflows like `make db`. For this project, trust `make db` plus an explicit DB check / app restart over that toast.

For schema work that adds enums or constraints, also do a real startup verification after `make db`: restart the dev server (`dev-stop`, `dev-start`, `dev-wait`) and confirm it reaches healthy status. `typecheck` and the test suite validate `Application/Schema.sql` and generated types, but they do not catch every parser failure triggered by IHP re-reading `pg_dump` output on boot.

Current auth direction: founder-wide cross-venue support uses a separate platform-level capability on `users` (`platform_role = 'super_admin'`). Keep that distinct from venue business roles like `manager`, `venue_admin`, and `venue_owner`; do not model support access as synthetic `venue_memberships`.

Venue-linked operational accounts should satisfy one invariant: for each `(venue_id, user_id)` pair that represents a real venue member, there should be exactly one linked `staff` row in that same venue. Provision venue users through the shared helper path instead of creating `venue_memberships` and `staff` rows independently, and preserve the partial unique index on linked staff rows so future multi-venue support keeps one global `users` identity with venue-local `staff` profiles.

To verify the schema is applied, connect to the dev DB and check:
```bash
psql -h "$PWD/build/db" app -c "\dt"
```

## Helpers
- `Application/Helper/Controller.hs` — compatibility wrapper for shared controller helpers
- `Application/Helper/View.hs` — compatibility wrapper for shared view helpers
- These are already imported via `Web.Controller.Prelude` and `Web.View.Prelude`
- Prefer adding new shared helpers to focused submodules first:
  - controller helpers under `Application/Helper/Controller*.hs` or adjacent feature modules
  - view helpers under `Application/Helper/View/*.hs`
- Treat the top-level wrapper modules as re-export surfaces for compatibility. Do not grow them back into monoliths.
- Keep durable audit writes centralized in `Application/Helper/Controller.hs`; prefer one append-only `audit_events` helper that stores structured `JSONB` payloads and call it inside the same `withTransaction` as the sensitive mutation.
- Keep export generation/download flow centralized under `Application/Helper/Export*.hs`; controllers should delegate venue-scoped export creation, expiry checks, and audit emission there instead of hand-rolling ad hoc CSV endpoints.
- Prefer splitting export code by concern:
  - `Application/Helper/Export/Types.hs` for export/report domain types and text conversions
  - `Application/Helper/Export/Render.hs` for CSV/ZIP rendering and pure formatting helpers
  - `Application/Helper/Export.hs` for DB-backed orchestration, authorization, expiry, and audit wiring
- Treat `Application/Helper/Export.hs` as the orchestration layer and compatibility wrapper, not the default place for new pure rendering helpers.
- Keep payroll report selection separate from export-job lifecycle. Venue-scoped report definitions (slug, engine, description, optional shift-type filters) should decide which report a venue can request; `export_jobs` should remain the request/generation/download/audit record for the concrete file instance.
- Legacy payroll parity currently maps venue report definitions like this:
  - `staff_hours` and filtered variants such as `kitchen` use `staff_pay_csv`
  - `wage` uses `hourly_breakdown_zip`
- Export generation and download are admin-only surfaces (`ensureAdminRole`): venue admins, venue owners, and super admins may generate/download exports; managers are denied. Keep this aligned with `Test/Controller/ExportsSpec.hs`.
- Current product focus is narrower than the full legacy inventory:
  - the only active payroll-export target is one canonical `staff_hours`-style CSV for the primary/only venue staff group
  - filtered variants such as `kitchen` are historical/regression behavior, not the first-class current requirement
  - future multiple staff-group or multiple roster-group payroll exports should be treated as a separate later product lane, not implied by the current CSV hardening work
- `export_jobs.file_contents` remains text-backed even for binary reports. Store ZIP payloads base64-encoded with `file_encoding = "base64"` and decode them only in the download path; keep plain CSV exports at `file_encoding = "utf8"`.
- For request-scoped business context such as `currentVenue` / `currentVenueMembership`, resolve it once in `Web/FrontController.initContext` and store `Maybe ...` values via `putContext`; views can then read them safely with frozen-context helpers instead of re-querying.
- Support access is represented by:
  - a real `currentVenue`
  - `currentVenueMembershipOrNothing = Nothing`
  - `currentUserIsSuperAdmin = True`
  Keep that shape intact so later audit/UI layers can distinguish founder support mode from ordinary venue membership access.
- For payroll-adjacent mutations, append provenance rows from shared helpers instead of scattering ad hoc JSON snapshots across controllers. Timesheet corrections use `timesheet_entry_versions`; leave lifecycle transitions use `leave_request_events`; venue-role assignment/change uses `venue_membership_role_events`.
- Keep pay/config reproducibility centralized in `Application/Helper/Pay.hs`: payroll-adjacent workflows should bind approved rows, exports, and Xero submissions to append-only relational pay config versions (`staff_pay_versions` and `shift_type_pay_versions`) instead of trusting mutable current config.
- Payroll report parity now depends on two persisted facts:
  - `timesheet_entries.shift_type_id` is the authoritative shift-type input for pay resolution and report grouping
  - effective award level resolution uses `shift_types.override_award_level_id` first, then `staff.default_award_level_id`
- The current schema does not have `pay_level_day_rules`. Treat day-specific award-level overrides as future work unless a new schema change reintroduces them.
- Award-level monetary inputs live in `award_level_base_rates` and `award_level_penalty_rates`, scoped by effective award level, employment basis, penalty kind, and operative dates. Any payroll/export change that needs wage math should read those canonical rows instead of recreating parallel monetary fields.
- `day_names.weekday_index` is treated as real weekday numbering for pay resolution (`EXTRACT(DOW ...)`: Sunday `0` through Saturday `6`). When rendering week-scoped report columns, do not sort/export by raw `weekday_index`; reorder labels by the selected week start date so Monday-first (or venue-specific epoch-first) week views stay stable while the SQL pay engine still resolves overrides correctly.
- The pay payload now exposes effective shift-type/pay-level identifiers and labels plus real monetary fields (`baseRate`, per-segment `amount`, `totals.totalAmount`) for payroll export/report shaping.
- Keep reusable overlay helpers in focused view helper modules:
  - `Application/Helper/View/Overlay.hs` for shared dialog mount ids, overlay config/button types, and workflow dialog / `setModal` footer rendering
  - `Application/Helper/View/Toast.hs` for toast mount ids, toast config, and toast rendering
- Keep toast host placement declarative as well. Prefer a `position` enum or class mapping in the helper layer instead of hardcoded left/right CSS in the layout.
- Prefer data/config records over passing Haskell callbacks into view builders. Server-rendered HSX stays easier to reuse when overlays are described declaratively.
- Shared form helpers should usually render only fields plus the `<form>` wrapper. Put submit/cancel controls in the overlay footer so the same form body can be used by both HTMX dialogs and `setModal` fallback views.
- For shared page shells and panels, use `Application/Helper/View/Chrome.hs` instead of mixing page/panel markup into unrelated feature view helpers.

## Database Queries
Read `/home/beau/documents/projects/ihp/Guide/querybuilder.markdown`. Key patterns:
```haskell
-- Fetch all
posts <- query @Post |> fetch

-- With filters
posts <- query @Post
    |> filterWhere (#userId, userId)
    |> orderByDesc #createdAt
    |> fetch

-- Single record
post <- query @Post |> fetchOne
post <- query @Post |> fetchOneOrNothing

-- Create
newRecord @Post |> set #title "Hello" |> createRecord

-- Update
post |> set #title "New title" |> updateRecord

-- Delete
deleteRecord post
```
