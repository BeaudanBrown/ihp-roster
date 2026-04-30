# Pipeline 66 - Input Handling And Injection Hardening

Read after `IMPLEMENTATION_PLAN.md`, `plans/60-v1-schema-hardening.md`, and
the repo-local `tk` tickets listed below.

## Goal

Raise the app's default input-handling standard so user-controlled data is
required, parsed, normalized, constrained, and rendered/exported safely across
controllers, helpers, database schema, and tests.

This plan captures the security audit follow-up from 2026-04-30. It is a
coordination plan, not proof that the fixes are complete.

## Ticket Map

- `ir-5rhn` - Input handling and injection hardening
- `ir-z51k` - Add shared request validation helpers and harden required fields
- `ir-l4ux` - Neutralize spreadsheet injection in CSV exports
- `ir-qksy` - Replace unsafe request-derived ID parsing
- `ir-36t6` - URL-encode query string helper usage
- `ir-c6cu` - Add text normalization and schema length constraints
- `ir-z8l8` - Raise input security standards in agent docs and tests

Related security/schema work:

- `ir-caf4` - V1 schema hardening
- `ir-2ds0` - Harden session/auth/assets/security headers
- `ir-7gm0` - Add core CHECK constraints and active-row uniqueness

## Scope

- server-side required-field validation for all user entry points
- safe parsing for request-derived ids, dates, times, enums, and lists
- consistent trimming, blank handling, and length limits for user text
- CSV/spreadsheet formula injection protection
- URL/query construction safety
- database constraints that backstop application validation
- regression tests and agent documentation so new work follows the same rules

## Non-Goals

- Do not replace IHP form helpers or QueryBuilder.
- Do not add raw SQL for ordinary request handling.
- Do not redesign user flows unless the existing flow cannot surface validation
  errors safely.
- Do not silently change product semantics such as which fields are optional
  without confirming that with the existing specs or tickets.

## Audit Findings To Address

### Missing Required Params Can Become Defaults

IHP's request filling can ignore missing params, so HTML `required` attributes
are not a server-side guarantee. Builders that use `fill` or typed param
helpers must explicitly reject missing required fields and malformed values.

Priority entry points:

- leave request create/update/cancel flows
- timesheet entry create/update/approve flows
- staff/profile editing
- onboarding and invitation/bootstrap flows
- admin config forms for roster groups, slot names, shift types, exports, and
  Xero mappings

### Unsafe Request-Derived ID Parsing

`Application/Helper/StaffShiftPreferences.hs` decodes preference keys from
request text. Bad UUID text must not be able to throw an exception or produce a
500. Cross-venue and cross-group ids must be treated as invalid even if they are
well-formed.

### CSV Export Cells Need Formula Neutralization

`Application/Helper/Export/Render.hs` quotes CSV syntax but must also prevent
spreadsheet formula execution for cells that begin, after whitespace handling,
with dangerous formula prefixes such as `=`, `+`, `-`, `@`, tab, or carriage
return.

### Manual Query String Concatenation

`Application/Helper/View/Format.hs` contains a query helper that concatenates
raw key/value text. Replace it with URL encoding and cover paths with existing
query strings, spaces, ampersands, equals signs, and empty values.

### Text Normalization And Schema Backstops Are Inconsistent

Names, notes, passkey names, phone numbers, labels, and admin-config text should
have predictable trimming, blank-to-null or blank-reject behavior, maximum
lengths, and parser-safe database constraints where appropriate.

## Implementation Order

1. Re-read the relevant local IHP docs and source before editing:
   `Guide/form.markdown`, `Guide/validation.markdown`,
   `Guide/querybuilder.markdown`, `Guide/security.markdown`, and
   `IHP/Controller/Param.hs`.
2. Add small shared controller/input helpers for required params, typed params,
   list parsing, safe ids, text trimming, blank handling, and length checks.
   Keep helper names explicit and local to controller/form use.
3. Harden high-risk mutation controllers first: leave and timesheets. Missing
   or malformed required fields should produce normal validation errors or
   controlled 4xx/redirect responses, never defaults or exceptions.
4. Harden staff/profile, onboarding/invitation, admin config, export filter,
   and Xero mapping forms with the same helper patterns.
5. Replace unsafe shift-preference key parsing with total parsing. Validate
   weekday, staff, roster group, slot, venue, and group membership before
   applying any mutation.
6. Harden CSV rendering with a single reusable cell sanitizer. Preserve correct
   CSV quoting while neutralizing spreadsheet formula execution.
7. Replace manual query string assembly with URL-encoded construction and update
   call sites only as needed.
8. Add schema constraints for stable length and blank/nonblank invariants. Keep
   constraints parser-safe for IHP: explicit `OR` checks instead of `IN (...)`,
   and verify with the full schema workflow.
9. Update `AGENTS.md`, `Web/Controller/AGENTS.md`, `Web/View/AGENTS.md`,
   `Application/AGENTS.md`, and `Test/AGENTS.md` with concise rules and tested
   examples.
10. Close or update each `tk` ticket only after its acceptance checks pass.

## Test Matrix

For every changed entry point, add focused Hspec coverage for:

- missing required params
- malformed dates, times, UUIDs, enum/status values, booleans, and integers
- oversized text and whitespace-only text
- cross-venue and cross-roster-group ids
- suspicious text payloads such as `<script>`, quotes, and shell-like strings
- repeated/list params with invalid members
- validation error rendering that preserves safe user input without executing it

For exports, add tests for:

- leading `=`, `+`, `-`, `@`
- leading tab, carriage return, newline, and formula text after whitespace
- quotes, commas, and newlines
- ordinary negative numbers or legitimate text if product rules need them

For URL helpers, add tests for:

- spaces, ampersands, equals signs, percent signs, and unicode-adjacent input
- paths with and without existing query strings
- empty values and omitted optional values

For schema hardening, add tests for:

- direct SQL rejecting impossible tenant/length/blank states
- controller validation failing before database errors for normal user mistakes
- IHP parser compatibility after `pg_dump` round trips

## Verification Commands

Use the repo wrapper unless already inside the activated devenv shell.

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Leave" --match "Timesheet" --match "Staff" --match "Profile" --match "Export"
bash ./bin/in-env lint
bash ./bin/in-env format
```

When `Application/Schema.sql` changes:

```bash
bash ./bin/in-env regen-types
bash ./bin/in-env typecheck
bash ./bin/in-env make db
bash ./bin/in-env dev-stop
bash ./bin/in-env dev-start
bash ./bin/in-env dev-wait
```

If a focused Hspec match does not cover the changed module, run the relevant
suite or the full `bash ./bin/in-env hspec-test`.

## Documentation Standard

The documentation ticket `ir-z8l8` should land last so it describes patterns
that were actually implemented. The docs should include:

- `fill` does not prove required params are present
- use shared required/typed-param helpers for user input
- never parse request ids with throwing conversion functions
- validate tenant scope after parsing any id
- use QueryBuilder for normal database access
- use encoded URL/query helpers
- use centralized CSV cell rendering for exports
- add missing, malformed, oversized, cross-scope, and suspicious-payload tests
  for every new or changed input boundary
