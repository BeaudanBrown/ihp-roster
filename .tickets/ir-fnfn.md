---
id: ir-fnfn
status: open
deps: [ir-re0y, ir-wk3e, ir-7hik]
links: []
created: 2026-05-29T00:51:30Z
type: task
priority: 2
assignee: beaudan
parent: ir-cqg3
tags: [agent-loop, css, components, split]
---
# Split shared components.css into focused shared component modules

Break static/css/components.css into discoverable shared modules so app-wide surfaces, forms, tables, accordions, week toolbar, toggles, public/auth pages, and admin controls do not share one catch-all file.

## Design

Create static/css/components/ with modules that preserve current cascade order. Suggested files: surfaces.css (app-page-auth, app-auth-card, app-panel, app-surface, panel header/body), menus.css or navigation.css (app-action-menu, settings menu), week-toolbar.css (app-week-nav-group/button/label and app-week-toolbar*), status.css or badges.css (app-status-badge tones), public.css (app-public-* and legal document styles), forms.css (app-form-width, muted helper, form-control/form-select/profile-field-grid), bootstrap-overrides.css or tables.css/buttons.css as appropriate for card/table/button overrides, accordions.css (accordion-item.app-panel contract), toggles.css (app-toggle-button), admin.css (admin-setting-row and admin-specific controls). Do not use @import. Update Web/View/Layout.hs and Makefile CSS_FILES. Update tests/docs to look for new module links. Leave static/css/components.css as a compatibility comment only if not linked, or remove it if safe.

## Acceptance Criteria

Shared component rules are split into focused files with comments that state ownership. Layout and Makefile remain synchronized. Existing shared components (auth card, panels, accordions, week toolbar, status badges, forms, tables, toggles, admin rows) render the same. bash ./bin/in-env ./bin/style-audit passes hard checks. Focused styling regression checks covering accordions, modals, and roster/timesheet week toolbar pass or are attempted and noted.

