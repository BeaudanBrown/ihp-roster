# Third-Party Notices

This file lists known direct, vendored, and development-time open source
components used by Bepis. It is an attribution aid, not a complete SBOM.

## Framework And Haskell Dependencies

| Component | License | Copyright / owner | Notes |
| --- | --- | --- | --- |
| IHP | MIT | digitally induced GmbH | Haskell web framework. |
| ihp-mail | MIT | digitally induced GmbH | Mail support package from the IHP project. |

## Vendored Runtime Assets

| Component | License | Copyright / owner | Notes |
| --- | --- | --- | --- |
| Bootstrap 5.3.8 | MIT | The Bootstrap Authors | Vendored under `static/vendor/bootstrap-5.3.8/`. |
| Bootstrap Icons 1.11.3 | MIT | The Bootstrap Authors | Vendored under `static/vendor/bootstrap-icons-1.11.3/`. |
| HTMX 1.9.12 | BSD-2-Clause | Big Sky Software | Vendored under `static/vendor/htmx-1.9.12/`. |
| Flatpickr | MIT | Gregory Vopros | Vendored from the pinned IHP checkout. |
| Morphdom | MIT | Patrick Steele-Idem | Vendored from the pinned IHP checkout. |

## Vendored API Contracts

| Component | License | Copyright / owner | Notes |
| --- | --- | --- | --- |
| Xero OpenAPI specifications | MIT | Xero Limited | Vendored under `vendor/xero-openapi/` from `https://github.com/XeroAPI/Xero-OpenAPI`. |

## Development And Test Tooling

| Component | License | Copyright / owner | Notes |
| --- | --- | --- | --- |
| Playwright | Apache-2.0 | Microsoft Corporation | Development/test dependency via `@playwright/test`. |

## Maintenance Notes

- Preserve upstream license and notice files when vendoring third-party code.
- Update this file when adding, replacing, or removing direct vendored assets or
  major development tooling.
- Before a public source release, run a dependency license review and reconcile
  this file with the generated dependency inventory.
