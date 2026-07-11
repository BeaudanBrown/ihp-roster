# E2E Coverage Audit

Status: active supporting audit for [#131](https://github.com/BeaudanBrown/ihp-roster/issues/131)

Parent workstream: [test-verification-efficiency.md](test-verification-efficiency.md)

## Classification Contract

This inventory was generated from `playwright test --list` on 2026-07-11. The
initial canonical default contained 176 project-tests: 116 desktop behaviors and
20 mobile behaviors repeated on Pixel 7, Galaxy S9+, and iPad Mini. After the
approved #133 relocations it contains 165 project-tests: 113 desktop behaviors,
all 20 mobile behaviors on Pixel 7, and the 16 genuinely profile-sensitive
mobile behaviors on each of Galaxy S9+ and iPad Mini. The opt-in roster
screenshot behavior is listed separately.

Flags apply to every behavior in a file unless the notes state an exception:

- **A** — must exercise real browser authentication, registration, passkey, or
  step-up rather than start from reusable authenticated state.
- **N** — navigation or browser/server integration is the contract.
- **L** — computed layout, overflow, visibility, or responsive CSS is the
  contract.
- **B** — browser APIs or native pointer, touch, wheel, focus, download, image,
  or WebAuthn behavior is required.
- **V** — multiple pages/contexts or live browser updates are required.
- **D** — more than one device profile provides distinct evidence.
- **R** — contains an assertion proposed for replacement at a faster layer;
  browser coverage remains until #133 lands the named replacement.

A blank flag means ordinary authenticated state and one browser page are enough;
it does not mean the behavior lacks server-side coverage.

## Complete Source-Behavior Inventory

| Spec | Source behaviors | Projects | Flags | Behavior protected |
| --- | ---: | --- | --- | --- |
| `admin-invites.spec.ts` | 2 | desktop | N, B | invite queue/revoke and accepted-link idempotency/email outcome |
| `admin-roster-ui-polish.spec.ts` | 3 | desktop | L | roster/admin alignment and staff unavailability submission |
| `admin-shift-types-live.spec.ts` | 2 | desktop | V | fragment ownership and cross-admin shift-type live update |
| `admin-slot-names.spec.ts` | 1 | desktop | V | add/delete draft spacing column with live refresh |
| `auth.spec.ts` | 4 | desktop | A, N | public login contract, login/logout, route guard, bad password |
| `display-density.spec.ts` | 1 | desktop | L, R | shared scale tokens and page-overflow boundary |
| `exports-authz.spec.ts` | 3 | desktop | N, R | manager/worker denial and admin fixed export catalog |
| `exports-determinism.spec.ts` (moved by #133) | 2 replacements | DB Hspec | R | distinct repeated CSV/ZIP jobs and deterministic content now live in `PayrollExportParitySpec`; real downloads remain below |
| `exports-payroll-downloads.spec.ts` | 1 | desktop | B | generate and download both payroll export forms |
| `header-navigation.spec.ts` | 2 | desktop | N, R | admin and worker header destinations/role visibility |
| `homepage.spec.ts` | 3 | desktop | N, R | welcome page, sign-in link, absence of public request access |
| `live-fragment-multiview.spec.ts` | 5 | desktop | V | leave/profile/timesheet/roster cross-viewer consistency |
| `live-fragment-submit-regressions.spec.ts` | 7 | desktop | B, V | HTMX form/modal replacement, initialization, and single mutation |
| `no-autofocus.spec.ts` | 5 | desktop | B | runtime focus on public/forms/dialogs; source scan moved to pure `FrontendContractsSpec` |
| `passkeys.spec.ts` | 6 | desktop | A, B | optional strong auth, WebAuthn registration/login/delete/setup link |
| `registration.spec.ts` | 5 | desktop | A, N | invitation-only request access and login/request links |
| `roster-assignment-filters.spec.ts` | 1 | desktop | V | assignment-filter dropdown refresh |
| `roster-assignment-sidebar.spec.ts` | 1 | desktop | V | linked assignment staff-panel refresh |
| `roster-duplicate-conflicts.spec.ts` | 2 | desktop | V | actor/viewer duplicate-conflict refresh |
| `roster-fullscreen.spec.ts` | 1 | desktop | L, B | fullscreen toggle and staff-panel visibility |
| `roster-layout-scale.spec.ts` | 7 | desktop | L, B | three widths, scale dimensions, and dialog clickability at three scales |
| `roster-live-fragments.spec.ts` | 6 | desktop | N, V | cross-viewer updates, scroll preservation, future draft, reconnect |
| `roster-pointer-effects.spec.ts` | 2 | desktop | B | generated drag proxy and dropzone effects in both layouts |
| `roster-row-controls.spec.ts` | 5 | desktop | L, R | labels/mutation controls, sticky scroll, clipping, alignment |
| `roster-staff-highlight.spec.ts` | 3 | desktop | L, B | row/day-column and persistent locate-shift highlighting |
| `roster-staff-modal.spec.ts` | 1 | desktop | N | inline edit without roster navigation |
| `roster-staff-panel-sorting.spec.ts` | 1 | desktop | L, B | three sort keys and direction toggles |
| `roster-time-picker.spec.ts` | 2 | desktop | B | modal picker selection and clear action |
| `roster-week-overview.spec.ts` | 6 | desktop | L, B, R | manager/worker/draft controls, JPG export, overflow modes |
| `styling-regression.spec.ts` | 7 | desktop | L, R | stylesheet, accordion/panel/dialog tokens, responsive computed style |
| `support-venue-switcher.spec.ts` | 2 | desktop | N | super-admin switch and ordinary-admin absence |
| `ui-region-capabilities.spec.ts` | 2 | desktop | B, V, R | marked HTMX lifecycle phases and lazy retry behavior |
| `unavailability-archive-pagination.spec.ts` | 1 | desktop | N, V | fragment pagination without accordion close/page reload |
| `venue-owner-onboarding.spec.ts` | 2 | desktop | A, N, B | owner email invite issue/redeem/one-use venue creation |
| `venue-scope.spec.ts` | 1 | desktop | A, N | login venue resolution and scoped destinations |
| `week-navigation.spec.ts` | 2 | desktop | N, R | roster/timesheet shell swaps without full navigation |
| `week-toolbar-responsive.spec.ts` | 4 | desktop | L | desktop and phone roster/timesheet toolbar ordering |
| `xero-imported-pay-item-dropdowns.spec.ts` | 1 | desktop | R | imported pay-item options in shift/staff selects |
| `xero-import-filter.spec.ts` | 1 | desktop | L, B | client-side filtering of Bootstrap candidate rows |
| `xero-staff-mapping.spec.ts` | 1 | desktop | R | disconnected Xero page renders only connection chrome |
| `xero-timesheet-preparation.spec.ts` | 1 | desktop | B | selected-period guided preparation modal |
| `mobile-experience.spec.ts` | 10 Pixel / 8 Galaxy / 8 iPad | mobile | N, L, B, D | collapsed navigation, narrow dialogs, snapping, filters; role-copy and uniform-action checks are canonical-Pixel only |
| `roster-mobile.spec.ts` | 10 Pixel / 8 Galaxy / 8 iPad | mobile | L, B, D | containment, stable widths, touch/wheel snapping; device-independent control-presence checks are canonical-Pixel only |
| `roster-mobile-screenshots.spec.ts` | 1 opt-in | Pixel, Galaxy, iPad | L, B, D | visual diagnostic captures and layout metrics; not a canonical gate |

## Fast And Full Browser Tiers

`e2e` remains the complete gate: 113 desktop behaviors, all 20 mobile behaviors
on Pixel 7, and the 16 profile-sensitive mobile behaviors on both Galaxy S9+
and iPad Mini (165 project-tests). It keeps the narrow 360px Android edge and
tablet breakpoint evidence while avoiding eight redundant project-tests.

The additive fast tier is:

1. all desktop behaviors on Chromium; and
2. all 20 mobile behaviors on Pixel 7 as the canonical touch/mobile profile.

That tier has 133 project-tests after assertion relocation. It retains every
source behavior at least once, including real auth/WebAuthn, downloads, live
multi-page behavior, computed desktop layout, touch, wheel, snapping, and
responsive navigation. It intentionally omits only duplicate Galaxy and iPad
execution. Focused file/grep/project invocations remain single-shard and are not
reinterpreted as a tier. `roster-mobile-screenshots.spec.ts` remains opt-in for
visual review in both contracts.

## Proposed Faster-Layer Replacements

No browser assertion was removed by #131. Issue #133 landed the first bounded
relocations below only after executable replacement coverage was added.

| Browser assertion candidate | Required replacement | Browser boundary retained |
| --- | --- | --- |
| `no-autofocus`: app-owned source scan **landed** | pure `FrontendContractsSpec` recursively scans app-owned Haskell/JS/TS/CSS | five real-browser public/form/dialog/passkey focus checks remain |
| `exports-determinism`: repeated CSV/ZIP content **landed** | DB-backed `PayrollExportParitySpec` creates distinct repeated jobs and compares contents | `exports-payroll-downloads.spec.ts` retains real generate/download coverage |
| `styling-regression`: stylesheet links and token/selector presence | `style-audit` manifest plus static CSS selector/token assertions | representative computed roster, accordion, dialog, and phone layout checks |
| generated region/surface attributes in `ui-region-capabilities` and live specs | `FrontendContractsSpec`/frontend unit assertions over generated names and parser behavior | real HTMX lifecycle, retry, websocket, and fragment replacement behavior |
| role-visible header/catalog/static Xero chrome (`header-navigation`, `exports-authz`, `homepage`, `xero-staff-mapping`) | focused controller/view Hspec for role and rendered-DOM contracts | one navigation/authorization browser path per role boundary |
| payroll CSV/ZIP byte determinism | `PayrollExportParitySpec` golden output and controller authorization coverage | one real browser generate/download workflow for each file container |
| imported Xero option membership | `XeroImportedPayItemsSpec` view/controller option coverage | one browser selection/save workflow |
| static roster labels and manager/worker control presence | `RosterGridSpec` and roster controller/view specs | computed overflow, permissioned interaction, and mutation flows |
| multi-device repetition of device-independent assertions inside mobile files | frontend/controller replacement or one canonical Pixel run | Galaxy narrow-width and iPad runs retain only breakpoint/touch/layout assertions that differ materially |

## Isolation Implications For #132

Only `auth.spec.ts`, `registration.spec.ts`, `passkeys.spec.ts`, the redemption
portion of `venue-owner-onboarding.spec.ts`, and login venue resolution in
`venue-scope.spec.ts` require fresh browser authentication. Other specs may load
role-scoped storage state, while still testing server authorization at their
actual endpoint. Multi-page/live specs require separate authenticated contexts
for each actor. Mail assertions require run/shard/test message correlation, not
a shared mailbox clear. Mutable fixed fixture rows must be restored before each
file or replaced with per-test identifiers before Playwright workers increase.
