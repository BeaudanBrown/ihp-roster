# Configurable Daysheets

## Status And Authority

V1 product scope is locked by the design-session approval. This is agreed
product and acceptance intent, **not implemented behavior or approval to start
implementation**. The worked examples below make agreed rules concrete; the
final section explicitly identifies details still requiring clarification.

[Domain language](../CONTEXT.md), [access control](03-access-control-and-auth.md),
and [data governance](02-domain-model.md#governance-and-data-classes) continue to
apply. Custom fields do not waive restrictions on sensitive-data collection,
exports, or security-sensitive audit events.

Bepis will use a custom implementation rather than adopt an external form-builder
or reporting platform for now. This does not prohibit ordinary implementation
libraries. The product is a reusable venue-configurable system, not a hard-coded
copy of one venue's spreadsheet.

## System Contract Versus Starter Template

The system contract applies to every configuration: venue authority, typed and
bounded calculations, preserved historical definitions, shared-day identity,
report snapshots, and the workflow described below.

The supplied starter template replaces the detailed workflow represented by the
local, untracked reference workbook `daysheet-template.xlsx`. The committed rules
and acceptance examples below retain the agreed contract; verification must not
require that local workbook. The template must be expressible entirely through
the same fields, lists, formulas, checks, and layouts available to venue admins. No hidden
venue-specific calculations are permitted. If its agreed workflow cannot be
expressed, the reusable primitives need improvement rather than a special case.

The starter template's financial choices are **not universal engine restrictions**.
Venues may model deposits, floats, multiple surcharge rates, split-terminal
allocations, or band-derived ticket amounts using the approved primitives.
Bepis does not provide specialised workflows for those variations in v1.

## Authority And Daily Identity

- One shared Daysheet per venue per Operational day, not a separate sheet per area.
- The Operational day runs from 06:00 venue-local time through the following
  05:59, consistent with existing domain language.
- Managers, admins, and owners may view, edit, submit, preview, download, and
  manually send the whole Daysheet, including financial figures. Workers have
  no access. Section-specific permissions and separate contributor roles are
  outside v1.
- Only admins and owners manage definitions, venue reference lists, layouts,
  report configurations, and recipients. Ordinary business authority comes from
  current venue membership; existing platform-support rules remain separate.
- An authorised manager, admin, or owner explicitly starts a Daysheet for a
  selected Operational day, defaulting to the current day. Viewing does not
  create one; there is no automatic daily creation. Concurrent creation must
  preserve the single shared venue/day identity.

## Builder Primitives

### Fields

The initial closed set of value types is:

| Type | Meaning |
| --- | --- |
| Text | Plain text, not rich text |
| Yes/no | Boolean value |
| Choice | A configured choice |
| Whole number | Integral quantity |
| Decimal number | Numeric quantity distinct from money |
| Money | Monetary value, distinct from an ordinary number |
| Percentage | Rate, distinct from an ordinary number |
| Date | Calendar date |
| Operational-day time | A time resolved against the Daysheet, including overnight entries |
| Single-record reference | One linked record in an allowed list |

All Money fields use Australian dollars in v1. Entered money has whole-cent
precision; intermediate calculations retain precision until an explicit
configured rounding step rather than rounding after every arithmetic operation.
Multiple currencies and currency conversion are outside v1.

Entered and calculated fields use the same value types. Repeating lists are
containers, not additional field types. File uploads, rich text, multi-record
references, and custom user-defined types are outside v1.

### Records And References

**Venue reference lists** hold reusable venue records, such as Areas and
Terminals. Admins and owners can define custom lists with the same primitives.
Venue records can reference other venue reference lists, such as a terminal's
area. Referenced entries are retired rather than destructively removed.
Retirement affects newly created Daysheets only: they capture active entries
and omit retired entries from new reference checklists. Existing Daysheets,
including drafts, retain their captured entries, references, and checklist rows
unchanged. Before retirement completes, active records referencing the retiring
item must be explicitly reassigned or retired as part of the same operation.
Show the affected items and require the admin/owner's choices; never silently
retire dependants or leave broken references. Existing Daysheets remain untouched.

**Daysheet record lists** hold daily records owned by one Daysheet, such as
receipts, cash-out entries, performances, and readings. Lists are named and flat.
References may target venue records or records in another list on the same
Daysheet, never records on another Daysheet. Layouts may visually group linked
records without nesting their underlying data.

Daily lists support two modes:

- **Open list:** managers add rows as needed.
- **Reference checklist:** exactly one automatically created row per entry in a
  selected preserved venue reference list. Managers fill the fields but cannot
  duplicate or remove checklist rows.

Deleting an open-list daily row may clear references to it after explicit
confirmation showing the affected entries. Referencing rows and their other
values remain intact; they are never automatically deleted. Delete the selected
row and clear its incoming references atomically. If dependencies change before
confirmation is applied, refresh the confirmation rather than silently expanding
the operation. An intervening edit to the target row also invalidates the
confirmation; show the updated row for fresh approval. Saving a stale edit to an
already-deleted row retains the editor's unsaved input without automatically
recreating the row. The manager must deliberately decide what to do next.
Calculations requiring a cleared reference become unavailable, not silently zero. Managers can assign a new reference later. This does not
permit deleting checklist rows or destructively removing venue reference data.

### Calculations And Advisory Checks

Admins and owners build calculated fields using restricted typed building
blocks: references, arithmetic, filtered/grouped sums, percentages, explicit
rounding, and typed comparisons/conditions. The designer is guided, not a
free-text formula editor or arbitrary scripting environment.

Construction must be valid by construction:

- Only compatible fields and operations are offered.
- Dependencies that would create a calculation cycle cannot be selected.
- Changing or deleting a definition cannot leave dependent calculations broken.
- Server-side validation remains mandatory for untrusted requests; the UI is not
  the security boundary.
- Evaluation is bounded. Arbitrary scripts, loops, and user-defined functions
  are outside v1.

Calculations may read the current Daysheet, its other daily lists, and preserved
venue reference data only. No cross-day calculations, live payroll dependencies,
or external-data dependencies. Cross-day reporting and integrations require a
separate design.

A result is either a known typed value (including zero), or **unavailable with a
plain-language reason**. Missing inputs/references, division by zero, and
operations without an empty-list result do not produce invented zeroes.
Unavailability carries through dependent calculations. Empty-list behavior is
operation-specific: an empty cash-out sum is zero; an empty average is unavailable.

Calculated fields are read-only during daily entry. Managers correct source
entries or use an explicitly configured adjustment field, never overwrite a
calculated result.

An **advisory check** uses typed comparisons/conditions and a plain-text message
configured by an admin or owner. Its result derives from saved values and has
three visible outcomes: Passed, Concern, or Not evaluated. Unavailable required
inputs produce Not evaluated with a reason, never a pass or a false financial
concern. Show compact status text beside the relevant field or section, not a
pop-up. Concerns are prominent; passed checks are quiet. Use text rather than
colour alone. Checks do not block submission or sending. Structural validity
and permissions remain mandatory safeguards, not advisory checks.

### Layouts And Outputs

Entry forms and reports use structured blocks: ordered sections, plain-text
instructions, individual fields, summary values, and record tables, with grouping
and ordering controls. Their layouts may differ but reference the same data and
calculations. No independent report formulas or separate copies of entered data.
Free-positioned and pixel-perfect canvases are outside v1.

Initial report output targets are formatted email/browser reports and downloadable
Excel workbooks, selectable by admins and owners per report. Excel contains
selected values and tables; calculated results are exported as values, not
executable spreadsheet formulas. Scheduled and manual emails contain the
configured formatted report without attachments; Excel is download-only.
Other output formats and user-authored renderers are outside v1.

Each selected top-level report section becomes one Excel worksheet, in report
order, containing only that section's selected summaries and tables. Do not add
hidden raw-data sheets or unselected fields. Include Draft/Live or frozen-report
capture identification in the workbook. Represent unavailable results and
advisory statuses explicitly, never silently as zeroes.

## Definitions And Historical Meaning

Admins and owners draft changes and explicitly publish a definition version.
The version includes fields, calculation rules, and entry/report layouts.

Explicit Daysheet creation pins the then-published definition and captures venue
reference data. Later publication applies only to newly created Daysheets.
Existing drafts and submitted Daysheets retain their original definitions,
layouts, and reference meaning. Migrating an existing Daysheet to a newer
definition is outside v1.

Recipient lists are separate delivery settings. Changing recipients does not
require publishing a new definition.

## Daily Editing And Submission

Managers use ordinary forms, not builder controls. Independent field edits must
preserve each other's changes. A stale edit to the same field is held for the
second editor to compare with the saved value. Their unsaved value remains
visible until they deliberately keep the saved value or replace it. No silent
last-write-wins behavior.

Daily-content history in v1 consists of last-edited metadata and frozen reports,
not a manager-visible per-change before/after history or restoration workflow.
Existing security-sensitive audit obligations are not removed.

A Draft has not been explicitly submitted. Submission declares the Daysheet
complete but does not lock editing or require every field to be filled.
Reopening and correction-approval workflows are outside v1. Passing a time cutoff
does not submit a Daysheet.

Submit and Send wait until the initiating manager's pending local edits are
saved and conflicts resolved, then operate on one consistent saved state. Do
not silently act on older values because a save is pending. A report includes
other managers' edits saved before capture; edits saved afterward affect only
the live Daysheet. This does not make intentionally blank fields or advisory
concerns blockers, and submission itself does not create a report snapshot.

## Reports And Delivery

Each configured report has its own recipient list. Recipients may be external
email addresses without Bepis accounts. Only admins and owners change report
content selection or recipients.

### Scheduled Send

- At 6am venue-local time, report on the previous Operational day.
- If unsubmitted, silently skip. No overdue notification or automatic catch-up.
- Submission is the sole business eligibility condition: no revenue threshold,
  completeness gate, or advisory-check gate.
- Capture a fixed report snapshot for that cutoff. Later live edits do not
  rewrite it or trigger an automatic correction email.
- Retry delivery using the captured snapshot, not newer data.
- If no cutoff snapshot was captured, skip the scheduled report rather than
  inventing a historical snapshot from current data. A captured report may retry.

### Manual Send

Managers, admins, and owners may send an existing configured report to its
configured recipients only. Managers cannot add addresses, change content
selection, or bypass that recipient boundary.

Manual Send requires submission: it overrides timing only. It captures current
saved data as a new frozen report, clearly dated with its actual capture time.
It neither resends nor replaces the cutoff report. Earlier reports remain
unchanged. Corrections to a submitted Daysheet can be sent without reopening it.
Repeated attempts of the same Send action, including double clicks and browser
retries, reuse one report and delivery run. Show the existing run's status;
a genuinely new send requires a fresh deliberate action. This prevents duplicate
runs from request handling, not all uncertainty at the email provider.

### Transport And Retry Semantics

Reuse the [shared email delivery pipeline](../Application/EmailDelivery/SPEC.md)
and its existing retry policy; do not create a separate Daysheet transport.
Email delivery is at-least-once: provider acceptance followed by a worker failure
before success is recorded can result in duplicate receipt on retry. Document
this limitation; request-level deduplication does not promise exactly-once
email. Retries use the same frozen report and respect recipient removal. Expose
delivery status without treating provider acceptance as proof of inbox delivery.

Each Daysheet shows report-send history with capture time, scheduled/manual
origin, sender where applicable, and per-recipient delivery status. Distinguish
queued/retrying, provider-accepted, confirmed delivery where available, failed,
and skipped/cancelled. This is delivery history, not per-field edit history.
Managers can deliberately send a fresh report after failure; no new alerts,
overdue notifications, or automatic catch-up are introduced.

### Recipients And Viewing

The scheduled cutoff captures intended recipients. Removing an address later
cancels unsent deliveries and retries to it; the same removal rule applies to
manual sends. Adding an address does not send old reports automatically.
Already-sent email cannot be recalled.

Managers, admins, and owners can preview and download current saved data before
submission, clearly labelled Draft or Live. Frozen sent reports remain separately
identifiable by capture time. A live export must not look like the earlier
emailed report. Submission gates email sending, not previews/downloads.

## Retention And Generated Files

V1 has no automatic age-based purge of saved Daysheets or frozen reports.
Generated Excel download files are temporary and use the existing export-expiry
lifecycle; expiry of a generated file does not delete its underlying business
record. This is an initial operational policy, not a permanent legal retention
schedule or a blanket application of payroll retention periods to all Daysheet
content. Venue closure, deletion requests, and legally required retention follow
the controlled governance process, not an automatic purge.

## Supplied Starter Template

### Venue Setup And Content

Areas, POS registers, EFTPOS terminals, and their area assignments are configured
by admins and owners. Inside, Beer Garden, and Amelia are example areas, not
engine constants. The starter assigns each terminal to one area for the entire
day and uses a single preserved venue-wide surcharge rate.

Terminal Receipts follows the reference-checklist pattern. Cash-out entries and
Bands are open lists. Initial content includes financial summaries, financial
comments, kitchen comments, general comments, bands, dB readings, and security
knockoff times. Existing manager/financial email concepts are the starting report
configurations, not fixed engine report types.

### Financial Meaning

The starter replaces detailed spreadsheet reconciliation, not just headline
summary entry. It covers denomination figures, POS totals, terminal receipts and
surcharges, and labelled cash-in/out entries.

- **Missing versus zero:** blanks mean not entered; explicit zero means checked
  and none. Dependent totals/variances remain visibly incomplete, including in
  reports. An empty Cash in / cash out list means none and contributes zero
  without a confirmation step.
- **Cash in / cash out:** that is the user-facing section name. Entries belong
  to an area and represent cash outside ordinary POS cash sales and the retained
  float. Cash-in increases expected counted cash; cash-out reduces it. Neither
  changes sales totals.
- **Cash count:** enter whole-number counts for each note denomination; Bepis
  calculates each denomination's monetary amount. Enter coins as one monetary
  total. Sum note amounts and the coin total to obtain counted cash. These
  entries represent cash after removing the retained till float; entry guidance
  must say so. No dedicated float or deposit workflow is supplied.
- **Customer cashout:** use the same cash-out list, with a customer-cashout
  distinction and terminal link. The matching money is already in the terminal
  receipt. Reduce expected physical cash once and exclude that amount from card
  sales. Do not enter a second standalone cashout amount.
- **Actual terminal card sales:** receipt total less separately reported surcharge
  less linked customer cashout. Use the terminal's actual reported surcharge,
  not the percentage calculation used for POS totals. For starter design, assume
  the EFTPOS report supplies input figures without performing the reconciliation
  calculations itself; Bepis owns those calculations. This is an operator-supplied
  working assumption, not verification of a provider's report semantics.
- **Expected POS card sales:** remove the configured surcharge percentage from
  each register's surcharge-inclusive card figure. Round each result to cents,
  with exact half-cent ties away from zero, then sum into area/venue totals.
  Preserve the rate on the Daysheet.
- **Independent reconciliation:** terminal figures provide actual card takings;
  POS figures provide expected card takings. Never substitute POS figures on the
  actual side or add both sides together as separate sales.
- **Variance:** actual minus expected. Positive means surplus; negative means
  shortage. Show explicit Surplus or Shortage labels, not just a signed number.
- **Sales breakdown:** POS-recorded sales drive the headline and area breakdown.
  Kitchen and ticket sales are portions of those sales; bar sales are the
  remainder after subtracting both. Actual takings and variances are separate.
  A shortage does not reduce recorded sales. Do not add the breakdown to payment
  totals a second time.

### Operational Information

Band information is informational in the starter. Financial ticket sales are
entered separately; presales and door information do not automatically create
additional daily receipts.

Security knockoff entries contain a guard label and finish time, interpreted in
the Operational day including overnight times. They do not create/update
Timesheets or affect payroll.

dB readings are a flexible list of time, numeric reading, and optional
location/note, not fixed hourly slots. No automatic noise-compliance judgments
or alerts; a recorded reading does not establish compliance.

## Worked Acceptance Examples

These examples specify observable results from agreed rules. They are not
claims of passing tests. Example amounts/rates are fixtures, not hard-coded
configuration. Variances use actual minus expected, with explicit surplus or
shortage labels.

### Financial Calculations

| Case | Saved input | Required result |
| --- | --- | --- |
| Note counts and coins | Three twenty-dollar notes; other note counts explicitly 0; coins 7.50, all after float removal | Notes 60; counted cash 67.50 |
| Cash expense | POS cash 500; cash-in 0; cash-out 50; counted cash 450 after float removal | Expected cash 450; no shortage; POS cash sales remain 500 |
| Extra cash | POS cash 500; cash-in 20; cash-out 0; counted cash 520 | Expected cash 520; no surplus; POS cash sales remain 500 |
| Shortage sign | Expected cash 500; counted cash 490 | Variance -10, labelled Shortage |
| Surplus sign | Expected cash 500; counted cash 510 | Variance +10, labelled Surplus |
| Customer cashout once | POS cash 500; one linked customer cashout 50; counted cash 450; terminal receipt 253.20; reported surcharge 3.20 | Expected cash 450; terminal sales 200; the same 50 is neither a sale nor a second cash-out entry |
| Independent card comparison | POS card figure 203.20 at 1.6%; terminal receipt 253.20, surcharge 3.20, linked cashout 50 | Expected and actual card sales both 200; combined sales are not 400 |
| Round before summing | Two registers each report 0.32 at 1.6% | Each yields rounded sales 0.31; combined sales 0.62, not aggregate-then-round 0.63 |
| Explicit intermediate rounding | Formula divides AUD 1.00 by 3, then multiplies by 3, then rounds to cents | AUD 1.00, not AUD 0.99 from prematurely rounding the division |
| Half-cent ties | Rounding operation receives 1.005 or -1.005 | Results 1.01 or -1.01 respectively |
| Sales breakdown | POS-recorded sales 1,000; kitchen 300; tickets 100; reconciled receipts show a cash shortage of 10 | Headline 1,000; bar 600; shortage 10 shown separately, not headline 990 |
| Missing surcharge | Terminal receipt 253.20; surcharge blank; linked cashout 50 | Terminal sales unavailable with a reason; not assumed 203.20 |
| Explicit zero surcharge | Same receipt and cashout, surcharge explicitly 0 | Terminal sales 203.20 |
| Empty cash-out list | No entries | Cash-out sum 0, no explicit none-confirmation required |
| Missing count | Average-spend formula has sales but no customer count | Unavailable with a reason, not zero |
| Zero count | Average-spend formula has customer count 0 | Unavailable with a reason, not division failure or zero average |
| Advisory pass | Check permits absolute cash variance up to 10; variance 3 | Quiet Passed status: Within tolerance |
| Advisory concern | Same check; variance -25 | Prominent Concern: Cash shortage exceeds 10; submission and sending remain available |
| Advisory unavailable | Same check; cash count blank | Not evaluated with a reason to enter cash count; neither a pass nor a shortage warning |

### Builder And Historical Definitions

1. A money calculation does not offer a text operand. A dependency that would
   form a cycle cannot be selected. A forged request cannot bypass those rules.
2. Two configured terminals generate two checklist rows. A manager cannot add
   a duplicate terminal receipt row or remove a required checklist row, but may
   add several open cash-out rows.
3. A reading may reference a band performance on the same Daysheet. A record on
   another Daysheet is not an eligible reference.
4. Day A is created under definition 1. An admin publishes definition 2 with a
   changed formula/layout and updates venue reference data. Day A retains its
   captured definition and data, even while still Draft. A newly created Day B
   uses the new configuration. Day A cannot migrate in v1.
5. The starter's cashout filtering, surcharge conversion, grouped totals, and
   layouts can be authored using the same public builder as a custom venue
   template; no special hidden evaluator is needed.
6. A worker cannot access the financial form by direct request. A manager can
   enter data and send a configured report, but cannot edit its recipients.
7. Two managers save different fields: both survive. Two save the same stale
   field: the second sees both values and must deliberately resolve the conflict.

8. A daily band row has a linked reading at 23:00 of 94 dB. Confirming deletion
   shows the affected reading. The band row is removed; the reading retains its
   time and value with its band reference blank. A calculation requiring that
   reference becomes unavailable. If another link is added before confirmation
   is applied, refresh the confirmation rather than silently clearing it too.

9. An admin retires Beer Garden while an active terminal references it. Show
   the terminal and require explicit reassignment or retirement before completing
   the operation. An already-created Draft keeps its original area, terminal,
   and checklist rows. A new Daysheet omits retired entries and includes only
   valid active references.

10. A manager opens a row-deletion confirmation, then another manager edits
    that row. Deletion requires fresh confirmation showing the changed row.
    Conversely, an edit saved after the row was deleted retains the unsaved
    values for the editor but does not recreate the row.

### Reporting

1. A submitted Daysheet is captured at 6am. At 6:10 a manager corrects a receipt.
   Retrying the scheduled report uses the original figures. The Live preview
   shows the correction, clearly distinguished from the frozen report.
2. A Draft remains unsubmitted at 6am: no email, overdue alert, or automatic
   catch-up. It can still be previewed/downloaded. Later submission permits an
   explicit manual Send, creating a newly dated snapshot.
3. A submitted Daysheet has missing figures or zero revenue: it remains eligible
   for the scheduled report, with incomplete results represented honestly.
4. No cutoff snapshot was captured during an outage: do not send current data
   as a 6am report. Manual Send captures a fresh report at its actual capture time.
5. After a scheduled report is queued, recipient A is removed and B is added.
   Cancel pending delivery/retries to A; B does not receive the old report
   automatically. Already-delivered mail is not recalled.
6. An Excel export has one worksheet per selected top-level report section in
   report order, containing its selected summaries/tables and calculated values,
   not executable calculation formulas or hidden raw-data sheets. Unselected
   fields are absent; unavailable results and advisory statuses are explicit.
   A Draft export is clearly labelled Draft.
7. A manual Send cannot be used on a Draft. On a submitted Daysheet it uses
   current saved data and configured recipients, preserving previous reports.

8. A manager double-clicks Send or the browser retries after an interrupted
   response. Both attempts resolve to one frozen report and delivery run, with
   its existing status shown. Only a fresh deliberate send creates another run.

9. A manager selects Submit or Send with pending saves or an unresolved edit
   conflict. Wait for those local edits to be saved and conflicts resolved.
   A report then captures one consistent saved state: another manager's edit
   saved before capture is included; one saved after capture is not. Intentionally
   blank fields and advisory concerns still do not block either action.

## Clarifications Before Implementation

Product decisions above are settled sufficiently to plan foundational work.
Remaining items are engineering contracts or release validation, not permission
to change scope. Resolve each before its dependent implementation or release;
they do not all block starting the generic builder. New product choices must
still be brought back for approval. GitHub, not this section, owns task status.

- **Starter inputs and complete equations (starter release validation):** map
  actual POS report fields to expected cash, card, and kitchen sales; establish
  whether the source POS figures already include/exclude customer cashout.
  Define full venue reconciliation equations with representative receipts. Use
  the approved EFTPOS working assumption to proceed with design; do not present
  it as verified provider behavior or block generic foundations on report samples.
- **Numeric and operator contract:** enumerate the exact operation/type matrix,
  bounded arithmetic representation and supported rounding operations consistent
  with AUD cent-precision entry and preserved intermediate precision, safe
  range/resource bounds, and unavailable-condition evaluation semantics.
  Advisory-check presentation is settled above. The example average can be
  derived from sum/count; it does not require a new unrestricted formula language.
- **Capture and delivery boundaries:** specify the transaction/scheduler mechanics
  implementing the settled consistent-state, eligibility, and missed-cutoff
  rules. Repeated attempts of the same manual Send reuse one report/delivery run;
  shared transport retries may still produce duplicate receipt after ambiguous
  provider acceptance. A delayed worker must not label later data as a cutoff
  copy. These mechanics must preserve the product contract rather than silently
  introduce a catch-up window. The shared email contract currently describes
  account-address recipients; external Daysheet addresses need explicit supported
  recipient identity/eligibility handling, not fabricated user accounts or a
  bypass of shared delivery controls.
- **Report rendering:** apply the settled section-to-worksheet mapping,
  selected-content boundary, and explicit unavailable/advisory presentation.
  Exact formatting remains engineering design, not an additional product scope
  decision. All exported text needs safe non-executable handling; values-only
  output is not permission for formula injection.
- **Operational and privacy policy:** apply existing sensitive-data restrictions
  to custom fields and external recipients. Delivery visibility and initial
  retention are settled above; operational recovery guidance and a permanent
  legal retention schedule remain implementation/governance responsibilities.

Schema, storage, migration strategy, component interfaces, and task decomposition
are subsequent engineering design, not decisions made by this product session.
GitHub remains the implementation tracker. No implementation graph has been
published by this specification.
