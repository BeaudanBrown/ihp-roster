#!/usr/bin/env bash
# shellcheck shell=bash

bepis_hls_cache_die() {
    local status="$1"
    shift
    echo "hls-cache: $*" >&2
    return "$status"
}

bepis_hls_cache_reject_line_breaks() {
    [[ "$1" != *$'\n'* && "$1" != *$'\r'* ]]
}

bepis_hls_cache_identity_for_path() {
    local requested_path="$1"
    bepis_hls_cache_reject_line_breaks "$requested_path" \
        || bepis_hls_cache_die 64 "workspace path may not contain line breaks" || return
    [ -n "$requested_path" ] && [ "$requested_path" != / ] \
        || bepis_hls_cache_die 64 "workspace path must not be empty or root" || return

    BEPIS_HLS_CACHE_WORKSPACE_PATH="$(realpath -m "$requested_path")"
    [ "$BEPIS_HLS_CACHE_WORKSPACE_PATH" = "$requested_path" ] \
        || bepis_hls_cache_die 64 "workspace path must be canonical: $requested_path" || return
    BEPIS_HLS_CACHE_WORKSPACE_ID="$(printf '%s' "$BEPIS_HLS_CACHE_WORKSPACE_PATH" | sha256sum | cut -c1-12)"
    BEPIS_HLS_CACHE_PARENT="${BEPIS_HLS_CACHE_PARENT:-/var/tmp/bepis-hls-$(id -u)}"
    bepis_hls_cache_reject_line_breaks "$BEPIS_HLS_CACHE_PARENT" \
        || bepis_hls_cache_die 64 "cache parent may not contain line breaks" || return
    [ "$(realpath -m "$BEPIS_HLS_CACHE_PARENT")" = "$BEPIS_HLS_CACHE_PARENT" ] \
        || bepis_hls_cache_die 65 "cache parent must be canonical and must not traverse symlinks: $BEPIS_HLS_CACHE_PARENT" || return
    BEPIS_HLS_CACHE_ROOT="$BEPIS_HLS_CACHE_PARENT/$BEPIS_HLS_CACHE_WORKSPACE_ID"
    BEPIS_HLS_CACHE_LOCKS="$BEPIS_HLS_CACHE_PARENT/locks"
    BEPIS_HLS_CACHE_LIFECYCLE_LOCK="$BEPIS_HLS_CACHE_LOCKS/$BEPIS_HLS_CACHE_WORKSPACE_ID.lock"
}

bepis_hls_cache_resolve_workspace() {
    local requested="${1:-${BEPIS_HLS_CACHE_REPO_ROOT:-$PWD}}"
    local top_level
    top_level="$(git -C "$requested" rev-parse --show-toplevel 2>/dev/null)" \
        || bepis_hls_cache_die 66 "cannot resolve Git worktree from: $requested" || return
    top_level="$(realpath "$top_level")"
    bepis_hls_cache_identity_for_path "$top_level"
}

bepis_hls_cache_validate_owned_directory() {
    local path="$1"
    local label="$2"
    [ -d "$path" ] && [ ! -L "$path" ] \
        || bepis_hls_cache_die 65 "$label is missing, not a directory, or symlinked: $path" || return
    [ "$(stat -c %u "$path" 2>/dev/null)" = "$(id -u)" ] \
        || bepis_hls_cache_die 65 "$label is owned by another user: $path" || return
}

