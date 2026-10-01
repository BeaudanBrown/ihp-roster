#!/usr/bin/env bash
# shellcheck shell=bash

bepis_dev_db_tooling_launcher() {
    if [ -n "${BEPIS_TOOLING_LAUNCHER:-}" ]; then
        printf '%s\n' "$BEPIS_TOOLING_LAUNCHER"
    else
        realpath "$(dirname "${BASH_SOURCE[0]}")/../../../../bin/tooling-run"
    fi
}

bepis_dev_db_capture_app_state() {
    BEPIS_DEV_DB_APP_WAS_RUNNING="$("$(bepis_dev_db_tooling_launcher)" postgres app-running)"
    export BEPIS_DEV_DB_APP_WAS_RUNNING
}

bepis_dev_db_wait_for_app_recovery() {
    "$(bepis_dev_db_tooling_launcher)" postgres wait-app-recovery
}
