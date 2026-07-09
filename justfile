set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# Thin human-facing wrappers over the existing devenv/flake scripts.
# Keep this file as an alias layer only; do not duplicate real logic here.

start:
    start

dev:
    dev-foreground

stop:
    dev-stop

status:
    dev-status

tunnel-grill:
    ssh -N -T \
        -L 8000:localhost:8000 \
        -L 8001:localhost:8001 \
        -L 8025:localhost:8025 \
        -L 1025:localhost:1025 \
        grill

db:
    make db

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

ghci:
    ghci-app
