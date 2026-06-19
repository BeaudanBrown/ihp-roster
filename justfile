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
        -L 127.0.0.1:8000:127.0.0.1:8000 \
        -L 127.0.0.1:8025:127.0.0.1:8025 \
        -L 127.0.0.1:1025:127.0.0.1:1025 \
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

profile-compare before after output="":
    if [ -z "{{output}}" ]; then profile-compare "{{before}}" "{{after}}"; else profile-compare "{{before}}" "{{after}}" "{{output}}"; fi

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
