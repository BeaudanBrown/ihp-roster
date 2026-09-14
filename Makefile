# Bepis serves the split assets listed by Web/View/Layout.hs directly.
# Config/nix/flake/ihp-app.nix disables IHP's optional prod.js/prod.css build;
# keep the included optional CSS target empty rather than duplicating that list.
CSS_FILES :=

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
