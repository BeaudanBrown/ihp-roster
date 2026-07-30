#!/usr/bin/env bash
# shellcheck shell=bash

bepis_workspace_die() {
    local status="$1"
    shift
    echo "dev-workspace: $*" >&2
    return "$status"
}

bepis_workspace_reject_symlink_path() {
    local path="$1"
    local canonical component
    canonical="$(realpath -m "$path")"
    [ "$canonical" = "$path" ] || { bepis_workspace_die 73 "state path must be canonical: $path"; return; }
    component="$path"
    while [ "$component" != / ]; do
        [ ! -L "$component" ] || { bepis_workspace_die 73 "refusing symlinked state path component: $component"; return; }
        component="$(dirname "$component")"
    done
}

bepis_workspace_ensure_native_state() {
    local state_dir="$1"
    local repo_root="$2"
    local marker="$state_dir/.bepis-dev-runtime"
    local owner_uid project_id fs_type
    owner_uid="$(id -u)"
    project_id="$(printf '%s' "$repo_root" | sha256sum | cut -c1-12)"
    case "$state_dir" in /|/tmp|/var|/var/tmp|/run|/run/user|"$repo_root") bepis_workspace_die 64 "refusing unsafe state directory: $state_dir"; return ;; esac
    [ ! -L "$state_dir" ] || { bepis_workspace_die 73 "refusing symlink state directory: $state_dir"; return; }
    mkdir -p "$state_dir"
    [ "$(stat -c %u "$state_dir")" = "$owner_uid" ] || { bepis_workspace_die 73 "state directory is not owned by uid $owner_uid: $state_dir"; return; }
    if [ ! -f "$marker" ]; then
        if find "$state_dir" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
            bepis_workspace_die 73 "refusing non-empty unowned state directory: $state_dir"
            return
        fi
        printf 'bepis-dev-runtime-v1\nuid=%s\nproject=%s\n' "$owner_uid" "$project_id" >"$marker"
    fi
    [ "$(sed -n '1p' "$marker")" = "bepis-dev-runtime-v1" ] \
        && [ "$(sed -n '2p' "$marker")" = "uid=$owner_uid" ] \
        && [ "$(sed -n '3p' "$marker")" = "project=$project_id" ] \
        || { bepis_workspace_die 73 "state ownership marker does not match this checkout: $marker"; return; }
    chmod 700 "$state_dir"
    fs_type="$(stat -f -c %T "$state_dir")"
    case "$fs_type" in
        virtiofs|9p|nfs|nfs4|fuse*|smb*|cifs)
            [ "${BEPIS_DEV_RUNTIME_ALLOW_NON_NATIVE:-0}" = 1 ] \
                || { bepis_workspace_die 78 "refusing $fs_type runtime state at $state_dir"; return; }
            ;;
    esac
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

    local port_offset="${BEPIS_WORKSPACE_PORT_OFFSET:-0}"
    if ! [[ "$port_offset" =~ ^[0-9]+$ ]] || [ "$port_offset" -gt 40000 ]; then
        bepis_workspace_die 64 "port offset must be an integer from 0 through 40000"
        return
    fi

    local workspace_id
    workspace_id="$(printf '%s' "$repo_root" | sha256sum | cut -c1-12)"
    local state_dir=""
    local state_root="${BEPIS_WORKSPACE_STATE_ROOT:-}"
    if [ "${BEPIS_WORKSPACE_STATE_CONFIGURED:-}" = "1" ] \
        && [ "${BEPIS_WORKSPACE_REPO_ROOT:-}" = "$repo_root" ] \
        && [ -n "${DEVENV_AGENT_STATE_DIR:-}" ] \
        && [ -f "${DEVENV_AGENT_STATE_DIR}/.bepis-dev-runtime" ]; then
        state_dir="$DEVENV_AGENT_STATE_DIR"
    elif [ -n "${DEVENV_AGENT_STATE_DIR:-}" ] \
        && { [ "${BEPIS_WORKSPACE_STATE_CONFIGURED:-}" != "1" ] \
            || [ "${BEPIS_WORKSPACE_REPO_ROOT:-}" != "$repo_root" ] \
            || [ "${DEVENV_AGENT_STATE_DIR:-}" != "$repo_root/.devenv/agent" ]; }; then
        state_root="$DEVENV_AGENT_STATE_DIR"
        if [[ "$state_root" != /* ]]; then
            state_root="$repo_root/$state_root"
        fi
        state_dir="$state_root/workspace-$workspace_id"
    else
        state_root="/tmp/bepis-dev-runtime-$(id -u)-$workspace_id"
        state_dir="$state_root"
    fi
    bepis_workspace_reject_symlink_path "$state_dir" || return
    state_dir="$(realpath -m "$state_dir")"
    bepis_workspace_ensure_native_state "$state_dir" "$repo_root" || return
    local app_port=$((8000 + port_offset + slot))
    local smtp_port=$((1025 + port_offset + slot))
    local mailhog_port=$((8025 + port_offset + slot))
    local app_url="http://127.0.0.1:$app_port"
    local mailhog_url="http://127.0.0.1:$mailhog_port"
    local dev_postgres_mode="${DEV_POSTGRES_MODE:-managed}"
    local dev_postgres_root="${DEV_POSTGRES_ROOT:-/tmp/bepis-dev-postgres-$(id -u)-$workspace_id}"
    local postgres_socket
    case "$dev_postgres_mode" in
        managed)
            [[ "$dev_postgres_root" = /* ]] \
                || { bepis_workspace_die 64 "DEV_POSTGRES_ROOT must be absolute"; return; }
            case "$dev_postgres_root" in
                /|/tmp|/var|/var/tmp|/run|/run/user|"$repo_root")
                    bepis_workspace_die 64 "refusing unsafe development PostgreSQL root: $dev_postgres_root"
                    return
                    ;;
            esac
            bepis_workspace_reject_symlink_path "$dev_postgres_root" || return
            postgres_socket="$dev_postgres_root/socket"
            ;;
        external)
            postgres_socket="${DEV_POSTGRES_SOCKET:-}"
            [ -n "$postgres_socket" ] && [[ "$postgres_socket" = /* ]] \
                || { bepis_workspace_die 64 "DEV_POSTGRES_MODE=external requires absolute DEV_POSTGRES_SOCKET"; return; }
            ;;
        *) bepis_workspace_die 64 "DEV_POSTGRES_MODE must be managed or external"; return ;;
    esac
    local database_url="postgresql:///app?host=$postgres_socket"
    local otel_service_name="ihp-roster-dev"
    if [ "$slot" -ne 0 ]; then
        otel_service_name="ihp-roster-dev-epic-$epic"
    fi
    local tempo_port=$((3200 + port_offset + slot))
    local tempo_server_grpc_port=$((9095 + port_offset + slot))
    local tempo_otlp_grpc_port=$((14317 + port_offset + slot))
    local tempo_otlp_http_port=$((14318 + port_offset + slot))
    local collector_otlp_grpc_port=$((4317 + port_offset + slot))
    local collector_otlp_http_port=$((4318 + port_offset + slot))
    local collector_health_port=$((13133 + port_offset + slot))
    local grafana_port=$((3300 + port_offset + slot))
    if [ "$tempo_otlp_http_port" -gt 65535 ]; then
        bepis_workspace_die 64 "port offset and workspace slot exceed the TCP port range"
        return
    fi

    export BEPIS_WORKSPACE_REPO_ROOT="$repo_root"
    export BEPIS_WORKSPACE_KIND="$kind"
    export BEPIS_WORKSPACE_SLOT="$slot"
    export BEPIS_WORKSPACE_EPIC="$epic"
    export BEPIS_WORKSPACE_STATE_CONFIGURED=1
    export BEPIS_WORKSPACE_STATE_ROOT="$state_root"
    export BEPIS_WORKSPACE_PORT_OFFSET="$port_offset"
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
    export DEV_POSTGRES_MODE="$dev_postgres_mode"
    export DEV_POSTGRES_ROOT="$dev_postgres_root"
    export DEV_POSTGRES_SOCKET="$postgres_socket"
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
        --argjson portOffset "$BEPIS_WORKSPACE_PORT_OFFSET" \
        --argjson appPort "$PORT" \
        --arg appUrl "$APP_BASE_URL" \
        --argjson smtpPort "$SMTP_PORT" \
        --argjson mailhogPort "$MAILHOG_PORT" \
        --arg mailhogUrl "$MAILHOG_BASE_URL" \
        --arg stateDir "$DEVENV_AGENT_STATE_DIR" \
        --arg postgresMode "$DEV_POSTGRES_MODE" \
        --arg postgresRoot "$DEV_POSTGRES_ROOT" \
        --arg postgresSocket "$PGHOST" \
        --arg databaseUrl "$DATABASE_URL" \
        --arg otelServiceName "$BEPIS_WORKSPACE_OTEL_SERVICE_NAME" \
        --argjson grafanaPort "$IHP_ROSTER_DEV_GRAFANA_PORT" \
        --argjson otlpHttpPort "$IHP_ROSTER_DEV_OTLP_HTTP_PORT" \
        '{path: $path, kind: $kind, epic: (if $epic == "" then null else ($epic | tonumber) end), slot: $slot, portOffset: $portOffset, appPort: $appPort, appUrl: $appUrl, smtpPort: $smtpPort, mailhogPort: $mailhogPort, mailhogUrl: $mailhogUrl, stateDir: $stateDir, postgresMode: $postgresMode, postgresRoot: $postgresRoot, postgresSocket: $postgresSocket, databaseUrl: $databaseUrl, otelServiceName: $otelServiceName, grafanaPort: $grafanaPort, otlpHttpPort: $otlpHttpPort}'
}

bepis_workspace_shell() {
    local name
    for name in \
        BEPIS_WORKSPACE_REPO_ROOT BEPIS_WORKSPACE_KIND BEPIS_WORKSPACE_SLOT BEPIS_WORKSPACE_EPIC \
        BEPIS_WORKSPACE_STATE_CONFIGURED BEPIS_WORKSPACE_STATE_ROOT BEPIS_WORKSPACE_PORT_OFFSET DEVENV_AGENT_STATE_DIR PORT APP_BASE_URL BASE_URL PWCLI_BASE_URL \
        SMTP_HOST SMTP_PORT MAILHOG_SMTP_PORT MAILHOG_PORT MAILHOG_BASE_URL DEV_POSTGRES_MODE DEV_POSTGRES_ROOT DEV_POSTGRES_SOCKET PGHOST DATABASE_URL \
        BEPIS_WORKSPACE_OTEL_SERVICE_NAME IHP_ROSTER_DEV_TEMPO_PORT IHP_ROSTER_DEV_TEMPO_SERVER_GRPC_PORT IHP_ROSTER_DEV_TEMPO_OTLP_GRPC_PORT IHP_ROSTER_DEV_TEMPO_OTLP_HTTP_PORT \
        IHP_ROSTER_DEV_OTLP_GRPC_PORT IHP_ROSTER_DEV_OTLP_HTTP_PORT IHP_ROSTER_DEV_COLLECTOR_HEALTH_PORT \
        IHP_ROSTER_DEV_GRAFANA_PORT; do
        printf 'export %s=%q\n' "$name" "${!name}"
    done
}
