---
id: ir-jkt2
status: open
deps: []
links: []
created: 2026-04-30T05:43:03Z
type: task
priority: 2
assignee: beaudan
parent: ir-y2wh
tags: [area:style, area:assets, area:maintenance]
---
# Fix style audit asset bookkeeping

Make bin/style-audit pass its blocking checks after the CSS split. Current failure is layout-linked CSS assets not matching Makefile CSS_FILES expectations for Bootstrap Icons and flatpickr.

## Design

Compare Web/View/Layout.hs stylesheet links with Makefile CSS_FILES and static/vendor contents. Decide whether flatpickr CSS should be referenced from static/vendor or the audit should explicitly understand IHP-provided vendor assets. Keep the asset story explicit and avoid changing runtime styling behavior unless required. Exclude generated static/prod.css/vendor output from hardcoded-color reporting if it makes audit output noisy but keep the undefined-variable and missing-asset checks strict.

## Acceptance Criteria

bash ./bin/style-audit exits 0; the audit still reports undefined CSS variables, banned light-mode utilities, and inline style attributes; linked stylesheet assets in Web/View/Layout.hs are either present locally or intentionally recognized as IHP-provided; Makefile CSS_FILES no longer conflicts with the layout asset model.

