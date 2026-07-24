# Hospitality Award public-holiday and missed-meal-break verification

Checked on 22 July 2026 against the current Hospitality Industry (General) Award 2020 (MA000009) and Fair Work Ombudsman guidance.

The executable target envelope, exclusions, stable scenario IDs and output
owners are defined in
[`hospitality-award-wage-compliance-matrix.md`](hospitality-award-wage-compliance-matrix.md).
This document continues to characterize the currently implemented SQL behavior
until cutover issue #239 lands.

## Official award rules

### Public holidays

For ordinary hours worked on a public holiday, Table 14 in clause 29.2 sets the rate at:

- 225% of the ordinary hourly rate for full-time and part-time employees;
- 250% for casual employees.

The public-holiday rate takes priority over lower overlapping penalties under clause 29.3(b). Full-time and part-time employees have a four-hour minimum payment and casual employees a two-hour minimum under clause 29.4(a)-(b). Clause 29.4(d) also permits a documented alternative for full-time and part-time employees: 125% for hours worked plus equivalent paid time added to annual leave or taken as time off.

Source: [Hospitality Industry (General) Award 2020, clauses 29.2–29.4](https://awards.fairwork.gov.au/MA000009.html).

### Missed meal break after six hours

Clause 16.2 requires a shift of more than 6 hours to include an unpaid meal break of at least 30 minutes, taken after the first 2 hours and within the first 6 hours. If the employer does not allow the break, clauses 16.5–16.6 require an additional 50% of the employee's ordinary hourly rate from six hours after the shift starts until a qualifying break is provided or the shift ends.

The 50% is an addition, not a replacement rate. Clause 29.3(c) expressly makes the break penalty cumulative with the otherwise applicable penalty. Fair Work Ombudsman guidance confirms that it can apply together with weekday evening/early-morning amounts, weekend rates, public-holiday rates, and casual loading.

Sources:

- [Hospitality Industry (General) Award 2020, clauses 16.2 and 16.5–16.6](https://awards.fairwork.gov.au/MA000009.html)
- [Fair Work Ombudsman: Missed meal breaks in the Hospitality Award](https://www.fairwork.gov.au/tools-and-resources/library/K600026_Missed-meal-breaks-in-the-Hospitality-Award)

## Combined rates by day

Let `O` be the award ordinary hourly rate, including applicable all-purpose allowances. Ignoring the separate Monday–Friday evening/early-morning dollar additions, ordinary-hours results are:

| Day | Full-time/part-time base | With missed-break addition | Casual base | With missed-break addition |
| --- | ---: | ---: | ---: | ---: |
| Monday–Friday ordinary | 100% O | 150% O | 125% O | 175% O |
| Saturday | 125% O | 175% O | 150% O | 200% O |
| Sunday | 150% O | 200% O | 175% O | 225% O |
| Public holiday | 225% O | 275% O | 250% O | 300% O |

For qualifying Monday–Friday evening or early-morning work, the award's applicable flat time amount is also payable alongside the 50% missed-break addition.

## Current Bepis calculation

The canonical calculation is the `calculate_timesheet_pay` SQL function in `Application/Schema.sql`, consumed through `Application/Helper/Pay.hs`.

Implemented behavior:

- It splits a shift into calendar-day and time-window segments.
- It detects a public holiday from the venue's configured jurisdiction and the segment's calendar date.
- It selects public-holiday penalty rows ahead of Saturday, Sunday, evening, and early-morning rows.
- For a shift longer than six hours without a recorded break of at least 30 minutes beginning between two and six hours after commencement, inclusive, it creates delayed-meal-break segments from the six-hour point until a later qualifying break begins or the shift ends.
- Weekday delayed-break segments use the employment-basis base rate plus 50% of the permanent ordinary base rate and retain any applicable evening or early-morning amount. Weekend and public-holiday delayed-break segments use the applicable day penalty rate plus 50% of the permanent ordinary base rate. This produces the award's expected casual-loading arithmetic where configured rates are correct.
- It enforces a four-hour public-holiday minimum for permanent employees and a two-hour minimum for casual employees. Adjacent hours in the same continuous timesheet entry count toward the minimum, and any shortfall is emitted as a distinct `public_holiday_minimum_top_up` segment at the public-holiday rate.
- Imported Xero pay-item rates remain explicit flat-rate overrides and do not receive award penalties or public-holiday minimum top-ups.

## Remaining limitations

1. **Regional public holidays are excluded.** Public-holiday lookup explicitly requires `is_regional = FALSE`; regional applicability remains a separate product requirement.
2. **The alternative 125%-plus-paid-time public-holiday arrangement is not represented.**
3. **Imported Xero pay-item overrides bypass award penalties by design.** When an imported pay item is selected, its base rate is returned before public-holiday, time-window, and delayed-break branches.
4. **The calculator infers the award condition from recorded break timing.** It does not separately record whether the employer failed to allow a break, which is the condition used by clauses 16.5–16.6.
5. **Public-holiday continuity is entry-scoped.** Hours immediately before or after the holiday count when they are in the same timesheet entry. Combining multiple adjacent entries into one continuous engagement is not currently implemented.

## Comparable software patterns

Vendor documentation shows three common approaches to the difference between a missing break record and a genuinely missed break.

### Tanda: calculate from recorded break facts, then attest the timesheet

Tanda's HIGA managed template says its clause 16.6 penalty is automated and applies cumulatively when the required meal break is early, late, or not taken. Its break-clock workflow records actual break start/end events, while its separate employee-acknowledgement workflow asks staff to confirm that all hours and breaks are correct or request a change with a comment. The published workflow does not ask whether the employer *allowed* the break; it uses recorded break facts plus employee review.

Sources:

- [Tanda HIGA managed-template summary](https://help.tanda.co/en/articles/5666906-ma000009-hospitality-industry-general-award-2020-higa-managed-template-summary)
- [Tanda: Clocking into breaks](https://help.tanda.co/en/articles/6677030-clocking-into-breaks)
- [Tanda: Allow employees to acknowledge their worked hours](https://help.tanda.co/en/articles/5240379-allow-employees-to-acknowledge-their-worked-hours)

### Employment Hero: assume an automatic break unless an explicit no-break work type is selected

Employment Hero's HIGA package documents an automatic meal-break rule when no break is recorded, but excludes that assumption when the `No meal break` work type is selected. Its `No Break Taken` rule can then use time worked without a break and the explicit work type to produce a linked `no break taken` pay category. This is an explicit exception model: ordinary omissions receive the configured automatic break, while an asserted no-break case triggers the penalty category.

Source: [Employment Hero: Hospitality Industry (General) Award 2020](https://help.employmenthero.com/hc/en-au/articles/7616313335055-Hospitality-Industry-General-Award-2020-MA000009).

### Humanforce: ask at clock-out whether a break was actually taken

Humanforce can prompt `Did you take a break?` when an employee clocks out without a recorded break. A `Yes` response allows the employee to enter its start time and duration; a `No` response preserves a no-break timesheet. This resolves forgotten clocking before payroll, although the documented prompt does not ask why the break was missed.

Sources:

- [Humanforce: Remind employees to enter breaks when clocking out](https://help.humanforce.com/hc/en-au/articles/4404301784601-How-can-I-remind-employees-to-enter-breaks-when-clocking-out)
- [Humanforce: Take and record breaks in the mobile app](https://help.humanforce.com/hc/en-au/articles/11306664007823-Take-and-record-breaks-in-the-Humanforce-mobile-app-Work-Legacy)

### Deputy: configurable no-break questions and separate attestation

Deputy supports mandatory Boolean shift questions displayed specifically when a timesheet has no break. A business can therefore ask a question such as `Were you offered and allowed to take the required meal break?`, optionally require a comment and notify a manager. Deputy pay rules can be conditioned on Boolean custom-timesheet answers. Deputy also provides a separate timesheet-attestation workflow with confirm/dispute comments and an audit trail, although its documented attestation workflow does not block payroll export and has limitations for employee-clocked timesheets.

Deputy's built-in `Missed Break Allowance` calculation is not itself a direct HIGA implementation: it returns one hour or one unit rather than paying 50% over the actual interval from six hours until break/end. Its question and audit mechanisms are the relevant design examples.

Sources:

- [Deputy: Creating custom timesheet fields for shift questions](https://help.deputy.com/hc/en-au/articles/4689463015055-Creating-custom-timesheet-fields-for-shift-questions)
- [Deputy: Missed Break Allowance calculation](https://help.deputy.com/hc/en-au/articles/13752216887439-Pay-rule-calculation-type-Missed-Break-Allowance)
- [Deputy: Timesheet attestation](https://help.deputy.com/hc/en-au/articles/13711824323471-Using-timesheet-attestation-Beta)

### Implication for Bepis

A defensible workflow can combine the strongest parts of these patterns:

1. Record actual break start/end events where possible.
2. At clock-out or timesheet submission, ask about an absent qualifying break so forgotten records can be repaired.
3. Record an explicit no-break outcome and, if legal/audit advice requires it, whether the break was offered/allowed and why it was missed.
4. Apply the HIGA penalty automatically from the six-hour point when the confirmed record has no qualifying break.
5. Require manager review for disputed or ambiguous cases without silently suppressing an employee entitlement.
6. Keep an audit trail of employee answer, manager changes, comments, and recalculation.

These findings describe the current implementation and are not legal advice. Award coverage, agreements, annualised arrangements, classifications, allowances, and individual circumstances can change the applicable result.
