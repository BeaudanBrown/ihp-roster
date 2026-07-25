# MA000009 wage compliance matrix

Status: target contract for [epic #227](https://github.com/BeaudanBrown/ihp-roster/issues/227). Matrix and source fixtures are established by [#228](https://github.com/BeaudanBrown/ihp-roster/issues/228); later tickets make each target row executable.

Checked on **24 July 2026** against the current Hospitality Industry (General)
Award 2020. This is an engineering verification contract, not legal advice.

## Scope and notation

- Bepis supports Melbourne (`Australia/Melbourne`) adult hourly employees in
  the seven core Table 3 classifications: Introductory and Levels 1–6.
- The stored `permanent` value means **part-time** exclusively, never full-time;
  customer-facing copy says “Part-time”. Casual is the other supported basis.
- Each timesheet entry is calculated independently. Adjacent entries are not
  joined and overlapping entries are independently payable.
- `O` is the permanent ordinary hourly rate, `C = 1.25 × O` is the casual
  ordinary rate, `E` is the evening fixed addition, and `N` is the
  early-morning fixed addition.
- Rule tests use a synthetic rate book such as `O = 100`, `E = 10`, and
  `N = 15`. These values are deliberately simple and are not current Award
  rates. Current dollar values live only in dated ingestion fixtures.
- `worked` paid time is actual elapsed shift time less the recorded unpaid meal
  break. Non-worked paid time is identified as either
  `casual_minimum_engagement_top_up` or
  `public_holiday_minimum_top_up` and never masquerades as worked time.
- Hourly earnings components use `hours`; the clause 29.2 evening and
  early-morning additions use `commenced_hours`. Exact components are grouped
  into final payroll earnings buckets and each final line is rounded once to
  cents.
- Calculation and approved-ledger quantities preserve exact elapsed seconds.
  Export hourly quantities aggregate by final output bucket, then defensively
  round once to the nearest 15 minutes (exact 7.5-minute ties round up); a
  rounded line recomputes amount from rounded quantity and rate before cent
  rounding. Fixed commenced-hour units remain whole.
- In the coverage columns, **SH** means the Staff Hours CSV, **DE** means the
  Detailed Payroll Earnings CSV, and **XR** means Xero Payroll. “Target” names
  the evidence required from the owning ticket; it does not claim that the
  target Haskell engine already exists.

## Immediate supported-rule matrix

| Scenario ID | Rule and boundary | Clause and official source | Basis | Expected paid-time outcome | Expected earnings-component outcome | Implementation owner | Test module | CSV coverage | Xero coverage |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `HIGA-10.3-PART-TIME-PERMANENT` | Resolve Bepis `Permanent` only as Award part-time. | [cl 10.2–10.3 and 10.13(a)][award] | Permanent | `worked` time only, subject to supported minimums. | Hourly components use the Table 3 part-time rate. | [#229][i229] | `Test.WageEngine.ContractSpec` | SH time; DE basis/source. | Part-time hourly bucket. |
| `HIGA-18.1-ADULT-CORE` | Resolve Introductory and Levels 1–6, and no other classification, from the effective rate book. | [cl 14 and cl 18.1, Table 3][award] | Permanent, casual | No time is created by classification selection. | Select `O` for the resolved level; casual loading is a separate rule input. | [#228][i228], [#229][i229] | `Test.FwcMapdSyncSpec`, `Test.WageEngine.ContractSpec` | SH/DE retain calculated level label. | Managed item key retains level/effective date. |
| `HIGA-11.1-CASUAL-LOADING` | Casual ordinary hours include 25% loading. | [cl 11.1][award] | Casual | Actual `worked` time, plus any applicable minimum top-up. | Ordinary hourly component is `hours × 1.25O`. | [#229][i229] | `Test.WageEngine.RulesSpec` | SH time; DE casual hourly component. | Casual ordinary hourly bucket. |
| `HIGA-POLICY-AWARD-LEVEL` | Shift-type award level overrides staff default; otherwise use staff default. Missing or unsupported levels are typed errors. | Bepis selection policy applying [cl 14 and cl 18.1][award] | Permanent, casual | No time change. | Every component uses one resolved level; never silently falls back to zero/base. | [#229][i229], [#235][i235] | `Test.WageEngine.AdapterSpec` | Both CSVs use the resolved label. | Requirements use the resolved level. |
| `HIGA-POLICY-WEEK-ROLLOVER` | A MAPD operative date takes effect on the first venue week boundary on/after that date. Weekly payroll follows `roster_week_starts_on`. | Bepis effective-date policy; [cl 23.1 permits weekly pay][award] | Permanent, casual | No time change. | Select the old or new effective rate book once; arithmetic is unchanged. | [#229][i229] | `Test.WageEngine.AdapterSpec` | DE records effective source/version. | Managed key uses effective date. |
| `HIGA-POLICY-APPROVED-IMMUTABLE` | Approved calculations remain stable after rates/config change; drafts recalculate. | Bepis audit policy | Permanent, casual, imported override | Persist exact-second paid-time segments. | Persist exact resolved components, source and version; derive rounded output lines/totals when read. | [#234][i234] | `Test.TimesheetPayLedgerSpec` | Approved ledger only for final exports. | Approved ledger only for submission. |
| `HIGA-29.2-WEEKDAY-ORDINARY` | Monday–Friday, 07:00–19:00 local time. | [cl 29.2, Table 14][award] | Permanent, casual | Qualifying `worked` minutes stay hourly paid time. | Permanent `hours × O`; casual `hours × 1.25O`. | [#229][i229], [#231][i231] | `Test.WageEngine.RulesSpec` | SH ordinary bucket; DE hourly line. | Ordinary hourly bucket. |
| `HIGA-29.2-EVENING-PART-HOUR` | Monday–Friday, 19:00–00:00. Aggregate qualifying duration before applying “per hour or part”; 15m→1 unit, 60m→1, 75m→2. | [cl 29.2, Table 14][award], [FWO evening/night guidance][fwo-evening] | Permanent, casual | Same `worked` minutes as the base hourly component; no extra paid minutes. | Base hourly component plus `ceiling(evening duration hours) × E` in a separate `commenced_hours` component. | [#231][i231] | `Test.WageEngine.ComponentsSpec` | SH does not inflate; DE has fixed-unit line. | Separate managed `RATEPERUNIT` item. |
| `HIGA-29.2-EARLY-PART-HOUR` | Monday–Friday, 00:00–07:00. Aggregate qualifying duration before applying “per hour or part”; keep this window separate from evening. | [cl 29.2, Table 14][award], [FWO evening/night guidance][fwo-evening] | Permanent, casual | Same `worked` minutes as the base hourly component; no extra paid minutes. | Base hourly component plus `ceiling(early duration hours) × N` in a separate `commenced_hours` component. | [#231][i231] | `Test.WageEngine.ComponentsSpec` | SH does not inflate; DE has fixed-unit line. | Separate managed `RATEPERUNIT` item. |
| `HIGA-29.2-SATURDAY` | Saturday local-date ordinary hours. | [cl 29.2, Table 14][award] | Permanent, casual | `worked` minutes remain hourly paid time. | Permanent `1.25O`; casual `1.50O`. | [#229][i229], [#231][i231] | `Test.WageEngine.RulesSpec` | SH Saturday bucket; DE Saturday line. | Saturday hourly bucket. |
| `HIGA-29.2-SUNDAY` | Sunday local-date ordinary hours. | [cl 29.2, Table 14][award] | Permanent, casual | `worked` minutes remain hourly paid time. | Permanent `1.50O`; casual `1.75O`. | [#229][i229], [#231][i231] | `Test.WageEngine.RulesSpec` | SH Sunday bucket; DE Sunday line. | Sunday hourly bucket. |
| `HIGA-29.2-PUBLIC-HOLIDAY` | DataVic statewide VIC public-holiday date. | [cl 29.2, Table 14][award] | Permanent, casual | `worked` minutes plus any applicable public-holiday minimum top-up. | Permanent `2.25O`; casual `2.50O`. | [#229][i229], [#233][i233] | `Test.WageEngine.RulesSpec`, `Test.PublicHolidaySyncSpec` | SH time in target day bucket; DE public-holiday line. | Public-holiday hourly bucket. |
| `HIGA-29.3-HIGHEST-PENALTY` | When day/time penalties overlap, use only the highest base penalty. Public holiday beats Saturday/Sunday; weekend/public holiday does not stack with weekday additions. | [cl 29.3(a)–(b)][award] | Permanent, casual | Count each paid minute once. | Exactly one base hourly condition per interval; no multiplied/stacked day-rate component. | [#232][i232] | `Test.WageEngine.MealBreakSpec` | No duplicated SH/DE quantity. | Exactly one base hourly bucket. |
| `HIGA-29.3-BREAK-CUMULATIVE` | The missed-meal-break 50% addition remains cumulative with the selected base condition. | [cl 29.3(c) and cl 16.5–16.6][award], [FWO missed-break guidance][fwo-break] | Permanent, casual | No extra paid time for the addition. | Separate `hours × 0.50O` component in addition to the one selected base component. | [#232][i232] | `Test.WageEngine.MealBreakSpec` | SH does not inflate; DE has separate addition. | Separate missed-break managed item. |
| `HIGA-POLICY-MELBOURNE-ELAPSED` | Calculate durations and 2h/6h thresholds from authoritative instants; classify windows/dates in `Australia/Melbourne`. Repeated autumn time needs occurrence; nonexistent spring time is rejected. | Bepis time-resolution policy applying clauses 16 and 29 | Permanent, casual, imported override | Paid minutes equal elapsed shift less elapsed unpaid break plus explicit top-ups. | Components follow local Award condition while quantities use elapsed duration. | [#230][i230] | `Test.VenueTimeSpec`, rule boundary modules | SH elapsed minutes in local buckets. | Same elapsed quantities as ledger. |
| `HIGA-POLICY-BREAK-BUCKET` | Deduct a recorded unpaid break from the actual local day/time segments it overlaps, including after midnight. | [cl 16.2][award] | Permanent, casual, imported override | Subtract each break minute exactly once from its actual bucket. | Reduce corresponding hourly quantities; fixed units derive from remaining qualifying duration. | [#230][i230], [#232][i232] | `Test.WageEngine.MealBreakSpec` | SH reflects bucket-specific deduction; DE quantities reconcile. | Reduced hourly quantities. |
| `HIGA-16.2-BREAK-5H` | Exactly 5 hours has no clause 16.2 unpaid-meal-break entitlement. | [cl 16.2, Table 2][award] | Permanent, casual | Pay recorded elapsed work; no automatic deduction/top-up. | Applicable base/time/day components only. | [#232][i232] | `Test.WageEngine.MealBreakSpec` | Normal paid time. | Normal components. |
| `HIGA-16.2-BREAK-5-6H` | More than 5 through 6 hours permits an elective recorded unpaid break up to 30m; absence does not trigger missed-break pay. | [cl 16.2 and 16.4][award] | Permanent, casual | Deduct a recorded break; otherwise pay elapsed work. | No missed-break component. | [#232][i232] | `Test.WageEngine.MealBreakSpec` | Net paid time only. | Base components only. |
| `HIGA-16.2-BREAK-6H` | Exactly 6 hours remains in the elective band; the mandatory-break and extra-pay rule begins only when the shift is **more than** 6 hours. | [cl 16.2, 16.5–16.6][award] | Permanent, casual | No automatic top-up at exactly 6h. | No missed-break component at exactly 6h. | [#232][i232] | `Test.WageEngine.MealBreakSpec` | Six hours less recorded break. | Base components only. |
| `HIGA-16.2-BREAK-OVER-6H` | A shift over 6 hours requires at least 30m unpaid meal break, starting after the first 2h and within the first 6h. | [cl 16.2, Table 2][award] | Permanent, casual | Deduct the recorded break; qualifying status controls the addition, not deduction. | Add missed-break component only for the delayed interval. | [#232][i232] | `Test.WageEngine.MealBreakSpec` | Net paid time. | Base plus any missed-break component. |
| `HIGA-16.2-BREAK-29M` | A 29-minute break is deducted but does not satisfy the minimum 30 minutes. | [cl 16.2, Table 2][award] | Permanent, casual | Deduct 29 minutes. | Missed-break addition still applies from 6h until shift end because no qualifying break occurred. | [#232][i232] | `Test.WageEngine.MealBreakSpec` | Net paid time. | Base plus missed-break component. |
| `HIGA-16.2-BREAK-30M` | A break of exactly 30 minutes can qualify when its start is in the inclusive 2h–6h window. | [cl 16.2, Table 2][award] | Permanent, casual | Deduct 30 minutes. | No missed-break component. | [#232][i232] | `Test.WageEngine.MealBreakSpec` | Net paid time. | Base components only. |
| `HIGA-16.2-BREAK-BEFORE-2H` | A break starting before 2h is deducted but does not qualify. | [cl 16.2, Table 2][award] | Permanent, casual | Deduct the break at its actual location. | Missed-break addition starts at 6h and continues to shift end unless a later qualifying break exists. | [#232][i232] | `Test.WageEngine.MealBreakSpec` | Net paid time. | Base plus missed-break component. |
| `HIGA-16.2-BREAK-AT-2H` | A 30m break starting exactly 2h after commencement qualifies. | [cl 16.2, Table 2][award] | Permanent, casual | Deduct the break. | No missed-break component. | [#232][i232] | `Test.WageEngine.MealBreakSpec` | Net paid time. | Base components only. |
| `HIGA-16.2-BREAK-AT-6H` | A 30m break starting exactly 6h after commencement qualifies. | [cl 16.2, Table 2][award] | Permanent, casual | Deduct the break. | No missed-break component. | [#232][i232] | `Test.WageEngine.MealBreakSpec` | Net paid time. | Base components only. |
| `HIGA-16.5-BREAK-LATE-STOP` | A 30m meal break starting after 6h is late: extra pay runs from 6h until break start, then stops. | [cl 16.5–16.6][award] | Permanent, casual | Deduct the break at its actual location. | `missed_meal_break = delayed hours × 0.50O`; no addition after break start. | [#232][i232] | `Test.WageEngine.MealBreakSpec` | Net paid time. | Separate missed-break line for delayed interval. |
| `HIGA-16.6-BREAK-NOT-RECORDED` | For a shift over 6h with no qualifying recorded unpaid break, extra pay runs from the 6h instant to shift end. | [cl 16.5–16.6][award], [FWO missed-break guidance][fwo-break] | Permanent, casual | All actual work remains paid once. | Base components plus `delayed hours × 0.50O`. | [#232][i232] | `Test.WageEngine.MealBreakSpec` | No extra SH hours. | Separate missed-break line. |
| `HIGA-16.6-BREAK-CASUAL-O` | A casual employee's missed-break addition is 50% of the permanent ordinary rate `O`, not 50% of `C`. | [cl 16.6][award], [FWO missed-break guidance][fwo-break] | Casual | No extra paid time. | Casual base condition plus `delayed hours × 0.50O`. | [#232][i232] | `Test.WageEngine.MealBreakSpec` | SH unchanged; DE separate addition. | Separate missed-break line. |
| `HIGA-16.6-BREAK-CONDITION-MATRIX` | Apply the same 50% addition with ordinary, evening, early-morning, Saturday, Sunday, and public-holiday base conditions, overnight and across Melbourne DST. | [cl 16.6 and 29.3(c)][award], [FWO missed-break guidance][fwo-break] | Permanent, casual | Every actual minute appears once; no added time. | One base component, applicable fixed commenced-hour component, and one cumulative `0.50O` component. | [#230][i230], [#232][i232] | `Test.WageEngine.MealBreakSpec` | SH conservation; DE component reconciliation. | Each positive component maps once. |
| `HIGA-16.6-COMMENCED-SPLIT` | A 6h threshold or internal segment split cannot count an evening/early commenced hour twice. | [cl 16.6 and 29.2][award] | Permanent, casual | No time duplication. | Aggregate qualifying duration before `ceiling`; artificial splits leave fixed-unit count unchanged. | [#231][i231], [#232][i232] | `Test.WageEngine.ComponentsSpec` | SH unchanged; DE one fixed-unit bucket. | One fixed-unit requirement/bucket. |
| `HIGA-16.2-PAID-REST` | Paid rest breaks are not entered as unpaid meal breaks and do not reduce wages. | [cl 16.2, Table 2, and cl 16.7][award] | Permanent, casual | Time remains paid as part of elapsed work. | No standalone component unless a future workflow models it; base condition remains payable. | [#232][i232] | `Test.WageEngine.MealBreakSpec` | Included in paid time. | Included in base hourly quantity. |
| `HIGA-11.3-CASUAL-MINIMUM` | Each Award-calculated casual timesheet receives at least 2 payable hours. Hypothetical continuation from actual end determines conditions and may cross windows/days/DST. | [cl 11.3][award] | Casual | Add distinct `casual_minimum_engagement_top_up` to 120 paid minutes. | Top-up hourly components follow the hypothetical continuation's conditions. | [#233][i233] | `Test.WageEngine.MinimumPaymentSpec` | SH includes top-up time; DE identifies provenance. | Top-up merges into applicable hourly buckets. |
| `HIGA-29.4-PH-MIN-PERMANENT` | A part-time employee working on a public holiday receives at least 4 payable hours. | [cl 29.4(a)][award] | Permanent | Add distinct `public_holiday_minimum_top_up` to 240 paid minutes. | Top-up quantity uses the public-holiday rate. | [#233][i233] | `Test.WageEngine.MinimumPaymentSpec` | SH includes top-up time; DE public-holiday provenance. | Merge into public-holiday hourly bucket. |
| `HIGA-29.4-PH-MIN-CASUAL` | A casual employee working on a public holiday receives at least 2 payable hours. | [cl 29.4(b)][award] | Casual | Add distinct `public_holiday_minimum_top_up` to 120 paid minutes. | Top-up quantity uses the casual public-holiday rate. | [#233][i233] | `Test.WageEngine.MinimumPaymentSpec` | SH includes top-up time. | Merge into casual public-holiday bucket. |
| `HIGA-29.4-PH-CONTINUOUS` | Hours immediately before/after the holiday count toward the minimum only when in the same continuous timesheet entry. | [cl 29.4(c)][award] | Permanent, casual | Compare the entry's total payable duration with the applicable minimum; top up only the shortfall. | Actual non-holiday time keeps its condition; any top-up is public-holiday rated. | [#233][i233] | `Test.WageEngine.MinimumPaymentSpec` | SH includes actual and top-up once. | Conditions remain separate; no duplication. |
| `HIGA-POLICY-MINIMUM-PRECEDENCE` | Apply only the highest applicable minimum; casual and public-holiday top-ups never stack. | Bepis policy implementing [cl 11.3 and 29.4][award] | Casual | At most one top-up source; 2h remains the result when both minima are 2h. | Emit only the components needed for that one top-up. | [#233][i233] | `Test.WageEngine.MinimumPaymentSpec` | No duplicate top-up hours. | No duplicate top-up components. |
| `HIGA-POLICY-ENTRY-INDEPENDENT` | Adjacent entries are not grouped; each entry gets its own calculation/minimum. Overlapping entries remain independently payable. | Bepis supported-envelope decision | Permanent, casual, imported override | Calculate each entry independently and retain auditable source entry IDs. | No period-level deduplication or adjacency allocation. | [#229][i229], [#233][i233] | `Test.WageEngine.MinimumPaymentSpec` | Each approved entry contributes once. | Each approved entry contributes once. |
| `HIGA-POLICY-IMPORTED-OVERRIDE` | Shift imported Xero item overrides staff imported item; either is an externally managed flat rate and bypasses Award rates, additions, minimums, missed-break pay, and future overtime. | Bepis external-pay-item policy | Imported override | Actual elapsed paid time less recorded unpaid break; no top-up. | One `external_imported_pay_item` hourly component at the imported flat rate. | [#229][i229], [#232][i232], [#233][i233] | `Test.WageEngine.RulesSpec`, `Test.XeroImportedPayItemsSpec` | SH actual net time; DE imported source. | Existing imported Xero earnings rate. |
| `HIGA-POLICY-FINAL-LINE-ROUNDING` | Preserve exact decimals, aggregate by final earnings bucket, round each final line once to cents, then sum rounded lines. | Bepis monetary policy | Permanent, casual, imported override | No time change. | No intermediate-cent rounding; component totals reconcile to rounded lines. | [#231][i231] | `Test.WageEngine.ComponentsSpec` | DE golden line totals. | Xero line quantities/rates reconcile. |
| `HIGA-SOURCE-FWC-COVERAGE` | Ingestion must produce permanent/casual base, Saturday, Sunday, public-holiday, evening, and early-morning categories for all seven core levels. | [cl 18.1 and 29.2][award]; [FWC MAPD API][mapd] | Permanent, casual | No direct time effect. | Rate book is complete or calculation fails closed. | [#228][i228], [#235][i235] | `Test.FwcMapdSyncSpec` | Missing source blocks final CSV. | Missing source blocks readiness/submission. |
| `HIGA-SOURCE-DATAVIC-STATEWIDE` | DataVic statewide VIC records are authoritative, including statewide additional public-holiday dates published when a holiday falls on a weekend. Regional rows are ignored under the exclusion below. | [DataVic API][datavic], record-level Business Victoria URLs | Permanent, casual | A matching local date enables public-holiday paid time/minimum logic. | Select public-holiday component/rate. | [#228][i228], [#233][i233] | `Test.PublicHolidaySyncSpec`, `Test.WageEngine.MinimumPaymentSpec` | SH/DE use the same holiday lookup. | XR uses the same holiday lookup. |
| `HIGA-SOURCE-FRESHNESS` | FWC success ≤8 days old, post-1-July sync for first full period on/after 1 July, and DataVic target-year cache ≤45 days old. Draft may warn; approval/final output fails closed. | Bepis source-integrity policy | Permanent, casual | Draft calculation may exist; approval cannot persist authoritative paid time when source is stale/missing. | Typed source error; never zero/base fallback. | [#235][i235] | `Test.WageSourcePolicySpec` | Both final CSVs blocked. | Readiness/submission blocked. |
| `HIGA-POLICY-OUTPUT-CONSERVATION` | Every positive approved component maps to exactly one output; fixed additions/missed-break money do not become Staff Hours. | Bepis output policy | Permanent, casual, imported override | SH derives from approved exact paid time, including minimum top-ups, then applies final-bucket quarter-hour export rounding. | DE/XR quantities and amounts reconcile through the same explicit export-rounding transform. | [#237][i237] | `Test.Controller.FixedExportGoldenSpec`, Xero preview/readiness/submission specs | SH and DE exact goldens. | Exactly-once, idempotent mapping. |
| `HIGA-15.2-PART-TIME-SHIFT-MIN` | Published permanent roster shift has at least 3 projected working hours after the existing projected unpaid break. This is a roster validation, not a timesheet wage top-up. | [cl 15.2(a)][award] | Permanent | Reject invalid roster shift; create no paid-time top-up. | No component. | [#236][i236] | `Test.RosterAwardDurationSpec` | N/A until valid approved work exists. | N/A. |
| `HIGA-15.2-PART-TIME-SHIFT-MAX` | Published permanent roster shift has at most 11.5 projected working hours after projected unpaid break. | [cl 15.2(b)][award] | Permanent | Reject invalid roster shift. | No component. | [#236][i236] | `Test.RosterAwardDurationSpec` | N/A. | N/A. |
| `HIGA-11.2-CASUAL-SHIFT-MAX` | Published casual roster shift has at most 12 projected working hours after projected unpaid break. | [cl 11.2(a)][award] | Casual | Reject invalid roster shift. | No component. | [#236][i236] | `Test.RosterAwardDurationSpec` | N/A. | N/A. |
| `HIGA-POLICY-GENERIC-TIME` | UI choices remain quarter-hour aligned, but the calculator is generic and no quarter-hour database invariant is added. | Bepis input policy | Permanent, casual, imported override | Preserve exact valid authoritative interval duration and persist exact-second ledger facts. | Calculation quantities derive from exact duration. | [#229][i229], [#230][i230] | `Test.WageEngine.ContractSpec`, `Test.VenueTimeSpec` | Final output buckets defensively round once to the nearest 15 minutes. | Hourly output buckets use the same rounding and recompute line amount consistently. |

## Explicit exclusions and deliberate limitations

An excluded input must be rejected as unsupported or routed to the explicit
imported-override path. It must never be silently presented as Award-compliant.

| Exclusion ID | Excluded capability | Award/source reference | Affected basis/input | Paid-time outcome | Earnings-component outcome | Implementation owner | Test module | CSV coverage | Xero coverage |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `HIGA-EXCL-FULL-TIME` | Full-time employees; `Permanent` cannot mean full-time. | [cl 9 and 15.1][award] | Full-time | No calculation. | Typed unsupported input; no component. | [#229][i229] | `Test.WageEngine.ContractSpec` | Block. | Block. |
| `HIGA-EXCL-MANAGERIAL-SALARY` | Managerial Staff (Hotels) annual salary. | [cl 18.2 and 25][award] | Salaried managerial | No calculation. | Not a core adult hourly level; no component. | [#228][i228], [#229][i229] | `Test.FwcMapdSyncSpec`, `Test.WageEngine.ContractSpec` | Block. | Block. |
| `HIGA-EXCL-JUNIOR` | Junior rates. | [cl 18.4][award] | Junior permanent/casual | No calculation. | Excluded by MAPD curation and typed unsupported input. | [#228][i228], [#229][i229] | `Test.FwcMapdSyncSpec`, `Test.WageEngine.ContractSpec` | Block. | Block. |
| `HIGA-EXCL-APPRENTICE` | Apprentice rates and proficiency payments. | [cl 12 and 19][award] | Apprentice | No calculation. | Excluded by curation/input contract. | [#228][i228], [#229][i229] | Fixture/contract specs | Block. | Block. |
| `HIGA-EXCL-TRAINEE` | National training wage/trainees. | [cl 21][award] | Trainee | No calculation. | Excluded by curation/input contract. | [#228][i228], [#229][i229] | Fixture/contract specs | Block. | Block. |
| `HIGA-EXCL-SUPPORTED-WAGE` | Supported Wage System employees. | [cl 20 and Schedule E][award] | Supported-wage employee | No calculation. | Typed unsupported input; no component. | [#229][i229] | `Test.WageEngine.ContractSpec` | Block. | Block. |
| `HIGA-EXCL-CASINO-GAMING-SURVEILLANCE` | Casino, gaming, security/surveillance stream classifications. | [cl 18.3, Table 4, Schedule A.3][award] | Any casino stream basis | No calculation. | Excluded by core-classification curation. | [#228][i228] | `Test.FwcMapdSyncSpec` | Block. | Block. |
| `HIGA-EXCL-AIRPORT-CATERING` | Airport-catering-specific classifications/arrangements and allowances. | [cl 26.11 and 26.13][award] | Airport-catering arrangement | No calculation/certification. | No airport-specific component. | [#228][i228], [#229][i229] | Fixture/contract specs | Block. | Block. |
| `HIGA-EXCL-LOADED-RATE` | Schedule I loaded-rate arrangements. | [Schedule I][award] | Loaded-rate arrangement | No Award-calculated time result. | Do not decompose a loaded rate into ordinary components. | [#228][i228], [#229][i229] | `Test.FwcMapdSyncSpec`, contract spec | Block. | Block. |
| `HIGA-EXCL-ALLOWANCES` | All allowances, including all-purpose, higher-classification-related, split-shift, meal, uniform, travel, first-aid and other clause 26 amounts. Clause 29.2 evening/early additions are penalties, not this exclusion. | [cl 26 and Schedule C][award] | Permanent, casual | Allowances create no paid time. | No allowance component; affected arrangements are not certified. | [#229][i229] | `Test.WageEngine.ContractSpec` | Do not emit. | Do not emit. |
| `HIGA-EXCL-HIGHER-DUTIES` | Automatic higher-duties classification/rate selection. | [cl 22][award] | Permanent, casual | No inferred top-up time. | Use configured level only; no inferred higher-duty component. | [#229][i229] | `Test.WageEngine.ContractSpec` | No inferred line. | No inferred item. |
| `HIGA-EXCL-ANNUALISED-SALARY-RECONCILIATION` | Annualised wage arrangements, salaries absorption and reconciliation. | [cl 24–25][award] | Annualised/salaried | No hourly-engine result. | Typed unsupported input; no reconciliation component. | [#229][i229] | `Test.WageEngine.ContractSpec` | Block. | Block. |
| `HIGA-EXCL-LEAVE` | Annual, personal/carer's, compassionate, parental, community-service and family/domestic-violence leave calculations. | [cl 30–34 and NES][award] | Permanent/casual as applicable | No leave time from this engine. | No leave earnings component. | [#229][i229] | `Test.WageEngine.ContractSpec` | Do not emit as wage-engine evidence. | Do not emit. |
| `HIGA-EXCL-SUPERANNUATION` | Superannuation calculations/contributions. | [cl 27][award] | All | No time effect. | No superannuation component. | [#229][i229] | `Test.WageEngine.ContractSpec` | Do not emit. | Do not emit. |
| `HIGA-EXCL-TERMINATION` | Termination pay and entitlements. | [cl 23.6 and NES][award] | All | No termination time calculation. | No termination component. | [#229][i229] | `Test.WageEngine.ContractSpec` | Do not emit. | Do not emit. |
| `HIGA-EXCL-TOIL` | Time off instead of paid overtime. | [cl 28.5 and Schedule F][award] | Permanent, casual | No time bank/top-up. | No TOIL component. | Outside epic #227; [#240][i240] closed | No production calculation branch | Do not emit. | Do not emit. |
| `HIGA-EXCL-OVERTIME` | Every daily, weekly, rostered-hours and period-level overtime rule. | [cl 10.13(b), 11.4 and 28][award] | Permanent, casual | Adjustments remain out-of-band for this delivery. | No wage-engine/product calculation branch, warning or label; provider ingestion may still filter provider rows. | Outside epic #227; issue [#240][i240] closed | None until separately authorized | No overtime line. | No overtime item. |
| `HIGA-EXCL-GUARANTEED-HOURS-TOP-UP` | Automatic part-time guaranteed-hours/timesheet top-ups. | [cl 10.4–10.13][award] | Permanent | Only actual approved time and supported per-entry minima. | No guaranteed-hours component. | [#229][i229] | `Test.WageEngine.ContractSpec` | No inferred hours. | No inferred component. |
| `HIGA-EXCL-BROADER-ROSTER-COMPLIANCE` | Guaranteed weekly hours, consecutive long-day rules, days off, roster notice, four-week patterns, split-shift spread and other rules beyond the three per-shift boundaries above. | [cl 10.7 and 15.2(c)–(e), 15.5–15.6][award] | Permanent/casual rosters | No additional validation or paid-time result. | No component; #236 enforces only agreed per-shift limits. | [#236][i236] | `Test.RosterAwardDurationSpec` | N/A. | N/A. |
| `HIGA-EXCL-REGIONAL-HOLIDAY` | Regional/local public holidays. | Bepis policy; [DataVic API][datavic] | Permanent, casual | Silently treat as an ordinary local date unless also statewide. | No regional public-holiday component. | [#233][i233], [#235][i235] | `Test.PublicHolidaySyncSpec` | No regional condition. | No regional condition. |
| `HIGA-EXCL-SUBSTITUTED-HOLIDAY` | Employer/employee substituted-day arrangements and Christmas weekend substitute-day arrangements. This does not exclude a statewide additional public-holiday date published by DataVic. | [cl 29.4(f)–(g) and cl 35][award] | Permanent, casual | Do not infer a privately arranged substitute paid time/day off. | Unsupported arrangement; no inferred substitute component. | [#229][i229], [#233][i233] | Contract/minimum specs | Block unsupported arrangement. | Block unsupported arrangement. |
| `HIGA-EXCL-PH-125-PAID-TIME` | 125% plus equivalent annual-leave/time-off public-holiday arrangement. | [cl 29.4(d)–(e)][award] | Permanent | Do not create equivalent leave/time-off. | Only default 225% arrangement is supported; no alternative component. | [#229][i229], [#233][i233] | Contract/minimum specs | Do not emit alternative. | Do not emit alternative. |
| `HIGA-EXCL-BREAK-OFFERED-WORKFLOW` | Separate “break offered/allowed” attestation and dispute workflow. | Legal condition in [cl 16.5–16.6][award] | Permanent, casual | Derive time only from recorded unpaid-break facts. | Do not suppress the recorded-fact missed-break component because attestation is absent. | [#232][i232] | `Test.WageEngine.MealBreakSpec` | Recorded-fact result only. | Recorded-fact result only. |
| `HIGA-EXCL-ENTRY-GROUPING` | Grouping adjacent entries into one engagement/continuous shift. | Bepis limitation alongside [cl 11.3 and 29.4(c)][award] | Permanent, casual | Entries remain independent; same-entry continuity only. | No cross-entry component allocation. | [#233][i233] | `Test.WageEngine.MinimumPaymentSpec` | Separate source entries. | Separate source entries. |
| `HIGA-EXCL-OVERLAP-VALIDATION` | Rejecting or netting overlapping timesheet entries. | Bepis limitation | Permanent, casual, imported override | Permit each valid entry's paid time independently. | No deduplication/netting component. | [#229][i229] | `Test.WageEngine.ContractSpec` | Each entry once. | Each entry once. |

## Source-data and drift policy

The dated offline fixture set is under
`Test/Fixtures/wage-sources/2026-07-24/`. Its README records exact URLs,
retrieval date, hashes, curation, and refresh procedure.

The fixture contract is structural. MAPD refresh builds a candidate, normalizes
only value-equivalent duplicate source identities, validates the complete
candidate, then publishes raw rows and projections in one transaction. A
conflicting duplicate or incomplete candidate records a failed sync while the
last complete projection remains active. Provider paging is supplemented by
direct canonical-classification reads, and response order never selects a
conflicting row.

- all seven adult hourly core classifications must remain present;
- each must project permanent and casual ordinary/base rates plus permanent and
  casual Saturday, Sunday, and public-holiday categories;
- both clause 29.2 commenced-hour categories must project;
- every MAPD overtime row is rejected at curation and validated-snapshot boundaries;
- DataVic parsing/import tests use the committed response and never the network.

A **rate-only** source update flows through ingestion and changes effective rate
books without changing synthetic rule arithmetic tests. An Award document
checksum, version, classification, or category-structure change is a
best-effort **notification signal** for platform super admins. It is not, by
itself, a mandatory review gate and does not block payroll. Missing/stale data
uses the separate fail-closed policy in `HIGA-SOURCE-FRESHNESS`.

## Existing `Test/PaySpec.hs` classification

The SQL suite predates the target component model. “Precursor” means its
business boundary maps to the target matrix but must move to named Haskell
engine evidence. “Characterization” means it protects a legacy seam and is not
Award-compliance evidence. “Non-compliance characterization” explicitly records
shape/arithmetic that the target tickets must replace; it must not be copied as
the new contract.

| Existing example | Classification | Matrix mapping / disposition |
| --- | --- | --- |
| `decodes single-entry pay payloads` | Characterization `CHAR-PAY-PAYLOAD-SINGLE` | Legacy SQL JSON decoder only; retire under [#239][i239]. |
| `builds summary flags for weekend and stacked multipliers` | **Non-compliance characterization** `CHAR-PAY-SUMMARY-STACKING` | Legacy payload permits stacked multipliers; target is `HIGA-29.3-HIGHEST-PENALTY`. |
| `derives venue-effective award dates from the next venue week boundary` | Policy precursor | `HIGA-POLICY-WEEK-ROLLOVER`. |
| `decodes range payload arrays and indexes summaries by entry id` | Characterization `CHAR-PAY-PAYLOAD-RANGE` | Legacy batch decoder only; replace with typed engine/ledger adapter in [#229][i229]/[#239][i239]. |
| `uses the staff default award level for ordinary weekday hours` | Compliance precursor | `HIGA-POLICY-AWARD-LEVEL`, `HIGA-29.2-WEEKDAY-ORDINARY`. |
| `uses elapsed instants for pay across the repeated autumn hour` | Compliance precursor | `HIGA-POLICY-MELBOURNE-ELAPSED`; the repeated hour contributes exact elapsed paid time. |
| `uses elapsed instants for pay across the skipped spring hour` | Compliance precursor | `HIGA-POLICY-MELBOURNE-ELAPSED`; the nonexistent hour contributes no elapsed paid time. |
| `rolls a mid-week FWC base rate increase to the next venue week boundary` | Policy precursor | `HIGA-POLICY-WEEK-ROLLOVER`. |
| `does not re-rate an approved entry when a newer FWC row is imported later` | Policy precursor | `HIGA-POLICY-APPROVED-IMMUTABLE`; target ledger replaces created-at SQL anchoring. |
| `splits evening and after-midnight weekday penalties` | **Non-compliance characterization** | Boundaries map to `HIGA-29.2-EVENING-PART-HOUR` and `HIGA-29.2-EARLY-PART-HOUR`, but current combined hourly amounts must become fixed commenced-hour components in [#231][i231]. |
| `uses weekend and public holiday penalty rows when applicable` | Compliance precursor | `HIGA-29.2-SATURDAY`, `HIGA-29.2-PUBLIC-HOLIDAY`. |
| `tops up a permanent employee to four paid hours on a public holiday` | Compliance precursor | `HIGA-29.4-PH-MIN-PERMANENT`. |
| `tops up a casual employee to two paid hours on a public holiday` | Compliance precursor | `HIGA-29.4-PH-MIN-CASUAL`, `HIGA-POLICY-MINIMUM-PRECEDENCE`. |
| `counts adjacent hours in a continuous shift toward the public holiday minimum` | Compliance precursor | `HIGA-29.4-PH-CONTINUOUS`; “adjacent” here is within one entry, not cross-entry grouping. |
| `tops up only the shortfall when a short continuous shift crosses into a public holiday` | Compliance precursor | `HIGA-29.4-PH-CONTINUOUS`, `HIGA-29.4-PH-MIN-PERMANENT`. |
| `uses casual base rates for casual staff` | Compliance precursor | `HIGA-11.1-CASUAL-LOADING`. |
| `lets a shift type award level override the staff default` | Policy precursor | `HIGA-POLICY-AWARD-LEVEL`. |
| `uses a staff imported Xero pay item as the hourly rate` | Policy precursor | `HIGA-POLICY-IMPORTED-OVERRIDE`. |
| `lets shift type imported Xero pay items override staff imported Xero pay items during penalty periods` | Policy precursor | `HIGA-POLICY-IMPORTED-OVERRIDE`. |
| `keeps an imported Xero rate flat across weekends and public holidays without minimum top ups` | Policy precursor | `HIGA-POLICY-IMPORTED-OVERRIDE`. |
| `keeps an imported Xero rate flat across time windows and missed break periods` | Policy precursor | `HIGA-POLICY-IMPORTED-OVERRIDE`, `HIGA-POLICY-BREAK-BUCKET`. |
| `allocates breaks to the actual penalty segment instead of trimming the end of an overnight shift` | Compliance precursor | `HIGA-POLICY-BREAK-BUCKET`. |
| `subtracts roster wage estimate automatic breaks from start+5h30 instead of the shift end` | Policy precursor | Projected-break input to `HIGA-15.2-PART-TIME-SHIFT-MIN`/`MAX`; it is not timesheet missed-break evidence. |
| `uses elapsed roster instants for wage prediction across DST transitions` | Compliance precursor | `HIGA-POLICY-MELBOURNE-ELAPSED`; roster projections use instant duration rather than wall-clock subtraction. |
| `treats an equal-clock repeated roster interval as complete for wage prediction` | Compliance precursor | `HIGA-POLICY-MELBOURNE-ELAPSED`; operational validity accepts a positive first-to-second repeated interval without admitting an invalid next-day wall-clock span. |
| `allocates after-midnight breaks to the next calendar day segment` | Compliance precursor | `HIGA-POLICY-BREAK-BUCKET`, `HIGA-POLICY-MELBOURNE-ELAPSED`. |
| `resolves weekday, Saturday, Sunday, and public holiday penalties from segment dates` | Compliance precursor | `HIGA-29.2-WEEKDAY-ORDINARY`, `SATURDAY`, `SUNDAY`, `PUBLIC-HOLIDAY`, and `HIGA-29.3-HIGHEST-PENALTY`. |
| `uses casual base and casual weekend penalty rows when the staff member is casual` | Compliance precursor | `HIGA-11.1-CASUAL-LOADING`, `HIGA-29.2-SATURDAY`. |
| `replaces worked time after six hours with weekday delayed meal break segments when no break is taken` | **Non-compliance characterization** | Arithmetic maps to `HIGA-16.6-BREAK-NOT-RECORDED`, but worked time must not be replaced; [#232][i232] emits a separate cumulative component. |
| `does not apply delayed meal break when a 30 minute break starts inside the first six hours` | Compliance precursor | `HIGA-16.2-BREAK-30M`. |
| `stops delayed meal break once a late 30 minute break starts` | Compliance precursor with legacy shape | `HIGA-16.5-BREAK-LATE-STOP`; target uses a separate component. |
| `uses the permanent ordinary rate for the casual delayed meal break top-up` | Compliance precursor with legacy shape | `HIGA-16.6-BREAK-CASUAL-O`; “top-up” becomes a separate earnings addition, not paid time. |
| `uses weekend and public holiday day rates as the delayed meal break base` | Compliance precursor with legacy shape | `HIGA-16.6-BREAK-CONDITION-MATRIX`, `HIGA-29.3-BREAK-CUMULATIVE`. |
| `adds the evening allowance to the delayed meal break rate` | **Non-compliance characterization** | Maps to `HIGA-16.6-BREAK-CONDITION-MATRIX` and `HIGA-16.6-COMMENCED-SPLIT`; the current hourly combination must become separate fixed and missed-break components. |
| `adds the early morning allowance to the delayed meal break rate` | **Non-compliance characterization** | Same disposition for `HIGA-29.2-EARLY-PART-HOUR`. |
| `does not treat a meal break before the first two hours as qualifying` | Compliance precursor | `HIGA-16.2-BREAK-BEFORE-2H`. |
| `treats a meal break at the two hour boundary as qualifying` | Compliance precursor | `HIGA-16.2-BREAK-AT-2H`. |
| `treats a meal break at the six hour boundary as qualifying` | Compliance precursor | `HIGA-16.2-BREAK-AT-6H`. |
| `emits zero paid minutes for breaks that consume the whole shift` | Characterization `CHAR-PAY-DEFENSIVE-ZERO` | Legacy defensive behavior, not Award evidence. Structural interval policy is owned by [#230][i230]; supported valid inputs still obey `HIGA-POLICY-BREAK-BUCKET`. |

## Official sources

- Hospitality Industry (General) Award 2020: [MA000009][award]
- Fair Work Ombudsman, missed meal breaks: [K600026][fwo-break]
- Fair Work Ombudsman, evening and night work: [K600027][fwo-evening]
- Fair Work Commission Modern Awards Pay Database: [MAPD API][mapd]
- DataVic Important Dates public-holiday dataset: [DataVic API][datavic]

[award]: https://awards.fairwork.gov.au/MA000009.html
[fwo-break]: https://www.fairwork.gov.au/tools-and-resources/library/K600026_Missed-meal-breaks-in-the-Hospitality-Award
[fwo-evening]: https://www.fairwork.gov.au/tools-and-resources/library/K600027_Evening-night-work-in-the-Hospitality-Award
[mapd]: https://api.fwc.gov.au/api/v1/awards/9
[datavic]: https://discover.data.vic.gov.au/api/3/action/datastore_search?resource_id=caaa47de-8626-46a6-aa28-3d948c15c5d9&filters=%7B%22dateType%22%3A%22PUBLIC_HOLIDAY%22%7D&limit=500
[i227]: https://github.com/BeaudanBrown/ihp-roster/issues/227
[i228]: https://github.com/BeaudanBrown/ihp-roster/issues/228
[i229]: https://github.com/BeaudanBrown/ihp-roster/issues/229
[i230]: https://github.com/BeaudanBrown/ihp-roster/issues/230
[i231]: https://github.com/BeaudanBrown/ihp-roster/issues/231
[i232]: https://github.com/BeaudanBrown/ihp-roster/issues/232
[i233]: https://github.com/BeaudanBrown/ihp-roster/issues/233
[i234]: https://github.com/BeaudanBrown/ihp-roster/issues/234
[i235]: https://github.com/BeaudanBrown/ihp-roster/issues/235
[i236]: https://github.com/BeaudanBrown/ihp-roster/issues/236
[i237]: https://github.com/BeaudanBrown/ihp-roster/issues/237
[i238]: https://github.com/BeaudanBrown/ihp-roster/issues/238
[i239]: https://github.com/BeaudanBrown/ihp-roster/issues/239
[i240]: https://github.com/BeaudanBrown/ihp-roster/issues/240
[i241]: https://github.com/BeaudanBrown/ihp-roster/issues/241
