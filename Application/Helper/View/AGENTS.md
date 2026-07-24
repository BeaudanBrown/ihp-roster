# View Helper Agent Notes

Read this before editing shared view helpers under `Application/Helper/View/`.

## Local Rules

- Put helpers in the narrowest module that matches the concern.
- Keep `Application/Helper/View.hs` as a compatibility re-export facade.
- Use declarative config records rather than passing Haskell callbacks into
  view builders.
- Shared forms should usually render fields plus the `<form>` wrapper; overlay
  footers own save/cancel buttons.
- Dialog/toast helpers consume `FrontendContract.Overlay.Runtime` for generated
  lane ids, roles, auto-submit state, and exact loading/auto-hide config. Keep
  Bootstrap markup and native/ARIA state in these focused adapters; do not add
  handwritten overlay `data-*` names or move request semantics out of typed
  AppShell/Surface Action helpers.
- Time-picker helpers consume `FrontendContract.TimePicker.Runtime` for the
  generated modal/field/internal roles and exact field/option payloads. Keep
  ranges, steps, option labels, empty-state copy, and initial native/ARIA state
  in Haskell. Do not reintroduce browser-selector classes or make the picker own
  Toggle break-region activation.
- Ordered ranges consume `FrontendContract.OrderedRange.Runtime` for generated
  roles, exact config/state, position properties, and the closed crossing
  policy. Keep ranges, steps, defaults, labels, initial values, native endpoint
  labels, and availability in Haskell; compose with Toggle without exposing raw
  extra attrs or duplicating its form transport.
- Passkey controls consume `FrontendContract.Passkey.Runtime` through
  `Application.Helper.View.Passkey`. Keep begin/finish routes, redirects,
  status relationships, prompt mode, and all workflow/status/recovery copy in
  Haskell. Render complete local control/status/recovery subtrees; do not expose
  raw passkey attrs or ids. Prompt dismissal composes the generated passkey and
  Overlay close roles through the typed supplemental-close-role helper and
  consumes the generated dismissal event, leaving dialog removal, focus, and
  body locking to the Overlay adapter. Do not expose a raw extra-attribute seam.
- For typed interaction-surface helpers, read
  `Application/Helper/Interaction.SPEC.md` and
  `Application/Helper/FrontendContract/Surface/README.md` first. Helpers should
  render `data-bepis-*` attrs and HTMX intent forms from typed Haskell contracts rather
  than accepting free-text surface/layer/intent names from call sites.

## Module Ownership

- `Chrome.hs` - page, panel, and navigation wrappers.
- `Overlay.hs` - workflow dialog mount ids, config records, typed supplemental close roles, and footer buttons.
- `Toast.hs` - toast config and rendering.
- `TimePicker.hs` - quarter-hour picker helpers.
- `Passkey.hs` - generated passkey controls, local status/recovery markup, and copy.
- `Staff*.hs` - reusable staff display/dialog helpers.
- `Format.hs`, `Status.hs`, `Audience.hs` - focused formatting/audience helpers.

## Gotchas

- Do not put non-view domain helpers here. Move those to application/domain
  helper modules and leave temporary re-exports only when needed.
- Avoid in-app prose that explains how to use the UI. Controls should be
  discoverable through normal labels, icons, and tooltips.
- Do not duplicate overlay footer actions inside form bodies.

## Verification

Run `bash ./bin/in-env typecheck` after helper signature changes. Use focused
E2E or screenshots for layout/overlay behavior changes.
