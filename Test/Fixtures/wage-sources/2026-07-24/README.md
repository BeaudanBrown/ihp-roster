# Wage-source fixtures retrieved 2026-07-24

These deterministic, offline fixtures preserve the response envelopes and the
minimum provider fields consumed by Bepis for MA000009 wage-rate and Victorian
public-holiday ingestion. They are curated source fixtures, not unrestricted
provider archives. CI and Hspec read these files directly and must not call the live services.

## Provenance

Retrieval date: **2026-07-24 UTC**.

### Fair Work Commission MAPD

Official API base: `https://api.fwc.gov.au/api/v1`

The fixture records were selected from these authenticated GET responses (the
subscription key header is never stored):

- `https://api.fwc.gov.au/api/v1/awards/9?page=1&limit=100`
- `https://api.fwc.gov.au/api/v1/awards/9/classifications?page={1..12}&limit=100`
- `https://api.fwc.gov.au/api/v1/awards/9/classifications?classification_fixed_id=257&page=1&limit=100`
- `https://api.fwc.gov.au/api/v1/awards/9/pay-rates?page={1..12}&limit=100`
- `https://api.fwc.gov.au/api/v1/awards/9/penalties?base_pay_rate_id={BR89890,BR89891,BR89892,BR89894,BR89895,BR89896,BR89897}&page=1&limit=100`
- `https://api.fwc.gov.au/api/v1/awards/9/wage-allowances?page={1..5}&limit=100`

SHA-256 of the reviewed source responses (multi-page entries are deterministic
local concatenations of each page's `results` array):

| Source response | SHA-256 |
| --- | --- |
| Award page | `5ba721b483d6322f2cfbac6caeef49d79d6d30bcb11f1a9da3a3519011188707` |
| Classification pages | `bc1b6ffb75a99923de242ccff26db6261f120218cc3bbccd53c1609c9a98e574` |
| Direct Level 3 classification query | `54b960ac3a165ad8853f6f0edff3baef0c2fcaacc066212a3c634ece574be049` |
| Pay-rate pages | `9b456aa25527503f9889b3ed1f7e3a4596ee346ecd58ced7345d99c96a77e1ab` |
| Seven filtered penalty responses | `16b71cd1788e96ae8e88c5c897a77e4e70f383b213dd4bc05820675d604cc746` |
| Wage-allowance pages | `0453582e175aed55739d86eac06b902418554498b7e3c15733083afb6574a504` |

The fixture keeps Award year 2026 and all seven adult hourly Table 3
classifications retained by Bepis: Introductory and Levels 1 through 6. The
unfiltered paginated classification read did not return the current Level 3 row
in that retrieval, so the reviewed direct `classification_fixed_id=257` response
supplies it. This provider pagination/category observation is source provenance,
not permission to omit Level 3.

For each classification, the fixture includes the permanent hourly source, the
casual ordinary source, and permanent/casual Saturday, Sunday, and public-holiday
categories. It also includes both clause 29.2 weekday commenced-hour additions.
Out-of-scope overtime rows and unrelated provider records are intentionally not
copied into the curated response files.

### DataVic

Official response URL:

`https://discover.data.vic.gov.au/api/3/action/datastore_search?resource_id=caaa47de-8626-46a6-aa28-3d948c15c5d9&filters=%7B%22dateType%22%3A%22PUBLIC_HOLIDAY%22%7D&limit=500`

- Reviewed raw response SHA-256:
  `ba8d7eff6c48f3c419e9aa04f87bd3a0cb759a55521ead0d01e0811f29343cd2`
- The committed response retains the 13 records published for calendar year
  2026 and only the fields decoded by `Application.PublicHolidays.Sync`.
- The record-level `source` URLs remain the official Business Victoria yearly
  pages supplied by DataVic.
- The statewide 28 December 2026 **additional public holiday** is deliberately
  retained. A statewide date published by DataVic is authoritative; it is not
  the unsupported employer/employee substituted-day arrangement excluded by
  the compliance matrix.

### Award document

The rule matrix was checked on the same date against:

- `https://awards.fairwork.gov.au/MA000009.html`
- Retrieved HTML SHA-256:
  `f8673e16c3daaf48c2e5a211a8682bd8c0d7ff069a1b4b5506498ca15f951ee8`

## Committed fixture hashes

| Fixture | SHA-256 |
| --- | --- |
| `fwc-mapd/award.json` | `fd5a1ea381c726d6f0275b2b78d03924f943b7e3e595209f5d0f8a357add43cb` |
| `fwc-mapd/classifications.json` | `efa1702b96a02618ac45f63ace788e59c955e69a78133ab094a8ba6f1f9d2d26` |
| `fwc-mapd/pay-rates.json` | `b2f671e75169efd76ffa6f1b98a720ad94ac788479965d7499499684fd613dfe` |
| `fwc-mapd/penalties.json` | `0a8411e8f9979bef506bedc4a553d43c872c6bcd0c12b266c2a06aa5611694df` |
| `fwc-mapd/wage-allowances.json` | `32ff9487aa9ab9b28918dae041059fadc30d00b49c803312a6aa62cffed76771` |
| `datavic/public-holidays.json` | `dbe509f523b640f1b23fe46d7279a9f0a42e833b838a057851af9697fcfec194` |

`SHA256SUMS` is the machine-checked copy of this committed-fixture manifest;
`doc-drift-check` verifies it offline.

## Refresh contract

1. Retrieve into an ignored temporary directory; never make test execution a
   refresh path.
2. Record the retrieval date, exact URLs, and reviewed raw hashes.
3. Keep only provider fields consumed by the decoders and preserve the response
   envelope.
4. Confirm all seven supported adult hourly core classifications and every
   expected base/day/time rate category remain represented.
5. Review document or category-structure drift as a platform-super-admin
   notification signal. It is **not** by itself a mandatory payroll review gate.
6. Run the focused `FWC MAPD` and `DataVic public holiday` Hspec examples.

Rate-only fixture updates flow through ingestion. Rule arithmetic examples use
synthetic rates and must not change merely because current dollar values do.
