CSS_FILES += static/vendor/bootstrap-5.3.8/bootstrap.min.css
CSS_FILES += static/vendor/bootstrap-icons-1.11.3/bootstrap-icons.min.css
CSS_FILES += ${IHP}/static/vendor/flatpickr.min.css
CSS_FILES += static/css/tokens.css
CSS_FILES += static/css/bootstrap-bridge.css
CSS_FILES += static/css/layout.css
CSS_FILES += static/css/components.css
CSS_FILES += static/css/overlays.css
CSS_FILES += static/css/features/exports.css
CSS_FILES += static/css/features/compliance.css
CSS_FILES += static/css/features/leave.css
CSS_FILES += static/css/features/preferences.css
CSS_FILES += static/css/features/roster.css
CSS_FILES += static/css/features/timesheets.css
CSS_FILES += static/app.css

JS_FILES += static/vendor/bootstrap-5.3.8/bootstrap.bundle.min.js
JS_FILES += ${IHP}/static/vendor/flatpickr.js
JS_FILES += ${IHP}/static/vendor/morphdom-umd.min.js

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
