# View Guidelines

## Reference
Read `IHP/Guide/view.markdown` and `IHP/Guide/hsx.markdown` before creating views.

## Creating a View

Each view is a separate file in `Web/View/ControllerName/ActionName.hs`:

```haskell
module Web.View.Posts.Index where
import Web.View.Prelude

data IndexView = IndexView { posts :: [Post] }

instance View IndexView where
    html IndexView { .. } = [hsx|
        <h1>Posts</h1>
        {forEach posts renderPost}
    |]
```

## HSX Rules
- `[hsx|...|]` is type-checked at compile time
- Use `{expression}` to embed Haskell expressions
- Use `{forEach items renderItem}` for lists
- Action values can be used directly in `href={...}`
- Use `{when condition [hsx|...|]}` for conditional rendering
- Keep HTML structurally valid and close all tags

## Forms
Read `IHP/Guide/form.markdown`. Basic pattern:

```haskell
renderForm :: Post -> Html
renderForm post = formFor post [hsx|
    {textField #title}
    {textareaField #body}
    {submitButton}
|]
```

## Key Imports
- Always import `Web.View.Prelude`
- Shared view helpers belong in `Application/Helper/View.hs`
- Layout is defined in `Web/View/Layout.hs`

## Theming Pattern
- The app uses a centralized token system in `static/app.css`
- Root layout sets dark mode with `<html data-bs-theme="dark">`
- Prefer semantic wrappers over ad-hoc utility combinations:
  - page shells: `app-shell`, `app-content`, `app-page-auth`
  - surfaces: `app-panel`, `app-auth-card`, `app-panel-body`, `app-auth-body`
  - sizing and text helpers: `app-form-width`, `app-muted`
- Avoid inline sizing styles in HSX when a reusable class will do
- Avoid hardcoded light-mode utilities for new views

## Global Header Pattern
- Authenticated navigation belongs in `Web/View/Layout.hs`
- Keep the header generic in the template so projects can customize it
- Do not duplicate primary navigation in individual pages unless the workflow requires it

## Overlay Pattern
- Prefer HTMX-driven workflow dialog fragments over page-jump modal flows
- Render top-level overlay hosts in `Web/View/Layout.hs`
- Keep reusable dialog and toast helpers in `Application/Helper/View.hs`
- Default toast placement should come from helper config, not page-specific markup
- Dialog triggers should target the shared dialog mount
- Validation failures should rerender the dialog fragment into the same mount
- Successful submissions should return only the updated fragment(s) and any out-of-band overlay updates

## Runtime Pattern
- Do not wire feature behavior to `turbolinks:load`. The shared client runtime emits `app:page-ready` for full-page loads and HTMX swaps
- Live-update shells should render stable subscription metadata with `data-live-update-owner="true"`, `data-live-update-scope`, and `data-live-updates-path`
- Server-owned fragments can opt into blur-delayed refetch with `data-live-fragment-defer-until-blur="true"`
- Use `renderTimePickerField` for quarter-hour picker controls instead of hand-rolling the `.js-time-picker-*` markup
