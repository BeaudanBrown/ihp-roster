CSS_FILES += ${IHP}/static/vendor/bootstrap.min.css
CSS_FILES += ${IHP}/static/vendor/flatpickr.min.css
CSS_FILES += static/app.css

JS_FILES += ${IHP}/static/vendor/jquery-3.6.0.slim.min.js
JS_FILES += ${IHP}/static/vendor/timeago.js
JS_FILES += ${IHP}/static/vendor/popper.min.js
JS_FILES += ${IHP}/static/vendor/bootstrap.min.js
JS_FILES += ${IHP}/static/vendor/flatpickr.js
JS_FILES += ${IHP}/static/helpers.js
JS_FILES += ${IHP}/static/vendor/morphdom-umd.min.js
JS_FILES += ${IHP}/static/vendor/turbolinks.js
JS_FILES += ${IHP}/static/vendor/turbolinksInstantClick.js
JS_FILES += ${IHP}/static/vendor/turbolinksMorphdom.js

# Resolve IHPSchema.sql across IHP env layouts.
# Some environments expose IHP_LIB without IHPSchema.sql (e.g. env-var compatibility wrapper).
IHP_LIB_FALLBACK := $(firstword \
	$(wildcard ${IHP}/lib/IHP) \
	$(wildcard ${PWD}/IHP/ihp-ide/data))

ifeq ($(wildcard ${IHP_LIB}/IHPSchema.sql),)
ifneq (${IHP_LIB_FALLBACK},)
IHP_LIB := ${IHP_LIB_FALLBACK}
endif
endif

include ${IHP}/Makefile.dist
