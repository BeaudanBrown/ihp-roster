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
