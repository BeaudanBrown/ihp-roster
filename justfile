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

db:
    make db

seed-dev *args:
    if [ -z "{{args}}" ]; then seed-dev app; else seed-dev {{args}}; fi

demo-reset *args:
    if [ -z "{{args}}" ]; then bash ./bin/demo-reset; else bash ./bin/demo-reset {{args}}; fi

demo-reset-local *args:
    if [ -z "{{args}}" ]; then bash ./bin/demo-reset-local; else bash ./bin/demo-reset-local {{args}}; fi

typecheck *args:
    typecheck {{args}}

test *args:
    test {{args}}

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
