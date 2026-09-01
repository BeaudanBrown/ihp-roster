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

bepis_dev_db_capture_app_state() {
    local app_port="${PORT:-}"
    [ -n "$app_port" ] || {
        echo "dev-db-maintenance: PORT is not configured" >&2
        return 69
    }
    BEPIS_DEV_DB_APP_WAS_RUNNING=0
    if command -v lsof >/dev/null 2>&1 \
        && lsof -nP -iTCP:"$app_port" -sTCP:LISTEN >/dev/null 2>&1; then
        BEPIS_DEV_DB_APP_WAS_RUNNING=1
    fi
    export BEPIS_DEV_DB_APP_WAS_RUNNING
}

bepis_dev_db_wait_for_app_recovery() {
    [ "${BEPIS_DEV_DB_APP_WAS_RUNNING:-0}" = 1 ] || return 0
    local attempts="${BEPIS_DEV_DB_RECOVERY_ATTEMPTS:-200}"
    local listener_count="" app_ok=false db_ok=false
    while [ "$attempts" -gt 0 ]; do
        app_ok=false
        db_ok=false
        curl --connect-timeout 1 --max-time 2 -fsS "${APP_BASE_URL:-http://127.0.0.1:${PORT}}" >/dev/null 2>&1 \
            && app_ok=true
        if listener_count="$(psql -X -h "$PGHOST" -d app -At -v ON_ERROR_STOP=1 \
            -c "SELECT COUNT(*)::INT FROM pg_stat_activity WHERE application_name = 'bepis-live-invalidation-listener'" 2>/dev/null)"; then
            [ "$listener_count" = 1 ] && db_ok=true
        fi
        if [ "$app_ok" = true ] && [ "$db_ok" = true ]; then
            echo "dev-db-maintenance: running app recovered with exactly one durable listener"
            return 0
        fi
        attempts=$((attempts - 1))
        sleep 0.1
    done
    echo "dev-db-maintenance: database maintenance completed, but the running app did not recover" >&2
    echo "Expected app health at ${APP_BASE_URL:-http://127.0.0.1:${PORT}} and one durable listener; listener_count=${listener_count:-unavailable}." >&2
    return 75
}
