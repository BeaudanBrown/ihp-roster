#!/usr/bin/env bash
# shellcheck shell=bash

bepis_workspace_resource_warn() {
    echo "workspace-cpu: warning: $*" >&2
}

bepis_workspace_resource_names() {
    local common_dir="$1"
    local kind="$2"
    local slot="$3"
    local repository_id workspace_id
    repository_id="$(printf '%s' "$common_dir" | sha256sum | cut -c1-12)"
    case "$kind" in
        primary) workspace_id="primary" ;;
        epic)
            [[ "$slot" =~ ^[1-9][0-9]*$ ]] || return 64
            workspace_id="epic$slot"
            ;;
        *) return 64 ;;
    esac
    BEPIS_WORKSPACE_RESOURCE_REPOSITORY_ID="$repository_id"
    BEPIS_WORKSPACE_RESOURCE_PARENT_SLICE="bepis-${repository_id}.slice"
    BEPIS_WORKSPACE_RESOURCE_SLICE="bepis-${repository_id}-${workspace_id}.slice"
}

bepis_workspace_resource_systemctl() {
    local command="${BEPIS_SYSTEMCTL_COMMAND:-systemctl}"
    "$command" --user "$@"
}

bepis_workspace_resource_systemd_run() {
    local command="${BEPIS_SYSTEMD_RUN_COMMAND:-systemd-run}"
    "$command" --user "$@"
}

bepis_workspace_resource_available() {
    [ "$(stat -fc %T /sys/fs/cgroup 2>/dev/null || true)" = cgroup2fs ] \
        && command -v "${BEPIS_SYSTEMCTL_COMMAND:-systemctl}" >/dev/null 2>&1 \
        && command -v "${BEPIS_SYSTEMD_RUN_COMMAND:-systemd-run}" >/dev/null 2>&1 \
        && bepis_workspace_resource_systemctl is-system-running >/dev/null 2>&1
}

bepis_workspace_resource_prepare() {
    local common_dir="$1"
    local kind="$2"
    local slot="$3"
    bepis_workspace_resource_names "$common_dir" "$kind" "$slot" || return
    bepis_workspace_resource_systemctl start "$BEPIS_WORKSPACE_RESOURCE_PARENT_SLICE" "$BEPIS_WORKSPACE_RESOURCE_SLICE" \
        && bepis_workspace_resource_systemctl set-property --runtime "$BEPIS_WORKSPACE_RESOURCE_SLICE" CPUWeight=100
}

bepis_workspace_resource_current_cgroup() {
    awk -F: '$1 == "0" {print $3; exit}' /proc/self/cgroup 2>/dev/null
}

bepis_workspace_resource_in_expected_slice() {
    local current
    current="$(bepis_workspace_resource_current_cgroup)"
    [[ "/$current/" == *"/$BEPIS_WORKSPACE_RESOURCE_SLICE/"* ]]
}

bepis_workspace_resource_exec() {
    local common_dir="$1"
    local kind="$2"
    local slot="$3"
    shift 3

    if [ "${BEPIS_WORKSPACE_CPU_SHARING:-on}" = off ]; then
        bepis_workspace_resource_warn "CPU sharing explicitly disabled; launching uncontained"
        exec "$@"
    fi
    if ! bepis_workspace_resource_available; then
        bepis_workspace_resource_warn "cgroup v2 user-systemd unavailable; launching uncontained"
        exec "$@"
    fi
    if ! bepis_workspace_resource_prepare "$common_dir" "$kind" "$slot"; then
        bepis_workspace_resource_warn "cannot prepare equal-weight workspace slice; launching uncontained"
        exec "$@"
    fi
    if bepis_workspace_resource_in_expected_slice; then
        exec "$@"
    fi
    exec "${BEPIS_SYSTEMD_RUN_COMMAND:-systemd-run}" --user --scope --quiet --collect \
        --slice="$BEPIS_WORKSPACE_RESOURCE_SLICE" -- "$@"
}

