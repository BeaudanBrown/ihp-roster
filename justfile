set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# Thin human-facing wrappers over the existing devenv/flake scripts.
# Keep this file as an alias layer only; do not duplicate real logic here.

start:
    dev-app

dev:
    dev-foreground

ddev:
    dev-foreground-stripe-tunnel

stop:
    dev-stop

status:
    dev-status

android-start:
    nix run .#bepis-pwa-android -- start

android-open:
    nix run .#bepis-pwa-android -- open

android-status:
    nix run .#bepis-pwa-android -- status

android-stop:
    nix run .#bepis-pwa-android -- stop

tunnel-grill:
    eval "$(bash ./bin/in-env dev-workspace-info --shell)"; \
    ssh -N -T \
        -L "${PORT}:localhost:${PORT}" \
        -L "$((PORT + 1)):localhost:$((PORT + 1))" \
        -L "${MAILHOG_PORT}:localhost:${MAILHOG_PORT}" \
        -L "${SMTP_PORT}:localhost:${SMTP_PORT}" \
        -L "${IHP_ROSTER_DEV_GRAFANA_PORT}:localhost:${IHP_ROSTER_DEV_GRAFANA_PORT}" \
        -L "${IHP_ROSTER_DEV_TEMPO_PORT}:localhost:${IHP_ROSTER_DEV_TEMPO_PORT}" \
        grill

tunnel-agent:
    eval "$(bash ./bin/in-env dev-workspace-info --shell)"; \
    ssh -N -T \
        -L "${PORT}:localhost:${PORT}" \
        -L "$((PORT + 1)):localhost:$((PORT + 1))" \
        -L "${MAILHOG_PORT}:localhost:${MAILHOG_PORT}" \
        -L "${SMTP_PORT}:localhost:${SMTP_PORT}" \
        -L "${IHP_ROSTER_DEV_GRAFANA_PORT}:localhost:${IHP_ROSTER_DEV_GRAFANA_PORT}" \
        -L "${IHP_ROSTER_DEV_TEMPO_PORT}:localhost:${IHP_ROSTER_DEV_TEMPO_PORT}" \
        agent

db:
    dev-db-reset

seed-dev *args:
    if [ -z "{{args}}" ]; then seed-dev app; else seed-dev {{args}}; fi

seed-profile *args:
    if [ -z "{{args}}" ]; then seed-profile app_profile; else seed-profile {{args}}; fi

profile *args:
    profile-app {{args}}

profile-load *args:
    profile-load {{args}}

profile-load-suite *args:
    profile-load-suite {{args}}

otel-browser *args:
    otel-browser {{args}}

otel-summary *args:
    otel-summary {{args}}

otel-start:
    dev-start-otel

otel-recent target="development" *args:
    otel-recent --target="{{target}}" {{args}}

otel-trace artifact trace *args:
    otel-trace --artifact-dir="{{artifact}}" --trace-ref="{{trace}}" {{args}}

otel-logs artifact trace:
    otel-logs --artifact-dir="{{artifact}}" --trace-ref="{{trace}}"

otel-compare target before_end after_end *args:
    otel-compare --target="{{target}}" --before-end="{{before_end}}" --after-end="{{after_end}}" {{args}}

profile-compare before after output="":
    if [ -z "{{output}}" ]; then profile-compare "{{before}}" "{{after}}"; else profile-compare "{{before}}" "{{after}}" "{{output}}"; fi

architecture:
    architecture-facts
    architecture-schema
    architecture-web-map
    architecture-module-graph

architecture-render:
    architecture-render

architecture-check:
    architecture-check-fresh

architecture-runtime-overlay *args:
    architecture-runtime-overlay {{args}}

architecture-query *args:
    architecture-query {{args}}

architecture-trace *args:
    architecture-trace-diagram {{args}}

demo-reset *args:
    if [ -z "{{args}}" ]; then bash ./bin/demo-reset; else bash ./bin/demo-reset {{args}}; fi

demo-reset-local *args:
    if [ -z "{{args}}" ]; then bash ./bin/demo-reset-local; else bash ./bin/demo-reset-local {{args}}; fi

typecheck *args:
    typecheck {{args}}

test *args:
    hspec-test {{args}}

e2e *args:
    e2e {{args}}

report:
    e2e-report

lint *args:
    lint {{args}}

format *args:
    format {{args}}

regen:
    regen-types

regen-all:
    generated-code-sync

ghci:
    ghci-app
