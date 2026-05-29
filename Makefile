CSS_FILES += static/vendor/bootstrap-5.3.8/bootstrap.min.css
CSS_FILES += static/vendor/bootstrap-icons-1.11.3/bootstrap-icons.min.css
CSS_FILES += ${IHP}/static/vendor/flatpickr.min.css
CSS_FILES += static/css/tokens.css
CSS_FILES += static/css/bootstrap-bridge.css
CSS_FILES += static/css/layout.css
CSS_FILES += static/css/components/surfaces.css
CSS_FILES += static/css/components/menus.css
CSS_FILES += static/css/components/surface-toolbar.css
CSS_FILES += static/css/components/week-nav.css
CSS_FILES += static/css/components/status.css
CSS_FILES += static/css/components/public.css
CSS_FILES += static/css/components/panels.css
CSS_FILES += static/css/components/forms.css
CSS_FILES += static/css/components/bootstrap-overrides.css
CSS_FILES += static/css/components/accordions.css
CSS_FILES += static/css/components/admin.css
CSS_FILES += static/css/components/week-toolbar.css
CSS_FILES += static/css/components/admin-responsive.css
CSS_FILES += static/css/overlays.css
CSS_FILES += static/css/features/exports.css
CSS_FILES += static/css/features/staff-documents.css
CSS_FILES += static/css/features/leave.css
CSS_FILES += static/css/features/preferences.css
CSS_FILES += static/css/features/roster/toolbar.css
CSS_FILES += static/css/features/roster/week-overview.css
CSS_FILES += static/css/features/roster/staff-panel.css
CSS_FILES += static/css/features/roster/grid-frame.css
CSS_FILES += static/css/features/roster/day-actions.css
CSS_FILES += static/css/features/roster/staff-highlight.css
CSS_FILES += static/css/features/roster/grid-cells.css
CSS_FILES += static/css/features/roster/day-columns.css
CSS_FILES += static/css/features/roster/shift-card.css
CSS_FILES += static/css/features/roster/responsive.css
CSS_FILES += static/css/features/roster/grid-controls.css
CSS_FILES += static/css/features/roster/states.css
CSS_FILES += static/css/features/roster/export-print.css
CSS_FILES += static/css/features/timesheets.css
CSS_FILES += static/css/features/xero.css
CSS_FILES += static/app.css

JS_FILES += static/vendor/bootstrap-5.3.8/bootstrap.bundle.min.js
JS_FILES += ${IHP}/static/vendor/flatpickr.js
JS_FILES += ${IHP}/static/vendor/morphdom-umd.min.js
JS_FILES += static/app-horizontal-scroll.js

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