bepis_workspace_resource_status() {
    local common_dir="$1"
    local kind="$2"
    local slot="$3"
    bepis_workspace_resource_names "$common_dir" "$kind" "$slot" || return

    local available=false load_state="not-found" active_state="inactive" cpu_weight=100 tasks=0
    if bepis_workspace_resource_available; then
        available=true
        local properties
        properties="$(bepis_workspace_resource_systemctl show "$BEPIS_WORKSPACE_RESOURCE_SLICE" \
            --property=LoadState --property=ActiveState --property=CPUWeight --property=TasksCurrent 2>/dev/null || true)"
        if [ -n "$properties" ]; then
            load_state="$(awk -F= '$1 == "LoadState" {print $2}' <<<"$properties")"
            active_state="$(awk -F= '$1 == "ActiveState" {print $2}' <<<"$properties")"
            local reported_weight reported_tasks
            reported_weight="$(awk -F= '$1 == "CPUWeight" {print $2}' <<<"$properties")"
            reported_tasks="$(awk -F= '$1 == "TasksCurrent" {print $2}' <<<"$properties")"
            [[ "$reported_weight" =~ ^[0-9]+$ ]] && cpu_weight="$reported_weight"
            [[ "$reported_tasks" =~ ^[0-9]+$ ]] && tasks="$reported_tasks"
        fi
    fi
    jq -cn \
        --arg repositoryId "$BEPIS_WORKSPACE_RESOURCE_REPOSITORY_ID" \
        --arg parentSlice "$BEPIS_WORKSPACE_RESOURCE_PARENT_SLICE" \
        --arg slice "$BEPIS_WORKSPACE_RESOURCE_SLICE" \
        --argjson available "$available" --arg loadState "$load_state" --arg activeState "$active_state" \
        --argjson cpuWeight "$cpu_weight" --argjson processes "$tasks" \
        '{repositoryId: $repositoryId, parentSlice: $parentSlice, slice: $slice, available: $available, loadState: $loadState, activeState: $activeState, cpuWeight: $cpuWeight, processes: $processes, contained: ($processes > 0)}'
}

bepis_workspace_pid_is_caller_ancestor() {
    local wanted="$1"
    local current="$BASHPID" parent
    while [[ "$current" =~ ^[1-9][0-9]*$ ]]; do
        [ "$current" != "$wanted" ] || return 0
        parent="$(awk '/^PPid:/ {print $2; exit}' "/proc/$current/status" 2>/dev/null || true)"
        [ -n "$parent" ] && [ "$parent" != "$current" ] || break
        current="$parent"
    done
    return 1
}

bepis_workspace_pid_in_path() {
    local pid="$1"
    local path="$2"
    local proc="/proc/$pid" cwd
    [ -r "$proc/status" ] || return 1
    [ "$(awk '/^Uid:/ {print $2; exit}' "$proc/status" 2>/dev/null)" = "$(id -u)" ] || return 1
    cwd="$(readlink "$proc/cwd" 2>/dev/null || true)"
    [ "$cwd" = "$path" ] || [[ "$cwd" == "$path/"* ]]
}

