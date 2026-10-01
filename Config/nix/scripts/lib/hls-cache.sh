#!/usr/bin/env bash
# Legacy-cache inspection helpers only. Owned worktree cache identity, markers,
# locks, status and deletion belong to the independent bepis-artifacts package.

bepis_hls_cache_die() {
    local status="$1"
    shift
    echo "hls-cache: $*" >&2
    return "$status"
}

bepis_hls_cache_validate_owned_directory() {
    local path="$1" label="$2"
    [ -d "$path" ] && [ ! -L "$path" ] \
        || bepis_hls_cache_die 65 "$label is missing, not a directory, or symlinked: $path" || return
    [ "$(stat -c %u "$path" 2>/dev/null)" = "$(id -u)" ] \
        || bepis_hls_cache_die 65 "$label is owned by another user: $path" || return
}

bepis_hls_cache_bytes() {
    local path="$1" bytes
    bytes="$(du -s -B1 "$path" 2>/dev/null | awk '{print $1}')"
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    printf '%s\n' "$bytes"
}
