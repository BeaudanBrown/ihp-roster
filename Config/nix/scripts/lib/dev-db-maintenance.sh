#!/usr/bin/env bash
# shellcheck shell=bash

bepis_dev_db_acquire_maintenance_lock() {
    local state_dir="${DEVENV_AGENT_STATE_DIR:-}"
    [ -n "$state_dir" ] || {
        echo "dev-db-maintenance: DEVENV_AGENT_STATE_DIR is not configured" >&2
        return 69
    }
    mkdir -p "$state_dir"
    local lock_file="$state_dir/database-maintenance.lock"
    exec {BEPIS_DEV_DB_MAINTENANCE_FD}>"$lock_file"
    if ! flock -n "$BEPIS_DEV_DB_MAINTENANCE_FD"; then
        echo "dev-db-maintenance: another reset or seed operation is already running for this workspace" >&2
        return 75
    fi
}

bepis_dev_db_require_app_stopped() {
    local app_port="${PORT:-}"
    [ -n "$app_port" ] || {
        echo "dev-db-maintenance: PORT is not configured" >&2
        return 69
    }
    if command -v lsof >/dev/null 2>&1 \
        && lsof -nP -iTCP:"$app_port" -sTCP:LISTEN >/dev/null 2>&1; then
        echo "dev-db-maintenance: refusing to reset the database while the workspace app owns port $app_port" >&2
        echo "Stop just dev/ddev with Ctrl-C, or run dev-stop for a detached server, then retry." >&2
        return 75
    fi
}
