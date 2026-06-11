# Shared profiling server helpers.
# Scripts sourcing this file must set PROFILE_PID_FILE before using
# cleanup_profile_server.

_ihp_roster_profile_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$_ihp_roster_profile_lib_dir/common.sh"
unset _ihp_roster_profile_lib_dir

process_group_pids() {
    ihp_roster_process_group_pids "$@"
}

detect_profile_base_url() {
    local pgid="$1"
    local pids ports port
    pids=$(process_group_pids "$pgid")
    if [ -z "$pids" ]; then
        return 1
    fi

    ports=$(ihp_roster_listen_ports_for_pids "$pids")

    for port in $ports; do
        if curl -fsS "http://127.0.0.1:$port/NewSession" 2>/dev/null | grep -q 'id="email"'; then
            printf 'http://127.0.0.1:%s\n' "$port"
            return 0
        fi
    done

    return 1
}

cleanup_profile_server() {
    if [ -f "$PROFILE_PID_FILE" ]; then
        local pid
        pid=$(cat "$PROFILE_PID_FILE")
        kill -TERM -"$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
        rm -f "$PROFILE_PID_FILE"
    fi
}
