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

profile_runtime_process_group_totals() {
    local process_group_id="$1"
    local stat_file stat_line stat_fields process_group process_id rss_kib
    local total_rss_kib=0
    local total_cpu_ticks=0
    for stat_file in /proc/[0-9]*/stat; do
        [ -r "$stat_file" ] || continue
        stat_line=$(cat "$stat_file" 2>/dev/null) || continue
        stat_fields="${stat_line##*) }"
        set -- $stat_fields
        process_group="${3:-}"
        [ "$process_group" = "$process_group_id" ] || continue
        process_id="${stat_file#/proc/}"
        process_id="${process_id%/stat}"
        rss_kib=$(awk '/^VmRSS:/ { print $2; found=1 } END { if (!found) print 0 }' "/proc/$process_id/status" 2>/dev/null || printf 0)
        total_rss_kib=$((total_rss_kib + rss_kib))
        total_cpu_ticks=$((total_cpu_ticks + ${12:-0} + ${13:-0}))
    done
    printf '%s\t%s\n' "$total_rss_kib" "$total_cpu_ticks"
}

sample_profile_runtime_resources() {
    local server_pid="$1" samples_file="$2" profiling_enabled="$3" database_socket="$4" database_name="$5"
    : > "$samples_file"
    while kill -0 "$server_pid" 2>/dev/null && [ -r "/proc/$server_pid/stat" ]; do
        local timestamp_ns rss_kib cpu_ticks active_connections=0 open_connections=0 server_waiters=0
        timestamp_ns=$(date +%s%N)
        IFS=$'\t' read -r rss_kib cpu_ticks < <(profile_runtime_process_group_totals "$server_pid")
        if [ "$profiling_enabled" = "1" ]; then
            IFS='|' read -r active_connections open_connections server_waiters < <(
                psql -X -qAt -h "$database_socket" -d "$database_name" -c \
                    "SELECT count(*) FILTER (WHERE pid <> pg_backend_pid() AND state = 'active'), count(*) FILTER (WHERE pid <> pg_backend_pid()), count(*) FILTER (WHERE pid <> pg_backend_pid() AND wait_event_type IS NOT NULL AND state = 'active') FROM pg_stat_activity WHERE datname = current_database()" \
                    2>/dev/null || printf '0|0|0\n'
            )
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$timestamp_ns" "$rss_kib" "$cpu_ticks" "$active_connections" "$open_connections" "$server_waiters" \
            >> "$samples_file"
        sleep 0.25
    done
}

stop_profile_runtime_sampler() {
    local sampler_pid_file="$1"
    if [ -f "$sampler_pid_file" ]; then
        local sampler_pid
        sampler_pid=$(cat "$sampler_pid_file")
        kill -TERM "$sampler_pid" 2>/dev/null || true
        wait "$sampler_pid" 2>/dev/null || true
        rm -f "$sampler_pid_file"
    fi
}

finalize_profile_runtime_resources() {
    local samples_file="$1" summary_file="$2"
    local clock_ticks first_timestamp last_timestamp first_ticks last_ticks peak_rss sample_count
    clock_ticks=$(getconf CLK_TCK)
    sample_count=$(wc -l < "$samples_file")
    if [ "$sample_count" -eq 0 ]; then
        echo "Profile runtime sampler produced no samples" >&2
        return 1
    fi
    first_timestamp=$(awk 'NR == 1 { print $1 }' "$samples_file")
    last_timestamp=$(awk 'END { print $1 }' "$samples_file")
    first_ticks=$(awk 'NR == 1 { print $3 }' "$samples_file")
    last_ticks=$(awk 'END { print $3 }' "$samples_file")
    peak_rss=$(awk 'BEGIN { peak=0 } $2 > peak { peak=$2 } END { print peak }' "$samples_file")
    jq -n \
        --argjson sampleCount "$sample_count" \
        --argjson peakRssKiB "$peak_rss" \
        --argjson elapsedNanoseconds "$((last_timestamp - first_timestamp))" \
        --argjson cpuTicks "$((last_ticks - first_ticks))" \
        --argjson clockTicksPerSecond "$clock_ticks" \
        '{sampleCount:$sampleCount,peakRssKiB:$peakRssKiB,elapsedSeconds:($elapsedNanoseconds / 1000000000),cpuSeconds:($cpuTicks / $clockTicksPerSecond)}' \
        > "$summary_file"
}
