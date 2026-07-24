# Xero Payroll AU v2 OpenAPI availability research — 2026-07-23

## Question

When will Xero publish an official OpenAPI contract for the Payroll AU v2
`/EarningsRates` endpoint used by Bepis?

## Finding

There is **no published availability date or active public tracking item** for
that endpoint in Xero's official OpenAPI repository as of 2026-07-23.

Xero has published an official `xero-payroll-au-v2.yaml`, but its current
contents cover Timesheets rather than Earnings Rates. The official developer
documentation separately publishes an AU Earnings Rates page, so the API
endpoint and its OpenAPI coverage currently diverge.

## Evidence

1. The official Xero OpenAPI repository's current `master` file
   [`xero-payroll-au-v2.yaml`][current-v2-spec] identifies itself as Payroll AU
   API 2.0 (`16.1.0`) at `https://api.xero.com/payroll.xro/2.0`. On 2026-07-23,
   it contains Timesheet operations and no `/EarningsRates` path.
2. Xero's PR [#752, "Add earnings rates endpoint to Payroll-Api-AU"][pr-752]
   proposed GET, POST, and GET-by-id v2 Earnings Rates contract coverage. It
   was opened on 2025-10-01, converted to draft on 2025-10-30, and closed the
   same day without a merge. Its description says it would enable AU consumers
   to retrieve earnings rates without retrieving the PayItems object.
3. Xero's PR [#778][pr-778] created the official AU v2 spec and was merged on
   2026-02-22. Its stated scope is Timesheets operations only. The subsequent
   current spec still has no Earnings Rates path.
4. GitHub search of the official repository for `earningsRates`, `Earnings
   Rates`, and `payroll au v2` found #752 as the only specific AU v2 Earnings
   Rates proposal and found no open successor or delivery date.
5. Xero's official [Payroll AU Earnings Rates documentation][earnings-docs]
   documents the endpoint independently of the OpenAPI repository.

## Implication for Bepis

Do not wait for a known publication date, and do not edit the pinned official
`vendor/xero-openapi/xero-payroll-au.yaml` as if it owned the v2 endpoint.

When Bepis next changes its v2 Earnings Rates integration, first refresh the
official vendor bundle and check whether upstream now contains the endpoint. If
it still does not, use a separately labelled local contract supplement with
source URL/retrieval date plus a safe live contract probe. Keep that supplement
distinct from the checksum-pinned upstream files.

[current-v2-spec]: https://github.com/XeroAPI/Xero-OpenAPI/blob/master/xero-payroll-au-v2.yaml
[pr-752]: https://github.com/XeroAPI/Xero-OpenAPI/pull/752
[pr-778]: https://github.com/XeroAPI/Xero-OpenAPI/pull/778
[earnings-docs]: https://developer.xero.com/documentation/api/payrollau/earningsrates
