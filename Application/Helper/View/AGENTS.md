# View Helper Agent Notes

Read this before editing shared view helpers under `Application/Helper/View/`.

## Local Rules

- Put helpers in the narrowest module that matches the concern.
- Keep `Application/Helper/View.hs` as a compatibility re-export facade.
- Use declarative config records rather than passing Haskell callbacks into
  view builders.
- Shared forms should usually render fields plus the `<form>` wrapper; overlay
  footers own save/cancel buttons.
- For typed interaction-surface helpers, read
  `Application/Helper/Interaction.SPEC.md` and
  `Application/Helper/FrontendContract/Surface/README.md` first. Helpers should
  render `data-bepis-*` attrs and HTMX intent forms from typed Haskell contracts rather
  than accepting free-text surface/layer/intent names from call sites.

## Module Ownership

- `Chrome.hs` - page, panel, and navigation wrappers.
- `Overlay.hs` - workflow dialog mount ids, config records, and footer buttons.
- `Toast.hs` - toast config and rendering.
- `TimePicker.hs` - quarter-hour picker helpers.
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
