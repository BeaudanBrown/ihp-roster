# Provisional Controller and Workflow Contract

Design for [epic #508](https://github.com/BeaudanBrown/ihp-roster/issues/508)
and [contract #509](https://github.com/BeaudanBrown/ihp-roster/issues/509).
**Proposal, not implemented rules.** Source references describe baseline
`61e783bc45a9d00f2a554475488a5cf16e2d66e6`; operation/type sketches below are
provisional unless explicitly called existing. No runtime, route, schema,
generated contract, authorization, or provider cutover is authorized here.
The operator reviews this contract before either pilot; selecting implementation
and accepting issue closure remain separate decisions. GitHub owns scope and status.
The matrices record change risks needed to judge these proposed interfaces, not
replacement feature specifications. Linked code/tests remain current authority.

## Desired depth and seam

A deep feature module should hide the decisions necessary to complete one
operation, not merely rename a controller's sequence of helper calls. Its
interface includes inputs, error precedence, transaction ownership, side effects,
and response expectations—not just a Haskell type. The deletion test: removing
it would put those decisions back in several callers.

The proposed roles are **not mandatory files** or a whole-application migration:

| Role | Decisions owned | Dependency direction |
| --- | --- | --- |
| IHP controller | `beforeAction`/`action`, access-policy invocation, permission response choice, request adaptation, operation invocation, feature response selection | Existing `Web.Controller.Prelude` and focused Web feature modules |
| Request adapter | Route/field decoding, omission versus invalid input, existing form annotations and navigation context | IHP and operation-local generated AppShell/Surface facades; no new wire schema |
| Feature workflow | Scoped loading, operation-specific validation/application, choice of existing mutation, completion data | Feature policy, persistence/mutation and read-model owners; not another controller |
| Mutation/effect owner | Lock order, revalidation, writes, existing audit/version/job effects, touched resources, commit/rollback | Existing domain/provider modules, shared audit/error and durable publication owners |
| Authoritative projection | Authorized page/fragment data and post-write impact data, without a second cache or payroll calculation | Existing read models, `Projection`, `SurfaceImpl` |
| Feature response/view owner | Exact response status/headers, form/dialog or redirect, copy, requester extras and presentation | Feature outcomes, existing views, shared response/live helpers; no second passive publisher |

Keep ordinary request orchestration in the existing `Web/Exports/`,
`Web/RosterWeeks/`, and `Web/Billing/` namespaces. Application modules remain
free of new redirects/HTMX/view dependencies. A role can be a small private
function in an existing module. Split only when a distinct caller/test seam
justifies it; do not add a generic CRUD layer, universal action-result registry,
policy-flag bag, effect typeclass, or configurable callback pipeline.

### Lifecycle, authority and error discipline

- [Bepis controller policy](../../Application/Bepis/Controller.hs) annotates
  the existing IHP `beforeAction`; it does not perform access checks.
  [runBepis](../../Application/Bepis/Action.hs) observes an ordinary `IO`
  action and owns the shared unexpected-error fallback. Neither supplies a
  transaction nor makes parsed input authorized. Keep action kinds and facts
  emitted by the real effect helpers, not descriptive metadata alongside them.
- Preserve the current order of authentication, venue/profile/role/strong-auth
  checks, writability, parameter decoding, scoped lookup and domain validation.
  Total adapters must not eagerly decode everything before a currently earlier
  denial, or replace an existing error with a nicer but different one. A
  suspicious existing case needing behavior repair requires separate scope.
- Use [ControllerContext](../../Application/Helper/ControllerContext.hs) and
  existing access helpers, not a second authorization model. Ordinary authority
  is effective venue membership/Staff; support has a real venue and **no venue
  membership**. Never require a fabricated membership for support. Impersonation
  uses effective authority without granting founder bypass.
- `ActualUser`/`EffectiveUser` come only from that initialized request context,
  never submitted IDs. Existing [Audit](../../Application/Helper/Audit.hs)
  supplies the actual authenticated actor, source channel and support or
  impersonation payload (including effective user and session). Retain that
  context at the effect; passing two IDs alone would lose provenance. Do not
  invent audit rows for operations that currently have none.
- A parsed ID or cached `RosterWindowScope` is only an input. Resolve records
  against the current venue/group/date at the existing validation points, then
  repeat the existing authoritative checks under locks before writing. A new
  wrapper around a record must not imply stronger authorization or freshness.
- IHP `fill` ignores absent fields and records parse errors; required fields,
  blank optional values, malformed values, nullable values and lists must retain
  their current distinctions. Reuse declared generated parsers and current IHP
  form validation. Do not add a generic raw-field dictionary or browser parser.
- [Error.Boundary](../../Application/Error/Boundary.hs) deliberately rethrows
  IHP `ResponseException`, asynchronous cancellation and record-not-found control.
  Rendering/redirects terminate the action. Never catch them as ordinary workflow
  failures or run mutation effects after a terminal response.

### Transactions are operation-specific

[Web.SurfaceInvalidation](../../Web/SurfaceInvalidation.hs) delegates to
[DurablePublisher](../../Application/Helper/LiveUpdate/DurablePublisher.hs).
Its outcome selector determines publication, **not rollback**: `Nothing` commits
without an event. Returning `Left` after partial writes can therefore commit them.
IHP `withTransaction` rolls back escaping exceptions and rejects nesting.

For an ordinary operation, preserve the existing outer transaction, do all
failure-producing pre-write checks at their current positions, and let write,
audit or outbox failures escape it. Map known persistence exceptions only outside
that owner. If a new typed failure can follow writes, it needs explicit rollback
before it becomes a returned result; reuse
[withAppResultTransaction](../../Application/Error/Transaction.hs) only where
`AppResult` already fits, or the existing feature's focused rollback technique.
Do not stack transaction runners or force every feature error into `AppError`.

Keep HTTP response construction outside a transaction that must commit. Moving
an existing response exception out of a lock changes rollback unless its
replacement explicitly preserves it. Conversely, a provider's rejection may
legitimately **commit** a durable diagnostic or expired attempt. No universal
"Left means rollback" wrapper can represent both cases.

## Ordinary-form design: edit a saved Payroll Workbook

### Proposed interface and caller knowledge

Conceptual Web feature interface; existing implicit IHP model/request contexts
are omitted from sketches for readability, not replaced by an effect framework:

```haskell
editSavedWorkbook :: WorkbookEditInput -> IO WorkbookEditOutcome

-- Input: route configuration ID, export anchor Day, submitted name,
-- ordered textual family keys, expected revision.
-- Outcome: editor rejection with the exact submitted/fallback draft and error,
-- or saved configuration with anchor and LiveMutationResult resources.
```

The request adapter uses the existing
`parseAppShellActionParams @UpdatePayrollWorkbookConfigurationOverlay` from
[AppShell.Request](../../Application/Helper/FrontendContract/AppShell/Request.hs).
Transport failure stays at that seam: it constructs the current fallback
week/draft and response, without calling persistence. A successful input is not
an authorized configuration or a validated workbook definition. The workflow
owns semantic family parsing, draft construction and mutation invocation;
current definition version is backend policy, not a caller-selectable flag.

Before: [Exports controller](../../Web/Controller/Exports.hs),
`UpdatePayrollWorkbookConfigurationAction`, knows family decoding, fallback
values, revision, draft/input conversion, mutation errors, toast, overlay cleanup,
Admin fragment and native URL assembly. After: it keeps access/writability and
request adaptation, invokes `editSavedWorkbook`, then selects the feature editor
response. It no longer constructs the definition, chooses persistence helpers,
or assembles the success response. Create/delete expose their own named
operations, not an `isUpdate`/`isDelete` mode.

### Owners and preservation matrix

| Concern | Owner and behavior to retain |
| --- | --- |
| Request/access | Existing Exports `beforeAction`: user, current venue, completed profile, admin role; Save checks writability before decoding. Admins/owners and unimpersonated support with a venue work; managers do not. |
| Error precedence | Transport errors use `currentExportWeekSelection`, new draft plus route ID. Unknown family errors retain submitted revision but current empty fallback name/families. Successfully decoded families produce the submitted draft. The update mutation locks the current-venue row **before** the inner name/definition/revision checks; absent row remains NotFound even with an invalid name. Do not unify these branches. |
| Scoped persistence | [Web.Exports.Mutations](../../Web/Exports/Mutations.hs), `updatePayrollWorkbookConfigurationMutation`, owns the existing ID + venue row lock and durable transaction. [PayrollWorkbookConfiguration](../../Application/Helper/Export/PayrollWorkbookConfiguration.hs), `updateSavedPayrollWorkbookConfigurationInCurrentTransaction`, resolves ID + venue again, validates name/definition and expected revision, then increments revision and replaces ordered families. |
| Data/queries | Keep the [Export specification](../../Application/Helper/Export/SPEC.md) unchanged. The seam must retain sequential contiguous family insertion and query order/count; it does not own XLSX rendering or historical export-job snapshots. |
| Failure/commit | Invalid/stale input writes nothing. SQL failures escape the durable transaction; both Hasql forms of SQLSTATE 23505 map to the same friendly conflict after rollback, regardless of constraint; other failures propagate. Family replacement and outbox cannot partially commit. |
| Effects/provenance | Exactly one existing `payroll_workbook_configuration.update` publication with `adminExportsResource` on success, none on rejection. Configuration create retains actual authenticated `createdByUserId`; edit/create/delete do not acquire new configuration audit rows. Export generation/download audit remains separate and unchanged. |
| Response | Proposed focused Web response owner moves the existing helpers unchanged: native flash + 302 to the date-selected Admin exports anchor; HTMX rejection returns the current editor dialog, success sets `HX-Reswap: none`, actor resource refresh for the date-specific Admin fragment, then dialog-clear OOB and success toast in that order. No business OOB or direct passive broadcast. |

Reuse [Hasql.isUniqueViolation](../../Application/Helper/Hasql.hs) and the
existing private `createConfigurationFamilyRecords` rather than retaining the
classifier and create-loop copies. Standard provisioning remains an explicit
in-current-transaction Application operation for Users; do not route onboarding
through a request workflow or open a nested transaction.

### Characterization at the seam

[Workbook pilot #511](https://github.com/BeaudanBrown/ihp-roster/issues/511)
owns exact cutover scope. Its saved-configuration seam excludes unrelated export
generation/download and must preserve draft-only controls even if their shared
response helper moves.

[PayrollWorkbookConfigurationSpec](../../Test/PayrollWorkbookConfigurationSpec.hs)
is the persistence oracle; [ExportsSpec](../../Test/Controller/ExportsSpec.hs)
is the request/response oracle; [UsersSpec](../../Test/Controller/UsersSpec.hs)
protects standard provisioning. Existing tests do not prove every failure
combination. The proposed seam needs pre-movement characterization
for missing/malformed fields versus role denial, unknown/duplicate/empty families,
foreign/deleted IDs plus invalid names, two edits with one revision, concurrent
unique conflicts, and an injected family/outbox failure after the parent write.
Assert retained rows/revision, exact native/HTMX responses, and audit/outbox counts.
Retain golden XLSX/CSV/ZIP expectations rather than deriving expected values from
the new implementation. Repoint tests of replaced coordination to the public
workflow; keep independent persistence and HTTP acceptance tests.

## Scheduling design: edit a shift or fill a Published Open shift

### Proposed interface and caller knowledge

```haskell
editRosterShift :: ShiftEditInput -> IO ShiftEditOutcome
createRosterShift :: ShiftCreateInput -> IO ShiftCreateOutcome

-- Edit input: route slot ID, submitted anchor/calendar context,
-- RosterShiftDialogSubmission (including presence of protected fields).
-- Create input additionally identifies day, lane and sparse row placement.
-- Outcome: exact dialog continuation, feature rejection, or committed
-- completion containing scope, mutation resources, impacted rows and feedback.
```

Keep the existing submission's optional raw text/occurrence distinctions until
[ShiftWorkflow](../../Web/RosterWeeks/ShiftWorkflow.hs) validates them. In
particular, `Nothing` and `Just ""` for a protected Published field are not
interchangeable. Adapt calendar context at its existing stage, not by eagerly
rejecting every field from the generated overlay parser. The current
`requireRosterShiftCalendarAppShellContext` selects only calendar-field errors;
other field errors belong to the dialog validator.

Before: [RosterWeeks controller](../../Web/Controller/RosterWeeks.hs),
`UpdateRosterSlotAction`, loads records, derives scope, chooses Draft versus
Published validation, applies fields, passes `allowPublishedOpenFill`, queries
related staff slots and assembles impacted rows and warning policy. After:
controller keeps manager/writable guards, staged adaptation and response
selection; the feature operation owns that coordination. The operation derives
Draft edit versus Published fill from authoritative state; callers cannot grant
Published access with a Boolean. Create remains a separate sparse-cell operation.
Private mutation variants may be named explicitly; constructor choices wait for
the pilot, not a new general permission algebra.

### Owners and preservation matrix

| Concern | Owner and behavior to retain |
| --- | --- |
| Access/order | Manager and writable guards first. Edit currently fetches slot, rejects deletion, fetches its day, enforces venue/date/calendar context, then checks closed/publication state before validating fields. `ShiftWorkflow`'s ID-only fetch helpers are **not** authorization. Move coherent scoped loading into the feature operation without inventing an earlier lookup/error or an additional broad group-access policy. |
| Sparse create | Preserve `fetchRosterDayForMutation`/`fetchRosterDayForRequest` materialization and projected-day validation, lane/day agreement, non-negative row, existing-cell reuse and row growth. Materialization can precede form validation and has its own existing lock/transaction behavior; "invalid form means no writes anywhere" is not a safe blanket claim. Do not pull it into a new encompassing transaction. |
| Validation | Reuse `validateRosterShiftDialogSubmission`, `validateLiveOpenShiftFill`, `applyValidatedRosterShift` and [Service](../../Web/RosterWeeks/Service.hs), not a second implementation of the [Roster scheduling specification](../../Web/RosterWeeks/SPEC.md). Preflight validation does not replace locked persistence validation. |
| Published fill | Only a Published Open shift may become valid Staff. Submitted protected times/type/occurrences reject even when blank where presence currently matters. No other fields change, no delete or Staff-to-Open escape. Concurrent stale assignment cannot silently refill a staffed shift. |
| Locks/revalidation | [Mutations](../../Web/RosterWeeks/Mutations.hs) retains date/calendar/publication lock, Staff operational locks, slot row lock and current assignment/deletion check, then persistence validation. `rosterSlotStillMatches` checks current Staff identity, not a full revision comparison; do not claim or add full optimistic concurrency in this refactor. Keep existing reads and lock order. |
| Failure/rollback | Preserve preflight calendar rejection and the under-lock HTMX 409 with `HX-Refresh: true`. Under-lock native calendar failure follows its existing returned-error path. Do not turn a response exception into a returned `Left` inside the durable transaction. Write/outbox failures must still roll back the slot mutation. |
| Effects/provenance | `roster.slot.save`/`roster.slot.update` retain exact touched resources, including affected Timesheet resources. Current save/update do not write shift audit rows. Preserve actual actor on existing deletion effects; retain shared request provenance wherever effects already audit. Materialized Timesheet snapshots never change. |
| Completion data | Mutation result retains previous Staff and source-Timesheet warning. Move post-commit related-slot lookup/impacted-row derivation from the controller to the operation's completion preparation, keeping its timing outside the mutation lock. A projection failure after commit must not cause another write. |
| Response | [Responses](../../Web/RosterWeeks/Responses.hs) owns completion construction; [Projection](../../Web/RosterWeeks/Projection.hs) remains the one layout decision owner. Preserve row/day-column/timeline fragment selection, `HX-Reswap: none`, dialog-clear before optional warning, and update's deliberate **absence of success toast**. Published fill suppresses the warning as today. Create/duplicate/assignment retain their native redirect branch; update/move must not gain one. |

Rejected forms retain current draft-specific versus Published value restoration:
Draft persistence failure rebuilds from the attempted slot; Published failure
rebuilds from the original slot. Returned completions contain semantic impact,
not a callback for controller-side querying or a new HTML/live planner. The
response owner may continue the existing view-dependent mounted projection work;
business read models remain [DirectReadModel](../../Web/RosterWeeks/DirectReadModel.hs)
and [RenderData](../../Web/RosterWeeks/RenderData.hs), not a new cache.

### Characterization at the seam

[Roster pilot #512](https://github.com/BeaudanBrown/ihp-roster/issues/512)
owns the create/edit/Published-fill cutover and exact completion-consumer map.
The proposed response seam replaces local builders for **all eight** consumers,
including response-only move/drop/delete paths; it does not redesign those
operations or leave a second wrapper layer.

[WorkflowSpec](../../Test/Controller/RosterWeeks/WorkflowSpec.hs) is the
shift-operation oracle; [FragmentsSpec](../../Test/Controller/RosterWeeks/FragmentsSpec.hs)
and [RosterInteractionWorkflowSpec](../../Test/RosterInteractionWorkflowSpec.hs)
are the projection/interaction oracles. Necessary pre-movement characterization:
combinations of deleted/foreign slots and malformed context; omitted
versus blank protected fields; stale calendar/publication/Staff while waiting for
locks; sparse existing-cell reuse/row growth; failure after slot write or outbox
publication; and exactly one successful concurrent Published fill. Assert actual
rows/resources and independent response markup/headers, not only helper calls.
For all eight response consumers compare native/HTMX, each layout, exact warning
and toast absence/order, and actor/passive convergence. Preserve public-interface
acceptance while moving tests of replaced coordination to the new operation seam.

## Provider design: owner Checkout, status and completion

### Interface and caller knowledge

The existing deep payment operation is
[startOrResumeBillingCheckoutMutation](../../Web/Billing/Mutations.hs). It takes
`StripeClient`, `StripeConfig`, venue, `ActualUser`, `EffectiveUser`, and the
attempt-specific success/cancel URL builders; returns
`LiveMutationResult CheckoutStartResult`. Keep that interface and the existing
[Checkout](../../Application/Billing/Checkout.hs) principal/outcomes. Do not
rewrite the payment engine to make it look like the ordinary-form pilot.

Proposed request-side interfaces in focused `Web/Billing/` owners:

```haskell
loadBillingStatus :: BillingStatusRequest -> IO BillingViewModel
finishBillingCheckoutRequest :: LiveMutationResult CheckoutStartResult -> IO ()

-- Status request: existing checkout-return query context after IHP adaptation.
-- Viewer/venue authority comes from current context, not a submitted audience.
-- Completion: rejected feedback, correlated pending return, or validated
-- hosted redirect with the existing successful-start audit before response.
```

Before: [Billing controller](../../Web/Controller/Billing.hs) owns audience
queries, return correlation/classification, the provider operation call and
completion branch assembly. After: it keeps access/strong-auth/email gates,
config/client and URL adaptation, the existing operation call and feature
response selection. The read-model owner hides audience/query/correlation
coordination; the completion owner hides URL validation, existing audit timing
and HTTP branch assembly. These remain Web request-side roles, not provider
transport code in a view. No new transaction or callback effect interface is
passed by the controller.

### Owners and preservation matrix

| Concern | Owner and behavior to retain |
| --- | --- |
| Access/inputs | Existing `ensureBillingAccess`, `ensureOwnerBillingPaymentAction`, shared strong-auth policy and verified effective-owner email gate. Owner status does not require fresh step-up; payment does when enabled. Unimpersonated support has no payer authority; impersonated owner pays as effective owner while actual founder remains actor. |
| Preparation transaction | `Application.Billing.Checkout.startCheckout` with the Web mutation's existing transaction runner locks the venue, rechecks subscription eligibility/open attempt, resolves Price and creates/reuses Customer, writes the attempt and commits **before Session creation**. Customer creation itself is already a provider call during preparation; never describe this as a provider-free phase. |
| Execution transaction | `executePreparedCheckout` reacquires venue lock, rechecks eligibility and the current open attempt/mode, then creates or retrieves the exact Session under the current serialization. Expiry/restart commits the expired attempt and newly prepared replacement before recursively executing. Retain one-open-attempt and stable venue-Customer/committed-attempt Session idempotency. |
| Failures | Provider create/retrieve errors and invalid responses may commit sanitized attempt diagnostics. An escaping execution exception rolls back that phase, **not** the already committed preparation. A retry uses the same durable attempt key. No universal transaction across the operation, and no retry of a whole HTTP response after commit. |
| Effects/provenance | Web mutation's existing focused phase runner attaches `billing.checkout.prepare`/`billing.checkout.execute` publication only when its selector says so. Customer-created audit stays inside preparation. Successful-start audit stays after committed operation and exact hosted-URL validation, before redirect; awaiting/rejected/invalid-URL branches do not gain that audit. Principal separates actual actor from effective payer/email; central audit retains session/source. |
| Projection/correlation | Proposed read-model owner preserves current-venue queries. Founder diagnostics fetch the existing recent-attempt/event/reconciliation lists with their current descending order and limit 5; owner does not query those lists. Preserve customer-safe projection and configuration-unhealthy display. Return parameters only locate local correlated attempt/Session/event/Subscription; never confirm payment from a browser flag. |
| Completion | Keep all `CheckoutStartRejected`, `CheckoutAwaitingWebhook`, `CheckoutSessionReady` branches, absent URL error, exact HTTPS Stripe-host validation, safe copy and correlated owner progress URL. Hosted HTMX success uses `HX-Redirect` plus empty text; native success redirects. Errors retain flash + Billing redirect even for HTMX; do not "standardize" them into toasts. |

The rank-polymorphic phase runner and customer-created callback already between
Web mutation and Application Checkout are **existing focused integration seams**.
Keep them internal to this provider composition; neither generalize them into
feature effects nor copy them into workbook/roster interfaces. Concrete
`StripeClient` remains the production/mock adapter seam.

### Signed ingress and other request variants

[StripeWebhooks controller](../../Web/Controller/StripeWebhooks.hs) is public,
not an authenticated-venue action. It reads raw body/signature, loads config,
verifies the signature **before JSON parsing**, then calls
[Webhook](../../Application/Billing/Webhook.hs) through the existing durable
transaction. Provider correlation resolves venue; no browser current membership
or payer principal may be required. Preserve config/processing failure 500,
signature/payload rejection 400, successful/duplicate `ok` after commit, event
ID deduplication and ordering. A duplicate with a resolved venue can still emit
the current convergent invalidation; do not remove that event as a generic no-op
optimization. Payload failures and exceptions must retain their current write
and rollback behavior, not be swallowed by a universal result handler.

Page and plain fragment share authorized status loading; `SurfaceImpl` stays
fragment authorization authority. Form/dialog responses retain submitted values
rather than refetching success data. Private preferences (for example
`UpdateRosterOwnLiveShiftHighlightPreferenceAction`) use effective-user
[UserPreferences](../../Application/Helper/UserPreferences.hs), existing local
actor refresh and their current native fallback—not a fabricated shared business
resource or mandatory venue-writability transaction. Portal remains a separate
existing recovery path with fresh per-request idempotency; return/reconciliation
continues to enqueue the shared job, not make provider writes. These variations
fit the roles without a universal action-result sum or policy flags.

### Characterization at the seam

[Billing work #517](https://github.com/BeaudanBrown/ihp-roster/issues/517)
owns focused read-model/response extraction, **not** provider phase or webhook
rewriting. [BillingSpec](../../Test/Controller/BillingSpec.hs) is the
request/completion oracle, including interrupted-provider and concurrency cases.
[BillingPersistenceSpec](../../Test/BillingPersistenceSpec.hs),
[BillingWebhookSpec](../../Test/BillingWebhookSpec.hs) and
[BillingReconciliationSpec](../../Test/BillingReconciliationSpec.hs) remain
independent local/provider oracles. The extracted seam needs characterization of
query ordering/limits, every return outcome and
native/HTMX completion (including missing URL), exact audit/publication counts,
and unchanged owner HTML/privacy. Keep the existing interrupted-provider and
concurrency tests as independent phase oracles; do not replace them with mocked
whole-workflow success. No real Stripe credentials or Sandbox writes are needed.

## Verification and promotion

This design does not claim runtime equivalence. Validate all source/interface
references and run `bash ./bin/in-env ./bin/doc-drift-check` for the document.
Before implementation movement, record an unchanged-source baseline on the issue;
keep temporary logs/query diagrams under `.pi/tmp/` or ignored output, not here.

For fresh architecture evidence, first validate `dev-workspace-info --json` and
`haskell-generated-ensure`, then run `architecture-facts` through `bin/in-env`.
Use the configured `module` queries for `Web.Exports.Mutations`,
`Web.RosterWeeks.ShiftWorkflow`, `Application.Billing.Checkout`, and `request-flow`
for `UpdatePayrollWorkbookConfigurationAction`, `UpdateRosterSlotAction`,
`CreateBillingCheckoutSessionAction`; run `conventions` with
`failOnViolations=true`. Static request-flow calls/responses are heuristic:
confirm transaction/auth/effect claims from source/tests, not inferred edges.
Missing generated/runtime evidence is a recorded limitation, never stale facts.

These focused commands identify the test surface for the proposed seams, not a
completion checklist; the linked implementation issues own required evidence.
Repeated Hspec matches are OR filters:

```bash
# Workbook pilot: persistence, request flow, onboarding and independent output.
bash ./bin/in-env hspec-test --match "Payroll Workbook" --match "Exports" --match "Users" --match "Fixed export goldens"
bash ./bin/in-env e2e e2e/exports-payroll-downloads.spec.ts e2e/exports-authz.spec.ts

# Roster pilot: all completion consumers, interaction and live semantics.
bash ./bin/in-env hspec-test --match "RosterWeeks" --match "RosterInteractionWorkflow" --match "MutationBoundary" --match "DurableLiveInvalidation"
bash ./bin/in-env e2e e2e/roster-live-fragments.spec.ts e2e/roster-time-picker.spec.ts e2e/roster-mobile.spec.ts e2e/live-fragment-multiview.spec.ts

# Billing read/response work: retain provider and audience acceptance.
bash ./bin/in-env hspec-test --match "Billing" --match "Stripe" --match "DurableLiveInvalidation"
bash ./bin/in-env e2e e2e/billing.spec.ts
```

[Root verification guidance](../../AGENTS.md#verification) and the epic own
broader gates, memory, serial-wrapper and runtime-identity requirements. Focused
checks cannot replace complete Hspec, typecheck/reachability, generated/frontend
or architecture authority; the combined rollout requires `verify-full` and
affected browser acceptance. Each child must prove its seam independently.

Constructor names, exact error grouping and private placement remain provisional.
Pilots must demonstrate less caller knowledge without reordering checks, adding
queries/effects, changing HTTP exceptions, or weakening typed wire authority.
Keep small domain-shaped inputs/completions; do not expose prepared records,
policy Booleans, raw dictionaries, or queries merely to make a controller short.
A proposed improvement that changes observed behavior needs separate approval.

Promote only proven extension rules into
[controller guidance](../../Web/Controller/AGENTS.md),
[Exports ownership](../../Application/Helper/Export/README.md),
[Roster ownership](../../Web/RosterWeeks/README.md) and
[Billing ownership](../../Application/Billing/README.md) with their local
AGENTS/SPEC as applicable. Those current documents are not rewritten as though
this proposal already landed. Reconcile/remove this workstream once no unresolved
design remains; use an ADR only for a consequential durable decision. Do not
expand into Timesheet/Unavailability product changes, auth redesign, schema
retirement, XLSX renderer splitting, a generic live dispatcher, or issue #212's
FrontendContract semantic-test cleanup.
