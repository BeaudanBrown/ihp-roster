# Bepis intentionally serves split assets from Web/View/Layout.hs via assetPath.
# IHP's optional prod.js/prod.css concatenation is disabled in
# Config/nix/flake/ihp-app.nix. Keep CSS_FILES as a style-audit manifest that
# mirrors Layout stylesheet order; do not add JS_FILES for an unused prod.js.
CSS_FILES += static/vendor/bootstrap-5.3.8/bootstrap.min.css
CSS_FILES += static/vendor/bootstrap-icons-1.11.3/bootstrap-icons.min.css
CSS_FILES += ${IHP}/static/vendor/flatpickr.min.css
CSS_FILES += static/css/tokens.css
CSS_FILES += static/css/palette.css
CSS_FILES += static/css/bootstrap-bridge.css
CSS_FILES += static/css/layout.css
CSS_FILES += static/css/components/surfaces.css
CSS_FILES += static/css/components/lazy-surface.css
CSS_FILES += static/css/components/region-transitions.css
CSS_FILES += static/css/components/horizontal.css
CSS_FILES += static/css/components/week-nav.css
CSS_FILES += static/css/components/status.css
CSS_FILES += static/css/components/public.css
CSS_FILES += static/css/components/panels.css
CSS_FILES += static/css/components/side-panel.css
CSS_FILES += static/css/components/forms.css
CSS_FILES += static/css/components/buttons.css
CSS_FILES += static/css/components/bootstrap-overrides.css
CSS_FILES += static/css/components/accordions.css
CSS_FILES += static/css/components/toggles.css
CSS_FILES += static/css/components/admin.css
CSS_FILES += static/css/components/week-toolbar.css
CSS_FILES += static/css/components/admin-responsive.css
CSS_FILES += static/css/overlays.css
CSS_FILES += static/css/features/leave.css
CSS_FILES += static/css/features/preferences.css
CSS_FILES += static/css/features/roster/toolbar.css
CSS_FILES += static/css/features/roster/week-overview.css
CSS_FILES += static/css/features/roster/timeline.css
CSS_FILES += static/css/features/roster/template-designer.css
CSS_FILES += static/css/features/roster/templates.css
CSS_FILES += static/css/features/roster/staff-panel.css
CSS_FILES += static/css/features/roster/grid-frame.css
CSS_FILES += static/css/features/roster/day-actions.css
CSS_FILES += static/css/features/roster/grid-cells.css
CSS_FILES += static/css/features/roster/day-columns.css
CSS_FILES += static/css/features/roster/shift-card.css
CSS_FILES += static/css/features/roster/responsive.css
CSS_FILES += static/css/features/roster/grid-controls.css
CSS_FILES += static/css/features/roster/states.css
CSS_FILES += static/css/features/roster/staff-highlight.css
CSS_FILES += static/css/features/roster/export-print.css
CSS_FILES += static/css/features/timesheets.css
CSS_FILES += static/css/features/xero.css

GHC_OPTIONS += -package hs-opentelemetry-api
GHC_OPTIONS += -package hs-opentelemetry-exporter-otlp
GHC_OPTIONS += -package hs-opentelemetry-instrumentation-wai
GHC_OPTIONS += -package hs-opentelemetry-propagator-w3c
GHC_OPTIONS += -package hs-opentelemetry-sdk

# Resolve IHPSchema.sql across IHP env layouts.
# Some environments expose IHP_LIB without IHPSchema.sql (e.g. env-var compatibility wrapper).
IHP_LIB_FALLBACK := $(firstword \
	$(wildcard ${IHP}/lib/IHP) \
	$(wildcard ${IHP_DEV_CHECKOUT}/ihp-ide/data))

ifeq ($(wildcard ${IHP_LIB}/IHPSchema.sql),)
ifneq (${IHP_LIB_FALLBACK},)
IHP_LIB := ${IHP_LIB_FALLBACK}
endif
endif

include ${IHP}/Makefile.dist
