#!/usr/bin/env bash
# shellcheck shell=bash

bepis_workspace_tooling_launcher() {
    if [ -n "${BEPIS_TOOLING_LAUNCHER:-}" ]; then
        printf '%s\n' "$BEPIS_TOOLING_LAUNCHER"
    else
        realpath "$(dirname "${BASH_SOURCE[0]}")/../../../../bin/tooling-run"
    fi
}

bepis_workspace_configure() {
    local exports
    exports="$("$(bepis_workspace_tooling_launcher)" workspace info --shell)" || return
    eval "$exports"
}

bepis_workspace_json() {
    jq -n \
        --arg path "$BEPIS_WORKSPACE_REPO_ROOT" --arg kind "$BEPIS_WORKSPACE_KIND" \
        --arg epic "$BEPIS_WORKSPACE_EPIC" --argjson slot "$BEPIS_WORKSPACE_SLOT" \
        --argjson portOffset "$BEPIS_WORKSPACE_PORT_OFFSET" --argjson appPort "$PORT" \
        --argjson hooglePort "$IHP_HOOGLE_PORT" --arg appUrl "$APP_BASE_URL" \
        --argjson smtpPort "$SMTP_PORT" --argjson mailhogPort "$MAILHOG_PORT" \
        --arg mailhogUrl "$MAILHOG_BASE_URL" --arg stateDir "$DEVENV_AGENT_STATE_DIR" \
        --arg postgresMode "$DEV_POSTGRES_MODE" --arg postgresRoot "$DEV_POSTGRES_ROOT" \
        --arg postgresSocket "$PGHOST" --arg databaseUrl "$DATABASE_URL" \
        --arg otelServiceName "$BEPIS_WORKSPACE_OTEL_SERVICE_NAME" \
        --argjson grafanaPort "$IHP_ROSTER_DEV_GRAFANA_PORT" --argjson otlpHttpPort "$IHP_ROSTER_DEV_OTLP_HTTP_PORT" \
        '{path: $path, kind: $kind, epic: (if $epic == "" then null else ($epic | tonumber) end), slot: $slot, portOffset: $portOffset, appPort: $appPort, hooglePort: $hooglePort, appUrl: $appUrl, smtpPort: $smtpPort, mailhogPort: $mailhogPort, mailhogUrl: $mailhogUrl, stateDir: $stateDir, postgresMode: $postgresMode, postgresRoot: $postgresRoot, postgresSocket: $postgresSocket, databaseUrl: $databaseUrl, otelServiceName: $otelServiceName, grafanaPort: $grafanaPort, otlpHttpPort: $otlpHttpPort}'
}

bepis_workspace_shell() {
    local name
    for name in \
        BEPIS_WORKSPACE_REPO_ROOT BEPIS_WORKSPACE_KIND BEPIS_WORKSPACE_SLOT BEPIS_WORKSPACE_EPIC \
        BEPIS_WORKSPACE_STATE_CONFIGURED BEPIS_WORKSPACE_STATE_ROOT BEPIS_WORKSPACE_PORT_OFFSET DEVENV_AGENT_STATE_DIR PORT IHP_HOOGLE_PORT APP_BASE_URL BASE_URL PWCLI_BASE_URL \
        SMTP_HOST SMTP_PORT MAILHOG_SMTP_PORT MAILHOG_PORT MAILHOG_BASE_URL DEV_POSTGRES_MODE DEV_POSTGRES_ROOT DEV_POSTGRES_SOCKET PGHOST DATABASE_URL \
        BEPIS_WORKSPACE_OTEL_SERVICE_NAME IHP_ROSTER_DEV_TEMPO_PORT IHP_ROSTER_DEV_TEMPO_SERVER_GRPC_PORT IHP_ROSTER_DEV_TEMPO_OTLP_GRPC_PORT IHP_ROSTER_DEV_TEMPO_OTLP_HTTP_PORT \
        IHP_ROSTER_DEV_OTLP_GRPC_PORT IHP_ROSTER_DEV_OTLP_HTTP_PORT IHP_ROSTER_DEV_COLLECTOR_HEALTH_PORT IHP_ROSTER_DEV_GRAFANA_PORT; do
        printf 'export %s=%q\n' "$name" "${!name}"
    done
}
