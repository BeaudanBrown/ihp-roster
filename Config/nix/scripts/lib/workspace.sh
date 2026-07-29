#!/usr/bin/env bash
# shellcheck shell=bash

bepis_workspace_die() {
    local status="$1"
    shift
    echo "dev-workspace: $*" >&2
    return "$status"
}

bepis_workspace_configure() {
    local repo_root="${BEPIS_WORKSPACE_REPO_ROOT:-}"
    if [ -z "$repo_root" ]; then
        repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    fi
    [ -n "$repo_root" ] || { bepis_workspace_die 66 "run from a Git worktree"; return; }
    [ -d "$repo_root" ] || { bepis_workspace_die 66 "worktree does not exist: $repo_root"; return; }
    repo_root="$(realpath "$repo_root")"
    if [[ "$repo_root" == *$'\n'* || "$repo_root" == *$'\r'* ]]; then
        bepis_workspace_die 64 "worktree path may not contain line breaks"
        return
    fi

    local top_level
    top_level="$(git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$top_level" ] && [ "$(realpath "$top_level")" = "$repo_root" ] \
        || { bepis_workspace_die 66 "path is not a Git worktree root: $repo_root"; return; }

    local slot=0
    local kind="primary"
    local epic=""
    local identity_file="$repo_root/.bepis-epic-worktree.json"
    if [ -e "$identity_file" ]; then
        [ -f "$identity_file" ] || { bepis_workspace_die 65 "epic identity is not a regular file"; return; }
        local registry_command="${BEPIS_EPIC_WORKTREE_COMMAND:-}"
        if [ -z "$registry_command" ]; then
            registry_command="$(command -v epic-worktree 2>/dev/null || true)"
        fi
        if [ -z "$registry_command" ] && [ -f "$repo_root/Config/nix/scripts/epic/worktree" ]; then
            registry_command="$repo_root/Config/nix/scripts/epic/worktree"
        fi
        [ -n "$registry_command" ] && [ -f "$registry_command" ] \
            || { bepis_workspace_die 69 "epic-worktree registry command is unavailable"; return; }

        local workspace_json
        if [ -x "$registry_command" ]; then
            workspace_json="$("$registry_command" inspect --path "$repo_root" --json 2>/dev/null || true)"
        else
            workspace_json="$(bash "$registry_command" inspect --path "$repo_root" --json 2>/dev/null || true)"
        fi
        if ! jq -e --arg path "$repo_root" '
            .path == $path
            and .status == "active"
            and (.slot | type == "number" and . > 0 and floor == .)
            and (.epic | type == "number" and . > 0 and floor == .)
            and .kind == "epic"
        ' <<<"$workspace_json" >/dev/null 2>&1; then
            bepis_workspace_die 65 "worktree does not have an active registry identity: $repo_root"
            return
        fi
        slot="$(jq -r '.slot' <<<"$workspace_json")"
        epic="$(jq -r '.epic' <<<"$workspace_json")"
        kind="epic"
    else
        local main_line main_path
        main_line="$(git -C "$repo_root" worktree list --porcelain | grep -m1 '^worktree ' || true)"
        [ -n "$main_line" ] || { bepis_workspace_die 66 "cannot identify primary checkout"; return; }
        main_path="$(realpath "${main_line#worktree }")"
        [ "$repo_root" = "$main_path" ] \
            || { bepis_workspace_die 65 "linked worktree is missing epic identity: $repo_root"; return; }
    fi

    local state_dir=""
    if [ "${BEPIS_WORKSPACE_STATE_CONFIGURED:-}" = "1" ] \
        && [ "${BEPIS_WORKSPACE_REPO_ROOT:-}" = "$repo_root" ] \
        && [ -n "${DEVENV_AGENT_STATE_DIR:-}" ]; then
        state_dir="$DEVENV_AGENT_STATE_DIR"
    elif [ -n "${DEVENV_AGENT_STATE_DIR:-}" ]; then
        local state_root="$DEVENV_AGENT_STATE_DIR"
        if [[ "$state_root" != /* ]]; then
            state_root="$repo_root/$state_root"
        fi
        state_root="$(realpath -m "$state_root")"
        local workspace_id
        workspace_id="$(printf '%s' "$repo_root" | sha256sum | cut -c1-12)"
        state_dir="$state_root/workspace-$workspace_id"
    elif [ "$slot" -eq 0 ] && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
        # Preserve the primary checkout's existing slot-zero state location.
        state_dir="$XDG_RUNTIME_DIR/ihp-roster-dev"
    else
        state_dir="$repo_root/.devenv/agent"
    fi
    state_dir="$(realpath -m "$state_dir")"
    local app_port=$((8000 + slot))
    local smtp_port=$((1025 + slot))
    local mailhog_port=$((8025 + slot))
    local app_url="http://127.0.0.1:$app_port"
    local mailhog_url="http://127.0.0.1:$mailhog_port"
    local postgres_socket="$repo_root/build/db"
    local database_url="postgresql:///app?host=$postgres_socket"
    local otel_service_name="ihp-roster-dev"
    if [ "$slot" -ne 0 ]; then
        otel_service_name="ihp-roster-dev-epic-$epic"
    fi
    local tempo_port=$((3200 + slot))
    local tempo_server_grpc_port=$((9095 + slot))
    local tempo_otlp_grpc_port=$((14317 + slot))
    local tempo_otlp_http_port=$((14318 + slot))
    local collector_otlp_grpc_port=$((4317 + slot))
    local collector_otlp_http_port=$((4318 + slot))
    local collector_health_port=$((13133 + slot))
    local grafana_port=$((3300 + slot))

    export BEPIS_WORKSPACE_REPO_ROOT="$repo_root"
    export BEPIS_WORKSPACE_KIND="$kind"
    export BEPIS_WORKSPACE_SLOT="$slot"
    export BEPIS_WORKSPACE_EPIC="$epic"
    export BEPIS_WORKSPACE_STATE_CONFIGURED=1
    export DEVENV_AGENT_STATE_DIR="$state_dir"
    export PORT="$app_port"
    export APP_BASE_URL="$app_url"
    export BASE_URL="$app_url"
    export PWCLI_BASE_URL="$app_url"
    export SMTP_HOST="127.0.0.1"
    export SMTP_PORT="$smtp_port"
    export MAILHOG_SMTP_PORT="$smtp_port"
    export MAILHOG_PORT="$mailhog_port"
    export MAILHOG_BASE_URL="$mailhog_url"
    export PGHOST="$postgres_socket"
    export DATABASE_URL="$database_url"
    export BEPIS_WORKSPACE_OTEL_SERVICE_NAME="$otel_service_name"
    export IHP_ROSTER_DEV_TEMPO_PORT="$tempo_port"
    export IHP_ROSTER_DEV_TEMPO_SERVER_GRPC_PORT="$tempo_server_grpc_port"
    export IHP_ROSTER_DEV_TEMPO_OTLP_GRPC_PORT="$tempo_otlp_grpc_port"
    export IHP_ROSTER_DEV_TEMPO_OTLP_HTTP_PORT="$tempo_otlp_http_port"
    export IHP_ROSTER_DEV_OTLP_GRPC_PORT="$collector_otlp_grpc_port"
    export IHP_ROSTER_DEV_OTLP_HTTP_PORT="$collector_otlp_http_port"
    export IHP_ROSTER_DEV_COLLECTOR_HEALTH_PORT="$collector_health_port"
    export IHP_ROSTER_DEV_GRAFANA_PORT="$grafana_port"
}

bepis_workspace_json() {
    jq -n \
        --arg path "$BEPIS_WORKSPACE_REPO_ROOT" \
        --arg kind "$BEPIS_WORKSPACE_KIND" \
        --arg epic "$BEPIS_WORKSPACE_EPIC" \
        --argjson slot "$BEPIS_WORKSPACE_SLOT" \
        --argjson appPort "$PORT" \
        --arg appUrl "$APP_BASE_URL" \
        --argjson smtpPort "$SMTP_PORT" \
        --argjson mailhogPort "$MAILHOG_PORT" \
        --arg mailhogUrl "$MAILHOG_BASE_URL" \
        --arg stateDir "$DEVENV_AGENT_STATE_DIR" \
        --arg postgresSocket "$PGHOST" \
        --arg databaseUrl "$DATABASE_URL" \
        --arg otelServiceName "$BEPIS_WORKSPACE_OTEL_SERVICE_NAME" \
        --argjson grafanaPort "$IHP_ROSTER_DEV_GRAFANA_PORT" \
        --argjson otlpHttpPort "$IHP_ROSTER_DEV_OTLP_HTTP_PORT" \
        '{path: $path, kind: $kind, epic: (if $epic == "" then null else ($epic | tonumber) end), slot: $slot, appPort: $appPort, appUrl: $appUrl, smtpPort: $smtpPort, mailhogPort: $mailhogPort, mailhogUrl: $mailhogUrl, stateDir: $stateDir, postgresSocket: $postgresSocket, databaseUrl: $databaseUrl, otelServiceName: $otelServiceName, grafanaPort: $grafanaPort, otlpHttpPort: $otlpHttpPort}'
}

bepis_workspace_shell() {
    local name
    for name in \
        BEPIS_WORKSPACE_REPO_ROOT BEPIS_WORKSPACE_KIND BEPIS_WORKSPACE_SLOT BEPIS_WORKSPACE_EPIC \
        BEPIS_WORKSPACE_STATE_CONFIGURED DEVENV_AGENT_STATE_DIR PORT APP_BASE_URL BASE_URL PWCLI_BASE_URL \
        SMTP_HOST SMTP_PORT MAILHOG_SMTP_PORT MAILHOG_PORT MAILHOG_BASE_URL PGHOST DATABASE_URL \
        BEPIS_WORKSPACE_OTEL_SERVICE_NAME IHP_ROSTER_DEV_TEMPO_PORT IHP_ROSTER_DEV_TEMPO_SERVER_GRPC_PORT IHP_ROSTER_DEV_TEMPO_OTLP_GRPC_PORT IHP_ROSTER_DEV_TEMPO_OTLP_HTTP_PORT \
        IHP_ROSTER_DEV_OTLP_GRPC_PORT IHP_ROSTER_DEV_OTLP_HTTP_PORT IHP_ROSTER_DEV_COLLECTOR_HEALTH_PORT \
        IHP_ROSTER_DEV_GRAFANA_PORT; do
        printf 'export %s=%q\n' "$name" "${!name}"
    done
}
