# shellcheck shell=bash
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

ihp_roster_configure_test_postgres() {
    local mode="${TEST_POSTGRES_MODE:-}"
    local scripts_root
    scripts_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    if [ -z "$mode" ]; then
        if [ -n "${TEST_DB_SOCKET:-}" ]; then
            mode=external
        else
            mode=managed
        fi
    fi

    case "$mode" in
        managed)
            TEST_DB_SOCKET="$("$scripts_root/db/test-postgres" ensure)"
            ;;
        external)
            if [ -z "${TEST_DB_SOCKET:-}" ]; then
                echo "TEST_POSTGRES_MODE=external requires an explicit TEST_DB_SOCKET" >&2
                return 64
            fi
            ;;
        *)
            echo "TEST_POSTGRES_MODE must be managed or external; got: $mode" >&2
            return 64
            ;;
    esac

    TEST_POSTGRES_MODE="$mode"
    PGHOST="$TEST_DB_SOCKET"
    export TEST_POSTGRES_MODE TEST_DB_SOCKET PGHOST
}

ihp_roster_report_test_postgres() {
    if [ "${TEST_POSTGRES_REPORT:-1}" = "0" ]; then
        return 0
    fi

    local details data_directory durability_profile fs_details
    local fsync_setting synchronous_commit_setting full_page_writes_setting
    details="$(
        psql -X -q -h "$TEST_DB_SOCKET" -d postgres -At -F $'\t' \
            -v ON_ERROR_STOP=1 -c \
            "SELECT current_setting('data_directory'), current_setting('fsync'), current_setting('synchronous_commit'), current_setting('full_page_writes')"
    )"
    IFS=$'\t' read -r data_directory fsync_setting synchronous_commit_setting full_page_writes_setting <<< "$details"
    fs_details="$(findmnt -n -T "$data_directory" -o FSTYPE,SOURCE 2>/dev/null | xargs || true)"
    if [ -z "$fs_details" ]; then
        fs_details="unknown"
    fi
    if [ "$TEST_POSTGRES_MODE" = "managed" ]; then
        durability_profile="${TEST_POSTGRES_DURABILITY:-disposable}"
    else
        durability_profile=external
    fi

    printf 'Hspec PostgreSQL: mode=%s durability=%s data=%s socket=%s filesystem=%s fsync=%s synchronous_commit=%s full_page_writes=%s\n' \
        "$TEST_POSTGRES_MODE" "$durability_profile" "$data_directory" "$TEST_DB_SOCKET" \
        "$fs_details" "$fsync_setting" "$synchronous_commit_setting" "$full_page_writes_setting"
}
