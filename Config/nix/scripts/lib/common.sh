# Shared shell helpers for ihp-roster devenv scripts.

ihp_roster_detect_cpu_count() {
    if command -v getconf >/dev/null 2>&1; then
        getconf _NPROCESSORS_ONLN 2>/dev/null && return 0
    fi
    if command -v nproc >/dev/null 2>&1; then
        nproc && return 0
    fi
    printf '1\n'
}

ihp_roster_process_group_pids() {
    local pgid="$1"
    pgrep -g "$pgid" 2>/dev/null | tr '\n' ' ' || true
}

ihp_roster_listen_ports_for_pids() {
    local pids="$1"
    local lsof_pid_args=()
    local pid

    for pid in $pids; do
        lsof_pid_args+=(-p "$pid")
    done

    if [ "${#lsof_pid_args[@]}" -eq 0 ]; then
        return 1
    fi

    lsof -Pan -iTCP -sTCP:LISTEN "${lsof_pid_args[@]}" 2>/dev/null \
        | awk 'NR > 1 { split($9, parts, ":"); print parts[length(parts)] }' \
        | sort -n -u
}
