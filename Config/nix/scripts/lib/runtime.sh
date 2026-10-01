#!/usr/bin/env bash
# shellcheck shell=bash

bepis_runtime_launcher() {
    if [ -n "${BEPIS_TOOLING_LAUNCHER:-}" ]; then
        printf '%s\n' "$BEPIS_TOOLING_LAUNCHER"
    else
        realpath "${BEPIS_SCRIPTS_ROOT:?}/../../../bin/tooling-run"
    fi
}

bepis_runtime_prepare() {
    if [ -z "${BEPIS_RUNTIME_BINARY:-}" ]; then
        BEPIS_RUNTIME_BINARY="$("$(bepis_runtime_launcher)" runtime --print-binary)"
        export BEPIS_RUNTIME_BINARY
    fi
}

bepis_runtime_command() {
    bepis_runtime_prepare
    "$BEPIS_RUNTIME_BINARY" "$@"
}

bepis_runtime_owner_file() {
    printf '%s.owner.json\n' "${1%.pid}"
}

bepis_runtime_ensure_invocation_token() {
    if [ -z "${BEPIS_RUNTIME_INVOCATION_TOKEN:-}" ]; then
        BEPIS_RUNTIME_INVOCATION_TOKEN="$(tr -d '\n' </proc/sys/kernel/random/uuid)"
        export BEPIS_RUNTIME_INVOCATION_TOKEN
    fi
}

bepis_runtime_start() {
    local pid_file="$1" log_file="$2" label="$3"
    shift 3
    local owner_file
    owner_file="$(bepis_runtime_owner_file "$pid_file")"
    bepis_runtime_command process start "$pid_file" "$owner_file" "$log_file" "$label" \
        "$BEPIS_WORKSPACE_REPO_ROOT" -- "$@"
}

bepis_runtime_start_result() {
    local pid_file="$1" log_file="$2" label="$3"
    shift 3
    local owner_file
    owner_file="$(bepis_runtime_owner_file "$pid_file")"
    bepis_runtime_prepare
    setsid "$BEPIS_RUNTIME_BINARY" process start-result "$pid_file" "$owner_file" "$log_file" "$label" \
        "$BEPIS_WORKSPACE_REPO_ROOT" -- "$@"
}

bepis_runtime_result_value() {
    local result="$1" key="$2"
    awk -v key="$key" '{for (i=1; i<=NF; i++) if ($i ~ ("^" key "=")) {sub("^" key "=", "", $i); print $i}}' <<<"$result"
}

bepis_runtime_adopt() {
    local pid_file="$1" label="$2" pid="$3"
    local owner_file
    owner_file="$(bepis_runtime_owner_file "$pid_file")"
    bepis_runtime_command process adopt "$pid_file" "$owner_file" "$label" \
        "$BEPIS_WORKSPACE_REPO_ROOT" "$pid"
}

bepis_runtime_release() {
    local pid_file="$1" label="$2" pid="$3"
    local owner_file
    owner_file="$(bepis_runtime_owner_file "$pid_file")"
    bepis_runtime_command process release "$pid_file" "$owner_file" "$label" \
        "$BEPIS_WORKSPACE_REPO_ROOT" "$pid"
}

bepis_runtime_stop_invocation() {
    local pid_file="$1" label="$2" grace_ms="${3:-2000}"
    local owner_file
    owner_file="$(bepis_runtime_owner_file "$pid_file")"
    [ -n "${BEPIS_RUNTIME_INVOCATION_TOKEN:-}" ] || return 0
    bepis_runtime_command process stop-invocation "$pid_file" "$owner_file" "$label" \
        "$BEPIS_WORKSPACE_REPO_ROOT" "$BEPIS_RUNTIME_INVOCATION_TOKEN" "$grace_ms"
}

bepis_runtime_stop() {
    local pid_file="$1" label="$2" grace_ms="${3:-20000}"
    local owner_file
    owner_file="$(bepis_runtime_owner_file "$pid_file")"
    bepis_runtime_command process stop "$pid_file" "$owner_file" "$label" \
        "$BEPIS_WORKSPACE_REPO_ROOT" "$grace_ms"
}

bepis_runtime_wait() {
    local timeout_ms="$1" label="$2" log_file="$3"
    shift 3
    bepis_runtime_command wait-command "$timeout_ms" "$label" "$log_file" -- "$@"
}

bepis_runtime_wait_owned() {
    local timeout_ms="$1" label="$2" log_file="$3" pid_file="$4"
    shift 4
    local owner_file
    owner_file="$(bepis_runtime_owner_file "$pid_file")"
    bepis_runtime_command wait-owned-command "$timeout_ms" "$label" "$log_file" \
        "$pid_file" "$owner_file" "$BEPIS_WORKSPACE_REPO_ROOT" -- "$@"
}

bepis_runtime_observe() {
    local pid_file="$1" label="$2"
    local owner_file
    owner_file="$(bepis_runtime_owner_file "$pid_file")"
    bepis_runtime_command process observe "$pid_file" "$owner_file" "$label" \
        "$BEPIS_WORKSPACE_REPO_ROOT"
}