bepis_hls_cache_ensure_parent() {
    if [ -e "$BEPIS_HLS_CACHE_PARENT" ] || [ -L "$BEPIS_HLS_CACHE_PARENT" ]; then
        bepis_hls_cache_validate_owned_directory "$BEPIS_HLS_CACHE_PARENT" "cache parent" || return
    else
        mkdir -p "$BEPIS_HLS_CACHE_PARENT" \
            || bepis_hls_cache_die 73 "cannot create cache parent: $BEPIS_HLS_CACHE_PARENT" || return
    fi
    chmod 700 "$BEPIS_HLS_CACHE_PARENT"
    if [ -e "$BEPIS_HLS_CACHE_LOCKS" ] || [ -L "$BEPIS_HLS_CACHE_LOCKS" ]; then
        bepis_hls_cache_validate_owned_directory "$BEPIS_HLS_CACHE_LOCKS" "cache lock directory" || return
    else
        mkdir -m 700 "$BEPIS_HLS_CACHE_LOCKS" \
            || bepis_hls_cache_die 73 "cannot create cache lock directory" || return
    fi
    chmod 700 "$BEPIS_HLS_CACHE_LOCKS"
}

bepis_hls_cache_expected_marker() {
    jq -cn \
        --argjson uid "$(id -u)" \
        --arg workspace "$BEPIS_HLS_CACHE_WORKSPACE_PATH" \
        --arg workspaceId "$BEPIS_HLS_CACHE_WORKSPACE_ID" \
        '{version: 1, uid: $uid, workspace: $workspace, workspaceId: $workspaceId}'
}

bepis_hls_cache_validate_root() {
    local marker="$BEPIS_HLS_CACHE_ROOT/.bepis-hls-cache"
    bepis_hls_cache_validate_owned_directory "$BEPIS_HLS_CACHE_ROOT" "cache root" || return
    [ -f "$marker" ] && [ ! -L "$marker" ] \
        || bepis_hls_cache_die 65 "cache root has no trusted marker: $BEPIS_HLS_CACHE_ROOT" || return
    [ "$(stat -c %u "$marker" 2>/dev/null)" = "$(id -u)" ] \
        || bepis_hls_cache_die 65 "cache marker is owned by another user: $marker" || return
    jq -e \
        --argjson uid "$(id -u)" \
        --arg workspace "$BEPIS_HLS_CACHE_WORKSPACE_PATH" \
        --arg workspaceId "$BEPIS_HLS_CACHE_WORKSPACE_ID" '
        type == "object"
        and (keys | sort == ["uid", "version", "workspace", "workspaceId"])
        and .version == 1
        and .uid == $uid
        and .workspace == $workspace
        and .workspaceId == $workspaceId
    ' "$marker" >/dev/null 2>&1 \
        || bepis_hls_cache_die 65 "cache root has a foreign or malformed marker: $BEPIS_HLS_CACHE_ROOT" || return
}

# Caller must hold the workspace lifecycle lock before creating or validating
# the cache. This prevents an approved clear racing an HLS launch.
bepis_hls_cache_prepare_locked() {
    local registry_lock="$BEPIS_HLS_CACHE_PARENT/registry.lock" created=false temporary
    exec {BEPIS_HLS_CACHE_REGISTRY_FD}>>"$registry_lock"
    flock "$BEPIS_HLS_CACHE_REGISTRY_FD"
    if [ -e "$BEPIS_HLS_CACHE_ROOT" ] || [ -L "$BEPIS_HLS_CACHE_ROOT" ]; then
        bepis_hls_cache_validate_root || return
    else
        mkdir -m 700 "$BEPIS_HLS_CACHE_ROOT" \
            || bepis_hls_cache_die 73 "cannot create cache root: $BEPIS_HLS_CACHE_ROOT" || return
        created=true
        temporary="$(mktemp "$BEPIS_HLS_CACHE_ROOT/.marker.XXXXXX")"
        if ! bepis_hls_cache_expected_marker >"$temporary" \
            || ! mv "$temporary" "$BEPIS_HLS_CACHE_ROOT/.bepis-hls-cache"; then
            rm -f "$temporary"
            [ "$created" = false ] || rm -rf --one-file-system "$BEPIS_HLS_CACHE_ROOT"
            bepis_hls_cache_die 73 "cannot publish cache marker" || return
        fi
    fi
    chmod 700 "$BEPIS_HLS_CACHE_ROOT"
    if [ -e "$BEPIS_HLS_CACHE_ROOT/xdg" ] || [ -L "$BEPIS_HLS_CACHE_ROOT/xdg" ]; then
        bepis_hls_cache_validate_owned_directory "$BEPIS_HLS_CACHE_ROOT/xdg" "XDG cache directory" || return
    else
        mkdir "$BEPIS_HLS_CACHE_ROOT/xdg"
    fi
    chmod 700 "$BEPIS_HLS_CACHE_ROOT/xdg"
    flock -u "$BEPIS_HLS_CACHE_REGISTRY_FD"
    eval "exec ${BEPIS_HLS_CACHE_REGISTRY_FD}>&-"
}

