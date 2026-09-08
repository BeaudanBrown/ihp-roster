#!/usr/bin/env bash
# Execution only: patterns, roots, exclusions and match/count policy stay in gates.
# rg and grep use 0/1 for matches/no matches; never hide their other failures.
# A subshell owns cleanup so callers' traps (and piped stdin) remain intact.
authority_scan() (
    local scanner="$1" errors status=0
    shift
    errors="$(mktemp "${TMPDIR:-/tmp}/authority-scan.XXXXXX")" || exit 2
    trap 'rm -f "$errors"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    command "$scanner" "$@" 2>"$errors" || status=$?
    case "$status" in
        0|1) exit 0 ;;
        *)
            printf '%s: %s scan failed (status %s); stderr preview (up to 4096 bytes):\n' "${0##*/}" "$scanner" "$status" >&2
            head -c 4096 "$errors" >&2
            printf '\n' >&2
            exit "$status"
            ;;
    esac
)
