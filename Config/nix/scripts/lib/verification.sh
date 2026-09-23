# shellcheck shell=bash
# Opt-in diagnostics only: emission failure must not replace an owner result.
verification_phase() {
    if [ -n "${BEPIS_VERIFICATION_EVENTS:-}" ]; then
        python3 -S "${BEPIS_SCRIPTS_ROOT:?}/../../../scripts/profiling/verification-measure.py" event \
            --phase "$1" --scope "$2" --edge "$3" "${@:4}" || true
    fi
}

verification_phase_result() {
    if [ "$3" -eq 0 ]; then
        verification_phase "$1" "$2" finish
    else
        verification_phase "$1" "$2" fail
    fi
}