bepis_workspace_processes_in_path() {
    local path="$1"
    local rows='[]' proc pid cwd command rss cpu
    local caller_ancestors=" " current="$BASHPID" parent
    while [[ "$current" =~ ^[1-9][0-9]*$ ]]; do
        caller_ancestors+="$current "
        parent="$(awk '/^PPid:/ {print $2; exit}' "/proc/$current/status" 2>/dev/null || true)"
        [ -n "$parent" ] && [ "$parent" != "$current" ] || break
        current="$parent"
    done
    for proc in /proc/[0-9]*; do
        pid="${proc##*/}"
        [[ "$caller_ancestors" == *" $pid "* ]] && continue
        bepis_workspace_pid_in_path "$pid" "$path" || continue
        cwd="$(readlink "$proc/cwd" 2>/dev/null || true)"
        # Kernel command lines can exceed the per-process argument limit when
        # forwarded to jq (notably GHC/HLS cradles). Status only needs a bounded
        # diagnostic preview and executable classification.
        command="$(head -c 8192 "$proc/cmdline" 2>/dev/null | tr '\0' ' ' || true)"
        rss="$(awk '/^VmRSS:/ {print $2; exit}' "$proc/status" 2>/dev/null || true)"
        [[ "$rss" =~ ^[0-9]+$ ]] || rss=0
        cpu="$(ps -p "$pid" -o pcpu= 2>/dev/null | awk '{printf "%.1f", $1}' || true)"
        [[ "$cpu" =~ ^[0-9]+([.][0-9]+)?$ ]] || cpu=0
        rows="$(jq -c \
            --argjson pid "$pid" --arg cwd "$cwd" --arg command "$command" \
            --argjson cpuPercent "$cpu" --argjson rssKiB "$rss" \
            '. + [{pid: $pid, cwd: $cwd, command: $command, cpuPercent: $cpuPercent, rssKiB: $rssKiB}]' \
            <<<"$rows")"
    done
    printf '%s\n' "$rows"
}

