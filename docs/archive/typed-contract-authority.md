# Typed Contract Authority

Status: implemented and archived

Epic: [#328](https://github.com/BeaudanBrown/ihp-roster/issues/328)

Baseline: [#329](https://github.com/BeaudanBrown/ihp-roster/issues/329)

## Intent

Every app-owned closed value, request shape, DOM contract, and workflow
operation has one typed Haskell authority. Feature views render through the
matching declaration-indexed helper, controllers parse the matching nominal
operation, and browser code consumes only explicitly reachable generated
contracts. Raw text remains only at a named external/platform boundary or a
narrow reason-bearing escape hatch.

GitHub Issues owns implementation status and dependencies. This workstream
records the cross-ticket contract, baseline, affected living docs, and exit
criteria; it is not a parallel task list.

## Authority Invariants

### Source

1. A persisted app-owned finite domain is a PostgreSQL enum and is consumed via
   its generated Haskell constructors. Do not create a shadow ADT.
2. A non-persisted app-owned finite request/browser domain is a closed
   FrontendContract declaration. `WireText` is not its semantic type.
3. Each Surface or AppShell mutation is nominal and owns exactly its submitted
   fields. A text discriminator plus optional superset is not a sum type.
4. Haskell renders names and values through the declaration-indexed operation;
   its controller parses through that same operation's exact parser.
5. Render a closed value to text only at persistence, telemetry, HTML, or an
   external wire boundary. Application decisions match constructors
   exhaustively, without a wildcard that hides a newly generated case.

### Compile failure

Focused fixtures must reject wrong-domain values, cross-operation bundles,
missing/extra/reordered fields, and incorrect optional/nullable nesting. Adding
an app-owned closed case must make every semantic Haskell projection
compiler-visible and every exhaustive TypeScript consumer fail its generated
contract check until handled.

### Drift

Generated Haskell adapters and TypeScript contracts remain byte-checked against
the checked IR. Schema-backed changes update `Application/Schema.sql`, an
upgrade migration, generated types, and exhaustive consumers together. Source
audits become blocking tombstones only after this baseline's candidates are
migrated or classified; broad word-based regexes are forbidden.

### Reachability

Application reachability uses fresh HIE data. Real IHP instance, controller,
view, script, reflection, and generated entrypoints receive narrow roots with
reasons. Declaration-complete generated Resource/Live modules may retain their
existing category roots. Handwritten modules, curated facades, and generated
Action/Intent APIs do not receive blanket roots or symbol allowlists.

## Baseline Inventory

Reproduce the source evidence and topology counts with:

```bash
bash ./bin/in-env typed-contract-authority-audit
```

The command is reporting-only. It deliberately does not fail on current
candidates; final blocking checks belong to the issue that removes or classifies
each candidate.

### Rendered generated-enum branches

| Domain | Concrete evidence | Intended owner |
| --- | --- | --- |
| Roster layout | `Application/Helper/UserPreferences.hs`, `Web/RosterWeeks/WageFilter.hs`, `Web/Controller/RosterWeeks.hs`, and roster settings/grid views branch through `rosterLayoutModeValue` text. | Generated `RosterLayoutModeEnum` constructors; request representation becomes a closed scalar. |
| App job status | `Web/View/Billing/Index.hs` and `Web/View/Support/Index.hs` branch on `inputValue status`, duplicate labels, and include fallback cases. | Generated `JobStatus` constructors plus one focused exhaustive presentation/capability projection. |
| Invitation lifecycle | `Web/View/Support/Index.hs` compares rendered invitation status with `"pending"`; `Web/View/Admin/Invites.hs` and `Web/View/Staff/Edit.hs` pass rendered statuses into presentation helpers. | Generated invitation status/delivery constructors with typed projections. |

The reporting scan intentionally includes rendered-value comparisons that need
classification. `inputValue` used for UUID comparison/serialization,
untrusted-text enum parsing, audit/telemetry values, HTML option values, or
external payloads is a boundary operation, not a semantic enum branch.

### Closed domains currently carried by `WireText`

| Class | Concrete declarations | Intended owner |
| --- | --- | --- |
| Schema-backed | `Surface.Interaction.LayoutModeInteraction`; `Surface.Profile` fields `VenueRoleField` and `EmploymentBasisField`. | Their generated PostgreSQL enum types. |
| DSL-owned finite values | `Surface.Roster.StaffScope`; `Surface.Admin.ExportType` and `ColourKey`; `Surface.LeaveRequests.LeaveSection`; Profile/AppShell `SectionField`; AppShell `FeedbackTypeField`. | Closed FrontendContract scalar declarations when not already schema-owned. |
| Sum/discriminator shapes | `Surface.Admin.ConfigFieldField`; Admin `PayRateSelection`; AppShell Xero `DecisionField`/`XeroEmployeeSelectionField`. | Nominal operations first; then a closed scalar or tagged request shape only where a finite value remains. |

Free-form names/copy/reasons, opaque keys, provider ids, URLs, CSS selectors,
and route/query context remain text. Boolean/query parsing such as
`showApproved`, `weekOffset`, and ordinary route ids should use the appropriate
existing primitive/parser but is not app-owned DSL state merely because it is
currently text.

### Handwritten names and values inside typed forms

The high-priority AppShell field-name bypass in
`Web/View/Admin/Xero/TimesheetPreparation.hs` was removed by #332. Period,
staff-decision, managed-pay-item, reference-wait, and submission workflows now
select nominal `AppShellContract` bundles for field names, metadata, hidden
route values, and exact controller parsing. The remaining
`decision="select_employee"` and `xeroEmployeeSelection="not_applicable"`
literals are finite-value candidates for the enum workstream; the employee id
itself remains provider-owned text.

Surface forms generally obtain names from generated bundles, but still contain
closed value literals that need a typed projection:

- `Web/View/Admin/VenueSettings.hs`: four `ConfigFieldField` discriminator
  values;
- `Web/View/Profiles/Edit.hs` and `Web/View/Staff/Edit.hs`: `SectionField`
  values `profile`/`preferences`;
- `Web/View/Admin/Xero/TimesheetPreparation.hs`: generated `ShowMatched` name
  with handwritten boolean text.

The audit also reports literal names in any module that uses typed Surface or
AppShell metadata. Those are candidates, not automatic violations: native IHP
method fields, upload mechanics, ordinary route context, and unrelated forms in
the same module require classification before a guard is added.

### Catch-all action

`Application/Helper/FrontendContract/Surface/Admin.hs` declares
`UpdateVenueConfig` as `ConfigFieldField` plus seven optional fields.
`Web/Controller/Admin.hs` dispatches on the discriminator, and
`Web/View/Admin/VenueSettings.hs` repeats the discriminator values. The owner is
separate nominal setting operations with exact generated builders and parsers.

### Raw recurring HTMX recipes

The reporting scan excludes OOB response swaps and the contract runtime itself.
Current request-side evidence includes:

- load/outerHTML fragment recipes in `Web/View/Staff/Edit.hs` and
  `Web/LeaveRequests/SelfService.hs`;
- autosave `change`, delayed `input`, and `hx-include="closest form"` recipes in
  `Web/View/Admin/VenueSettings.hs` and `Web/View/Admin/ShiftTypes.hs`;
- AppShell route extras such as `click consume` in
  `Web/View/RosterWeeks/StaffPanel.hs`;
- target/swap extras around Profile/Staff forms.

Common stable recipes should move to typed HTMX vocabulary. A remaining raw
recipe must be narrow, non-empty-reason-bearing checked IR. `hx-swap-oob` on an
authoritative response, native form method mechanics, and ordinary route URLs
are not request-DSL bypasses.

### App-owned constrained Xero text

`Application/Schema.sql` uses checked `TEXT` for app workflow families including
staff/earnings mapping state, account-code selection, pay-item requirement
state, sync status/kind, preparation/submission run status/source, preparation
decision kind/status, and per-staff submission status. Production branches and
writes are concentrated under `Application/Xero/Timesheets/`,
`Application/Xero/Admin/`, and
`Web/View/Admin/Xero/TimesheetPreparation.hs`. These are candidates for
migration-safe PostgreSQL enums and generated constructors.

## Permitted Exceptions

| Boundary | Narrow exception and reason | Evidence/owner |
| --- | --- | --- |
| Xero provider vocabulary | Employee/account/pay-run/timesheet statuses, earnings/rate/unit/account types, remote ids, and opaque payload fields stay open for provider forward compatibility. Parse/normalize only in Xero adapters. | `Application/Schema.sql` provider snapshot tables; `Application/Xero/Admin/ReferenceData.hs`; Xero request/response modules. |
| Stripe provider vocabulary | Stripe ids, statuses, event types, metadata, and payload projections remain provider-owned text at the Stripe adapter/persistence seam. They must not become FrontendContract app enums. | `Application/Billing/` provider client and webhook boundaries. |
| WebAuthn/browser platform | Credential objects, extension results, platform events, capability detection, native properties, ARIA state, and local-storage hints remain in the focused browser adapter. `WireUnknown` stays limited to extension results. | `Application/Helper/FrontendContract/Passkey.hs`, `Wire/Passkey.hs`, and the passkey TypeScript adapter. |
| Native browser/HTMX mechanics | `_method`, native input state, browser events, and response-side OOB mechanics are platform transport, not app-owned domain state. | `Web/View/Layout.hs` owns IHP method forms; `Application/Helper/FrontendContract/Htmx.hs` and `Surface/Runtime.hs` own typed request rendering; controller `Responses.hs` modules own OOB response mechanics. |
| Presentation | Bootstrap/CSS classes and local transient `is-*` classes are presentation vocabulary unless a generated app state is explicitly shared with Haskell. | `static/css/README.md` defines CSS ownership; focused adapters such as `frontend/ts/app-dialog-overlays.ts`, `frontend/ts/roster/fullscreen.ts`, and `frontend/ts/roster/column-edit.ts` own transient classes. |
| Route context | Paths, query filters, return targets, pagination/week offsets, and opaque ids remain Haskell/IHP route context unless they are fields of a nominal operation. | `pathTo`, `appendQueryParams`, and `AppShellActionRoute`. |

An exception does not permit application business logic to branch on external
text outside its named adapter. Any raw contract escape hatch must record its
specific reason in checked IR; directory-wide exemptions are not permitted.

## Baseline Metrics

Captured on the #329 baseline:

| Measure | Baseline |
| --- | ---: |
| Haskell adapter generator foundation | 10 files / 3,083 LOC |
| Feature family/home associations | 8 files / 156 LOC |
| Generated Haskell adapter modules | 24 files / 3,483 LOC |
| Curated generated-adapter facades | 24 files / 614 LOC |
| Generated TypeScript contracts | 1 file / 1,671 LOC |
| Profile Action exact `Application.*` closure | 19 modules |
| Roster Intent exact `Application.*` closure | 20 modules |
| FrontendContract Weeder candidates | 0 |
| Other ignored framework/application Weeder candidates | 255 |

Topology LOC is physical line count (`wc -l`), intentionally simple and
repeatable rather than a semantic SLOC claim. Reproduce closure and full
candidate evidence with:

```bash
bash ./bin/in-env architecture-surface-request-closure --print-modules
WEEDER_PRINT_CANDIDATES=1 bash ./bin/in-env weeder-check
bash ./bin/in-env ./bin/doc-drift-check
```

The closure command owns exact module sets, not counts alone. Generator
simplification must compare files touched, handwritten foundation/home/facade
cost, generated output, focused closure, diagnostics, publication atomicity,
and drift behavior; reducing LOC cannot weaken nominal typing.

## Reconciled Living Docs

Implemented contracts were moved into:

- `Application/Helper/FrontendContract/README.md`;
- `Application/Helper/FrontendContract/Surface/README.md`;
- `Application/Helper/Interaction.SPEC.md`;
- `Application/Xero/README.md` and `Application/Xero/SPEC.md`;
- nearest `AGENTS.md` when a reusable authoring/verification rule emerges.

Durable authority rationale is retained in ADR 0002 and ADR 0003. This archive
preserves the reproducible baseline and final exit evidence; implementation
history remains in Git and GitHub Issues.

## Exit Evidence

- No app-owned closed request value degrades to unclassified `WireText`.
- No catch-all discriminator action or handwritten migrated operation field
  remains.
- No semantic branch uses rendered generated-enum text.
- App-owned constrained Xero state uses migration-safe generated enums;
  provider vocabulary remains explicitly external.
- Generated contract/adapter drift, compile-failure, exact-parser, source, and
  schema checks block regressions.
- Fresh application-wide Weeder output has no unexplained candidate; any bounded
  residual is narrow and reason-bearing.
- Generator authoring cost and focused closure improve or retain a documented
  tradeoff without weakening authority guarantees.
- Living docs describe the final implemented contract and this workstream is
  archived; GitHub remains the closure/status authority for the epic and its
  final issue.