bepis_hls_cache_bytes() {
    local path="$1" bytes
    bytes="$(du -s -B1 "$path" 2>/dev/null | awk '{print $1}')"
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    printf '%s\n' "$bytes"
}

bepis_hls_cache_lock_active() {
    [ -f "$BEPIS_HLS_CACHE_LIFECYCLE_LOCK" ] || return 1
    exec {BEPIS_HLS_CACHE_PROBE_FD}>>"$BEPIS_HLS_CACHE_LIFECYCLE_LOCK"
    if flock -n -x "$BEPIS_HLS_CACHE_PROBE_FD"; then
        flock -u "$BEPIS_HLS_CACHE_PROBE_FD"
        eval "exec ${BEPIS_HLS_CACHE_PROBE_FD}>&-"
        return 1
    fi
    eval "exec ${BEPIS_HLS_CACHE_PROBE_FD}>&-"
    return 0
}

bepis_hls_cache_status_json_for_identity() {
    local state="absent" active=false bytes=0 filesystem="absent"
    if [ -e "$BEPIS_HLS_CACHE_ROOT" ] || [ -L "$BEPIS_HLS_CACHE_ROOT" ]; then
        bepis_hls_cache_validate_root || return
        state="present"
        bytes="$(bepis_hls_cache_bytes "$BEPIS_HLS_CACHE_ROOT")"
        filesystem="$(stat -f -c %T "$BEPIS_HLS_CACHE_ROOT" 2>/dev/null || printf unknown)"
        if bepis_hls_cache_lock_active; then active=true; fi
    fi
    jq -cn \
        --arg state "$state" --arg root "$BEPIS_HLS_CACHE_ROOT" \
        --arg workspace "$BEPIS_HLS_CACHE_WORKSPACE_PATH" \
        --arg workspaceId "$BEPIS_HLS_CACHE_WORKSPACE_ID" \
        --arg filesystem "$filesystem" --argjson bytes "$bytes" --argjson active "$active" \
        '{state: $state, root: $root, workspace: $workspace, workspaceId: $workspaceId,
          filesystem: $filesystem, bytes: $bytes, active: $active}'
}

bepis_hls_cache_clear_identity() {
    local apply="$1"
    if [ ! -e "$BEPIS_HLS_CACHE_ROOT" ] && [ ! -L "$BEPIS_HLS_CACHE_ROOT" ]; then
        return 0
    fi
    bepis_hls_cache_ensure_parent || return
    exec {BEPIS_HLS_CACHE_CLEAR_FD}>>"$BEPIS_HLS_CACHE_LIFECYCLE_LOCK"
    if ! flock -n -x "$BEPIS_HLS_CACHE_CLEAR_FD"; then
        eval "exec ${BEPIS_HLS_CACHE_CLEAR_FD}>&-"
        bepis_hls_cache_die 75 "active HLS owns cache: $BEPIS_HLS_CACHE_ROOT" || return
    fi
    bepis_hls_cache_validate_root || return
    if [ "$apply" = true ]; then
        rm -rf --one-file-system "$BEPIS_HLS_CACHE_ROOT"
    fi
    flock -u "$BEPIS_HLS_CACHE_CLEAR_FD"
    eval "exec ${BEPIS_HLS_CACHE_CLEAR_FD}>&-"
}