bepis_workspace_hls_status() {
    local path="$1"
    local workspace_processes rows='[]' row pid command rss cpu elapsed
    local cache_base cache_bytes latest_mtime indexing_active now fd target file size mtime
    workspace_processes="$(bepis_workspace_processes_in_path "$path")"
    now="$(date +%s)"

    while IFS= read -r row; do
        command="$(jq -r '.command' <<<"$row")"
        [[ "$command" == *haskell-language-server* ]] || continue
        pid="$(jq -r '.pid' <<<"$row")"
        [ -r "/proc/$pid/status" ] || continue

        rss="$(awk '/^VmRSS:/ {print $2; exit}' "/proc/$pid/status" 2>/dev/null || true)"
        [[ "$rss" =~ ^[0-9]+$ ]] || rss=0
        cpu="$(ps -p "$pid" -o pcpu= 2>/dev/null | awk '{printf "%.1f", $1}' || true)"
        [[ "$cpu" =~ ^[0-9]+([.][0-9]+)?$ ]] || cpu=0
        elapsed="$(ps -p "$pid" -o etimes= 2>/dev/null | tr -d ' ' || true)"
        [[ "$elapsed" =~ ^[0-9]+$ ]] || elapsed=0

        cache_base=""
        for fd in /proc/"$pid"/fd/*; do
            target="$(readlink "$fd" 2>/dev/null || true)"
            case "$target" in
                *.hiedb) cache_base="$target"; break ;;
                *.hiedb-wal) cache_base="${target%-wal}"; break ;;
                *.hiedb-shm) cache_base="${target%-shm}"; break ;;
            esac
        done

        cache_bytes=0
        latest_mtime=0
        if [ -n "$cache_base" ]; then
            for file in "$cache_base" "$cache_base-wal" "$cache_base-shm"; do
                [ -f "$file" ] || continue
                size="$(stat -c %s "$file" 2>/dev/null || printf 0)"
                mtime="$(stat -c %Y "$file" 2>/dev/null || printf 0)"
                [[ "$size" =~ ^[0-9]+$ ]] && cache_bytes=$((cache_bytes + size))
                [[ "$mtime" =~ ^[0-9]+$ ]] && [ "$mtime" -gt "$latest_mtime" ] && latest_mtime="$mtime"
            done
        fi
        indexing_active=false
        if [ "$latest_mtime" -gt 0 ] && [ $((now - latest_mtime)) -le 10 ]; then
            indexing_active=true
        fi

        rows="$(jq -c \
            --argjson pid "$pid" \
            --argjson cpuPercent "$cpu" \
            --argjson rssKiB "$rss" \
            --argjson elapsedSeconds "$elapsed" \
            --arg cachePath "$cache_base" \
            --argjson cacheBytes "$cache_bytes" \
            --argjson indexingActive "$indexing_active" \
            '. + [{pid: $pid, cpuPercent: $cpuPercent, rssKiB: $rssKiB,
                    elapsedSeconds: $elapsedSeconds,
                    cachePath: (if $cachePath == "" then null else $cachePath end),
                    cacheBytes: $cacheBytes, indexingActive: $indexingActive}]' <<<"$rows")"
    done < <(jq -c '.[]' <<<"$workspace_processes")

    jq -c '
        {processes: ., totalRssKiB: ([.[].rssKiB] | add // 0),
         cacheBytes: ([.[].cacheBytes] | add // 0),
         indexingActive: any(.[]; .indexingActive)}
    ' <<<"$rows"
}

bepis_workspace_uncontained_processes_in_path() {
    local path="$1"
    local expected_slice="$2"
    local processes result='[]' row pid cgroup
    processes="$(bepis_workspace_processes_in_path "$path")"
    while IFS= read -r row; do
        pid="$(jq -r '.pid' <<<"$row")"
        cgroup="$(awk -F: '$1 == "0" {print $3; exit}' "/proc/$pid/cgroup" 2>/dev/null || true)"
        if [[ "/$cgroup/" != *"/$expected_slice/"* ]]; then
            result="$(jq -c --argjson row "$row" '. + [$row]' <<<"$result")"
        fi
    done < <(jq -c '.[]' <<<"$processes")
    printf '%s\n' "$result"
}

bepis_workspace_resource_terminate() {
    local common_dir="$1"
    local kind="$2"
    local slot="$3"
    local path="$4"
    : "$5" # Runtime report retained in the interface for cleanup evidence.
    local grace_seconds=5
    bepis_workspace_resource_names "$common_dir" "$kind" "$slot" || return

    local systemd_available=false slice_processes=0
    if bepis_workspace_resource_available; then
        systemd_available=true
        slice_processes="$(bepis_workspace_resource_status "$common_dir" "$kind" "$slot" | jq -r '.processes')"
    fi
    local path_processes all_pids
    path_processes="$(bepis_workspace_processes_in_path "$path")"
    # Runtime PID files can be stale and their numeric PIDs can be reused. Only
    # signal independently verified same-user processes rooted in this path;
    # contained descendants are terminated through the exact workspace slice.
    all_pids="$(jq -r -n --argjson paths "$path_processes" '[$paths[].pid] | unique | .[]')"

    if [ "$slice_processes" -gt 0 ]; then
        bepis_workspace_resource_systemctl kill --kill-whom=all --signal=SIGTERM "$BEPIS_WORKSPACE_RESOURCE_SLICE" >/dev/null 2>&1 || true
    fi
    if [ -n "$all_pids" ]; then
        mapfile -t pid_array <<<"$all_pids"
        local pid
        for pid in "${pid_array[@]}"; do
            if [[ "$pid" =~ ^[1-9][0-9]*$ ]] \
                && ! bepis_workspace_pid_is_caller_ancestor "$pid" \
                && bepis_workspace_pid_in_path "$pid" "$path"; then
                kill -TERM "$pid" 2>/dev/null || true
            fi
        done
    fi
    if [ "$slice_processes" -gt 0 ] || [ -n "$all_pids" ]; then
        [ "$grace_seconds" = 0 ] || sleep "$grace_seconds"
    fi
    if [ "$slice_processes" -gt 0 ]; then
        bepis_workspace_resource_systemctl kill --kill-whom=all --signal=SIGKILL "$BEPIS_WORKSPACE_RESOURCE_SLICE" >/dev/null 2>&1 || true
    fi
    if [ -n "$all_pids" ]; then
        for pid in "${pid_array[@]}"; do
            if [[ "$pid" =~ ^[1-9][0-9]*$ ]] \
                && ! bepis_workspace_pid_is_caller_ancestor "$pid" \
                && bepis_workspace_pid_in_path "$pid" "$path"; then
                kill -KILL "$pid" 2>/dev/null || true
            fi
        done
    fi
    if [ "$systemd_available" = true ]; then
        bepis_workspace_resource_systemctl stop "$BEPIS_WORKSPACE_RESOURCE_SLICE" >/dev/null 2>&1 || true
    fi
}
