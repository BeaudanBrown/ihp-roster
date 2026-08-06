# Static Asset Agent Notes

## Generated And Vendor Assets

Runtime assets are local and loaded through `assetPath`. PWA manifest icons
cannot use `assetPath`; keep content-versioned filenames and update the manifest
when icon bytes change. Do not edit third-party files under `static/vendor/`.

App JavaScript is authored in `frontend/ts/`. Do not edit generated
`static/app*.js`; regenerate it with `bash ./bin/in-env frontend-build`.
Generated contracts under `frontend/ts/generated/` are also backend-owned and
must not be edited.

Browser runtime consumes exact generated contracts for backend JSON, Surface
mounts, interaction roles/intents, overlays, and shared DOM vocabulary. Do not
restore handwritten validators, raw canonical data attributes, broad server
models, alternate mount protocols, fallback business values/copy, or
feature-specific live transport/focus behavior. Read `frontend/AGENTS.md` and
the referenced interaction/Surface contracts before runtime work.

## CSS

Keep CSS split by concern under `static/css/`; read its README before changes.
Use the narrowest owner: tokens/palette, Bootstrap bridge, layout, shared
components, overlays, or feature modules. Prefer existing semantic components
and tokens; avoid broad global selectors, raw colours, and presentation classes
as browser contracts.

Link app CSS directly from `Web/View/Layout.hs` with `assetPath` and mirror the
same ordered paths in `Makefile` `CSS_FILES`. Production app CSS must not use
`@import`; IHP `prod.js`/`prod.css` concatenation remains disabled. Do not
recreate catch-all app CSS or add external CDNs/bundlers without an explicit
compatibility decision.

Keep page overflow contained, dialogs usable on phone viewports, and important
actions available without hover.

## Verification

```bash
bash ./bin/in-env frontend-test
bash ./bin/in-env frontend-check
bash ./bin/in-env ./bin/style-audit
bash ./bin/in-env e2e e2e/mobile-experience.spec.ts
```

Run `style-audit` after stylesheet ownership/link/token changes. Use focused
Playwright and screenshots for runtime/responsive behavior. Pre-commit owns only
generated JS drift through `frontend-drift-check`.
