---
id: ir-myon
status: closed
deps: [ir-at28]
links: []
created: 2026-06-25T13:30:47Z
type: feature
priority: 2
assignee: beaudan
parent: ir-p008
tags: [agent-loop, observability, opentelemetry]
---
# Wire OpenTelemetry WAI request tracing and OTLP export

Add the OpenTelemetry runtime spine: WAI root HTTP server spans, tracer provider/exporter setup, and environment-gated OTLP export.

## Design

Use `hs-opentelemetry` instrumentation for WAI with a project Nix `doJailbreak` override for `hs-opentelemetry-instrumentation-wai`; the package is broken in nixpkgs because of a stale API upper bound, and a jailbreak build against `hs-opentelemetry-api-0.3.0.0` has succeeded. Add the needed Haskell dependencies and keep the override documented near the Nix package definition.

Gate app initialization with `IHP_ROSTER_OTEL=1` and standard `OTEL_*` environment variables such as `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_TRACES_SAMPLER`, and `OTEL_TRACES_SAMPLER_ARG`. With the flag unset, avoid initializing the tracer provider/exporter and keep overhead negligible. Keep current `IHP_ROSTER_PROFILING` behavior untouched.

Add NixOS module options for observability rather than requiring ad-hoc env files. Initial options should cover enabling OTel, service name, OTLP endpoint, sampler/sampler arg, and whether local collector/profile integration is enabled.

Root WAI spans should include method, status, and a safe path/target attribute, but must avoid raw query strings. Since WAI middleware cannot infer IHP action constructor names, add a lightweight action annotation helper and call it from controller `beforeAction` implementations to set/update `http.route` and the root span name to values such as `ShowRosterWeekAction`.

## Acceptance Criteria

With `IHP_ROSTER_OTEL=1` and a local collector, a roster request appears as an HTTP server trace with method/status and an IHP action route such as `ShowRosterWeekAction`; raw query strings and ids are not emitted by default; with the flag unset there is no meaningful runtime/export overhead; NixOS module options can configure the app env; existing typecheck and focused roster tests pass; setup docs include a minimal Nix-managed local collector command/config.


## Notes

**2026-06-28T00:47:12Z**

Implemented gated OpenTelemetry runtime: added hs-opentelemetry dependencies and jailbroken/patched WAI instrumentation, Application.Helper.Telemetry, WAI middleware wiring, controller action annotation, NixOS app env options, Makefile GHC package exposure, and local file collector smoke config. Verified with direnv exec . bash ./bin/in-env typecheck and otelcol-contrib validate.
