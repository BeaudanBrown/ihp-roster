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

# Forward local browser/dev-service ports from this machine to a dev host.
# Run this on your laptop/workstation (e.g. t480), not inside an existing SSH
# shell on grill. Override ports with e.g.
#   IHP_ROSTER_TUNNEL_PORTS="18000:8000 18025:8025" just dev-tunnel grill
# Each item is local-port:remote-port; bare ports map to themselves.
dev-tunnel host="grill":
    port_specs="${IHP_ROSTER_TUNNEL_PORTS:-8000 8025 1025}"; \
    ssh_args=(-N -T -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3); \
    echo "Opening SSH dev tunnel to {{host}}"; \
    echo "Forwarded services:"; \
    for spec in $port_specs; do \
        if [[ "$spec" == *:* ]]; then local_port="${spec%%:*}"; remote_port="${spec#*:}"; else local_port="$spec"; remote_port="$spec"; fi; \
        ssh_args+=(-L "127.0.0.1:${local_port}:127.0.0.1:${remote_port}"); \
        case "$remote_port" in \
            8000) label="app" ;; \
            8025) label="MailHog UI/API" ;; \
            1025) label="MailHog SMTP" ;; \
            *) label="service" ;; \
        esac; \
        echo "  ${label}: 127.0.0.1:${local_port} -> {{host}}:127.0.0.1:${remote_port}"; \
    done; \
    echo; \
    echo "Open http://127.0.0.1:8000 for the app and http://127.0.0.1:8025 for MailHog when using default ports."; \
    echo "Press Ctrl-C to close the tunnel."; \
    exec ssh "${ssh_args[@]}" "{{host}}"

# Convenience alias for the primary remote development host.
tunnel-grill:
    @just dev-tunnel grill

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
