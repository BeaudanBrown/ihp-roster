# Daysheet experience redesign — discussion draft

Related implementation and acceptance context: [#630](https://github.com/BeaudanBrown/ihp-roster/issues/630) and [#642](https://github.com/BeaudanBrown/ihp-roster/issues/642).

This is a proposed design for discussion, not implementation authorization or an amendment to the approved Daysheet contract. GitHub owns implementation scope and status. The initial scope is the complete Daysheet experience; unrelated Bepis workflows are not being redesigned.

## Thesis

Keep the existing financial and concurrency engine. Replace the interface that exposes its underlying structures with an interface organized around people's tasks.

The current screen combines entering figures, configuring definitions, inspecting results, publishing, capturing and sending. Adding better spacing cannot fix that information architecture. Equally, replacing the engine or adding a browser-side state/evaluation system would incur risk without solving the observed problems.

The desired outcomes are:

- A manager can enter a day's figures, see what is unsaved or needs attention, review the result, and submit without understanding the configuration engine.
- An administrator can adapt a template and understand the consequences before publishing, without navigating a giant inventory of controls.
- A reader can distinguish live results from retained reports and understand whether anything was actually sent.

## Agreed direction from design interview

- Desktop-first: figures are mainly entered and reconciled at a workstation.
- Area-first: finish one area's figures before moving to the next.
- Show one selected area at a time, rather than a continuous display of every area.
- Area selection is navigation only. There is no per-area completion state or submission; retain one shared Daysheet submission.
- Allow switching areas with failed saves or conflicts while retaining exact unsaved input. Flag affected areas and keep a whole-Day warning with a direct return to the problem. Final submission/capture remains gated on resolving pending edits.
- Area-bound lists have area-specific creation actions. For example, Beer Garden's Add cash-out action can create only a Beer Garden entry. There is no area picker; the server enforces the scope rather than merely prefilling a field.
- An area-bound record's area is fixed after creation. Correct the wrong area by explicit deletion and deliberate creation in the correct area, retaining deletion/dependency safeguards. Do not introduce a move action or allow a generic edit to bypass the fixed scope. This is a behavioral constraint beyond presentation grouping; its reusable definition/validation representation still needs design.
- Manually added entries use an inline Add/Cancel form: opening it creates nothing, Add saves the entered values together into the fixed area's list, and Cancel creates nothing. This does not introduce mandatory completion of every field.
- Existing manually added entries use whole-entry Edit/Save/Cancel rather than per-field autosave. The save is atomic so a changed reason and amount are not published separately.
- Any concurrent change to the entry being edited stops its save for explicit review. Retain the draft and show the latest saved entry; do not automatically merge even non-overlapping fields. Changes to other entries do not cause a conflict.
- Fixed cash-count, POS and terminal-reading checklist figures retain field autosave and independent cell conflict handling.
- Keep the selected area's reconciliation summary visible beside its inputs, based on acknowledged saved values rather than optimistic unsaved calculations.
- A separate **Whole day** view alongside the areas holds combined totals, cross-area comparison and shared daily notes. It is not a required final step.
- Grouping is explicitly admin-configured and supplied by the starter: select the reference list furnishing navigation items and configure how displayed records belong to those items. Do not infer grouping from names or silently hide unmatched records.
- Admins explicitly select area-summary figures and advisory checks, with the starter supplying an initial selection. Do not automatically expose all intermediate calculated fields or introduce separate summary calculations.
- The operator confirms there are no existing customer Daysheets to migrate. Design the initial experience directly; historical UI rollout is not a workstream. Capture preservation remains an invariant once the system is in use.
- Configuration is preview-first: select visible sections, fields or summaries to open focused editors; retain searchable advanced inventories.
- The designer has distinct **Edit layout** and **Test entry** modes. Test entry accepts isolated sample figures and uses the real calculation engine, with no real daily creation, submission, capture or sending. Retain compatible sample values between modes; incompatible values need explicit correction, not silent conversion. Publication excludes sample values.
- No designer Undo/Redo. Use explicit Save/Cancel per editor and manually reverse saved configuration changes.
- Publication requires a change-review screen followed by explicit Publish. First publication reviews what is introduced; subsequent reviews compare with the published version. Another admin changing the draft invalidates the reviewed revision and requires refreshed review. Using sample data is optional, not a publication gate.

These decisions refine the proposed experience below. They do not authorize implementation. The existing single-page contract must be reconciled explicitly with selected-area presentation; the intended approach is in-page selection, not separate area records or a completion wizard.

## Retain these contracts

- One shared venue/Operational-day Daysheet. Daily entry remains one page, not a paginated wizard or separate area-owned records.
- Explicit creation and submission. Submission remains editable afterward; it neither freezes results nor sends mail.
- Missing input is not zero. Advisories and incompleteness are informational, not new submission/send gates. Only existing authority, submission and unsettled-edit requirements block the relevant actions.
- Exact arithmetic, explicit rounding, bounded calculations, selected-content reports and escaped/non-executable output.
- Immutable captured definitions, references and frozen report content. Future publication must not reinterpret existing Daysheets, including drafts.
- Existing venue, founder and effective impersonation authority; no UI affordance becomes authority.
- Existing revision checks, dirty-form owner, save acknowledgement, conflict recovery, capture identity, cutoff policy and delivery pipeline.
- Native form recovery and accessible alternatives to pointer interactions. JavaScript enhances presentation and interaction, not domain meaning.

## Proposed experience

### 1. Daily workspace: enter and review

Use a compact header containing operational date, submission state and save state. Separate the concepts visually: **Draft/Submitted**, **Saving/Saved/Needs resolution**, and **report capture/delivery** are not interchangeable statuses.

The body starts with useful work, not a stack of configuration/export buttons. Use area navigation to show one area's related cash, POS and terminal entry at a time within the shared Daysheet. This is navigation, not an area-completion workflow. Navigation and live refresh must retain input, focus and scroll context. Unsaved/conflicting edits in other areas must remain discoverable; switching areas must not discard or falsely acknowledge them. Keep the explicitly selected area-summary figures and checks beside entry, and put shared information and combined totals in a separate **Whole day** view. Summary calculations use the existing authoritative evaluation of saved data. Mark pending edits clearly so old saved totals are not mistaken for a calculation incorporating those edits.

Use a compact secondary Reports action and a permission-aware Settings action. Preserve access to preview, export, capture/send and history without repeating every report/output combination above the inputs.

Prioritise desktop keyboard entry and aligned comparison within the selected area. Mobile must remain usable without dictating desktop density. Its exact presentation remains open; avoid hidden desktop and mobile copies of editable forms.

There must be one editing owner per cell occurrence, not hidden desktop and mobile copies of the same form. Repeated authored occurrences retain their existing synchronization semantics.

Show entered values differently from calculated values. Keep accessible labels, but avoid repeating visible labels below identical desktop column headings. Reduce always-visible Save clutter only when acknowledged autosave is available; retain explicit-save fallback, keyboard operation and retry/error controls.

A non-blocking review summary should distinguish missing inputs, advisory concerns and unsaved/conflicting edits. These are different kinds of attention, not one red error count. Do not invent a completion percentage: the definition currently does not establish that every input is required.

### 2. Report workspace: inspect, capture and deliver

Provide one discoverable place to select a configured report and inspect its current saved preview, available export and frozen history. A report selection must respect its configured outputs. Keep live and frozen views unmistakable, with operational date, source/capture identity and labelled timestamps.

Render financial summaries compactly, and make existing advisory outcomes easy to see. Do not infer financial importance or danger from a field name, a negative number, or text such as “Shortage.” Any new emphasis policy must be explicit and server-owned.

Mobile tables must preserve readable values and row identity. They must not shrink into letter-wide columns. Selected-content restrictions apply equally to row cards: a renderer cannot fetch hidden fields merely to improve their titles. If meaningful advisory row labels need new authored selection, make that an explicit, versioned enhancement rather than silently discovering source labels.

Confirmation should answer four questions first: which day/report, which saved state will be captured, which recipients, and what the action does. Put detailed retry/transport explanations behind accessible secondary disclosure without removing safety-critical warnings.

With no recipients, use capture-only wording. With recipients, distinguish capture from queued/attempted/provider-accepted/delivered states. A single green “Sent” badge must not conceal the existing independent queue/provider facts. A fresh confirmation deliberately creates a new run; retries reuse its identity.

Keep recipient administration separate from the primary manager task, while showing the current configured recipients in confirmation. Capture must still recheck them under the existing authority/transaction rules.

### 3. Configuration workspace: configure, preview, publish

Replace the single designer inventory with focused navigation:

- **Overview:** published/draft state and the next configuration task.
- **Venue reference data:** areas, registers, terminals and other authored reusable lists.
- **Fields and calculations:** entered/calculated distinction, types and dependencies.
- **Daily entry layout:** authored section and field placement.
- **Reports:** content selection, layout, output settings and a clear route to recipient administration.
- **Review and publish:** change summary, affected dependencies and future-only effect.

These are views over the existing public definition model, not a second simplified template model. Keep all existing capabilities accessible. Use focused editing with one dirty form at a time; URL navigation should preserve selection and return context.

Calculation editing should show a readable whole-expression summary, the selected part, its type and available compatible replacements. Keep the server's valid-by-construction choices and explicit constant editing. Do not introduce free-form scripts, a JavaScript evaluator or a parallel formula document.

Layout editing should show the authored outline alongside a responsive preview. Start with reliable keyboard/native move controls rather than assuming drag-and-drop is necessary. Any future drag interaction must call the same typed edits.

A preview against synthetic sample data should be clearly labelled and must not create a real Daysheet, mutate venue records or send reports. Previewing unpublished definitions needs a deliberate pure evaluation path; the current saved-day preview is not a substitute.

For onboarding, lead through reviewing the starter's reference records, settings and financial assumptions, then preview and explicit publication. Do not claim provider certification or silently install/publish a template.

## Refactoring seams

### Shared meaning, separate renderers

`Application.Daysheet.Saved` and `Report` already supply useful deep modules: entry and reporting reuse authoritative evaluation; the selected report contains no hidden source document. Preserve those interfaces instead of creating a new client data model.

The current `Application.Helper.View.DaysheetReport.renderReportContent` is used by both browser views and `Web.Mail.DaysheetReport`. That is a real seam with two different rendering needs. Separate browser presentation from email-safe rendering while sharing selected content and plain-text/value semantics. XLSX remains its existing values-only adapter. Do not make emailed reports depend on application CSS, sticky controls or interactive disclosure.

### Context-aware entry presentation

`Web.View.Daysheets.Cell` currently renders a standalone field form even inside every table cell. Give entry presentation a small, typed context for labels/layout while keeping form identity, revision, save acknowledgement and conflict handling under the existing owner. Avoid a sprawling collection of unrelated display flags.

`Web.View.Daysheets.Index` currently assembles every report action and all entry content in one stack. Separate the workspace header/navigation from authored section rendering, without spreading authorization or final-action gating among callers.

### Focused designer navigation

`Web.View.Daysheets.Designer` currently renders all fields, lists and layouts on its index. Introduce focused, server-selected designer views and corresponding generated route/fragment contracts. Keep `Storage` and `Designer` as mutation authorities. Merely splitting the 488-line view into several files would not reduce the interface users must understand.

### Presentation is not permission to change retained meaning

First prefer improvements derivable from existing typed values and layout structure. Additional primary-row labels, display roles or presentation metadata are separate design decisions. If needed, define them in the Haskell-owned contract, generate browser controls and provide version-aware decoding and preservation tests.

Improve ordinary amount/date presentation only after deciding precision and historical behavior. Do not silently round exact calculated money to cents or reformat retained frozen display text under new business rules. Generic responsive styling can improve historical readability without changing captured content/order/meaning.

## Proposed implementation order

1. **Agree the daily working model and create representative prototypes.** Compare desktop entry, phone entry and report reading using populated, incomplete and conflicting states. Include designer navigation before committing to its structure.
2. **Establish the browser/email rendering seam and fix report readability.** Preserve selected-content equivalence and retained values; address mobile table collapse, spacing and accessible numeric alignment.
3. **Rework the daily workspace.** Compact header, section navigation, context-aware cells and save/error visibility; preserve concurrent editing and native recovery.
4. **Unify report discovery and clarify capture/history.** Consolidate actions and simplify decision-making without replacing capture/delivery semantics.
5. **Rework configuration around focused tasks.** Navigation, dependencies, readable calculations, layout preview and publication review. Add new presentation metadata only where agreed prototypes demonstrate a real need.
6. **Integrated acceptance.** Recheck realistic maximum starter data, unusual valid custom templates, historical definitions and old frozen reports, role variants and channel-specific rendering.

These are sequencing recommendations, not newly assigned GitHub tasks. After the design is agreed, publish a bounded issue graph rather than silently extending the current acceptance issue.

## Acceptance that goes beyond passing functional tests

- At agreed desktop and phone viewports, the initial entry screen shows meaningful daily work and its save/submission context, not only navigation.
- Monetary values and identifiers remain readable; mobile table headings do not become vertical character stacks.
- A manager can find and resolve a conflict without losing typed content, section position or row context, including during passive live refresh.
- Missing input, zero, advisory concern, unavailable calculation and unsaved edit remain distinguishable.
- Selected report content is equivalent across applicable browser, frozen history, email and XLSX paths; hidden fields do not leak through improved labels.
- A current draft, submitted editable day and frozen capture are visually and behaviorally distinct. No capture is described as delivery without supporting facts.
- An admin can locate a field, understand its use, edit one calculation and review publication without scanning the entire definition.
- Keyboard, zoom, narrow viewports and no-JavaScript recovery receive explicit checks. Inspect real screenshots at agreed checkpoints; do not replace visual acceptance with text/DOM assertions alone.

## Questions to resolve iteratively

Start with the first question; do not require every decision at once.

1. Resolved working model: desktop-first, area-first, one selected area visible, navigation only with one whole-Day submission. Next determine whether area reconciliation stays visible during entry or has a separate review view.
2. What deserves immediate attention in the manager's first screen: data entry, variances, operational notes, or a combination? Keep the answer configurable where it represents venue-specific meaning.
3. How much routine configuration should be guided for nontechnical venue admins, versus performed with founder assistance? This affects onboarding and editor priority, not permission.
4. Should readable mobile record views be automatic, author-selected, or a reader toggle? What identifies a row when no report-visible identifying field is selected?
5. Should this iteration add explicit summary/emphasis/row-label metadata, or first improve presentation with the existing contract only?
6. What publication comparison and synthetic draft preview is necessary for confidence, and what precision/display rules may change for future output?

## Living documents affected after decisions

Update `specs/07-daysheets.md` only for approved product-contract changes. Retain engineering interfaces and invariants in `Application/Daysheet/{README,SPEC}.md`, view/interaction owner notes and generated surface definitions. Record consequential architectural decisions separately where warranted. This workstream remains unresolved design, not a replacement acceptance checklist or implementation tracker.
