# shellcheck shell=bash
# Opt-in diagnostics only: emission failure must not replace an owner result.
verification_phase() {
    if [ -n "${BEPIS_VERIFICATION_EVENTS:-}" ]; then
        python3 -S "${BEPIS_SCRIPTS_ROOT:?}/../../../scripts/profiling/verification-measure.py" event \
            --phase "$1" --scope "$2" --edge "$3" "${@:4}" || true
    fi
}

verification_generation_result() {
    if [ "$2" = current ]; then
        verification_phase generation-current "$1" observe
    else
        verification_phase generation-regenerated "$1" observe
    fi
}

# Leave compiler options/cache identity and the uninstrumented path untouched.
verification_ghc() {
    local phase="$1" scope="$2"
    shift 2
    if [ -n "${BEPIS_VERIFICATION_EVENTS:-}" ]; then
        python3 "${BEPIS_SCRIPTS_ROOT:?}/../../../scripts/profiling/verification-ghc.py" ghc "$phase" "$scope" "$@"
    else
        ghc "$@"
    fi
}

verification_phase_result() {
    if [ "$3" -eq 0 ]; then
        verification_phase "$1" "$2" finish
    else
        verification_phase "$1" "$2" fail
    fi
}
