# shellcheck shell=bash
# Shared GHC option discovery for ihp-roster devenv scripts.

ihp_roster_ghc_opts() {
    make print-ghc-options GHC_RTS_FLAGS="" 2>/dev/null \
        | sed 's/-iIHP[^ ]* //g; s/-fbyte-code//g'
}

ihp_roster_prepare_artifacts() {
    [ -z "${IHP_ROSTER_ARTIFACTS_BINARY:-}" ] || return 0
    local launcher scripts_repo
    scripts_repo="$(cd "${BEPIS_SCRIPTS_ROOT:?}/../../.." && pwd)"
    launcher="${BEPIS_TOOLING_LAUNCHER:-$scripts_repo/bin/tooling-run}"
    IHP_ROSTER_ARTIFACTS_BINARY="$("$launcher" artifacts --print-binary)"
    export IHP_ROSTER_ARTIFACTS_BINARY
}

ihp_roster_verification_build_dir() {
    printf '%s\n' "${VERIFICATION_BUILD_DIR:-$PWD/build/Verification}"
}

ihp_roster_report_tmp_pressure() {
    local tmp_path="$1"
    local free_bytes="$2"
    local threshold="$3"
    local action="$4"
    echo "compiler-tmp: $tmp_path has $free_bytes bytes free, less than $threshold; $action" >&2
    if [ "${BEPIS_TMP_PRESSURE_REPORT:-1}" = 1 ] && [ -d "$tmp_path" ]; then
        find "$tmp_path" -mindepth 1 -maxdepth 1 -type d \
            \( -name 'nix-cache' -o -name 'bepis-*' \) -print0 2>/dev/null \
            | xargs -0 -r du -s -B1 2>/dev/null \
            | sort -nr | head -n 8 \
            | awk '{printf "compiler-tmp: consumer bytes=%s path=%s\\n", $1, $2}' >&2 || true
    fi
}

ihp_roster_configure_compiler_tmpdir() {
    # Respect an explicit caller choice while still reporting pressure on the
    # shared tmpfs. The fallback exists only to keep an unexpectedly full
    # tmpfs from aborting compile-heavy project commands.
    local threshold="${BEPIS_TMP_FREE_THRESHOLD_BYTES:-2147483648}"
    local free_bytes="${BEPIS_TMP_FREE_BYTES_OVERRIDE:-}"
    local tmp_path="${BEPIS_TMP_PATH:-/tmp}"
    [[ "$threshold" =~ ^[1-9][0-9]*$ ]] || {
        echo "compiler-tmp: invalid free-space threshold: $threshold" >&2
        return 64
    }
    if [ -z "$free_bytes" ]; then
        free_bytes="$(df -PB1 "$tmp_path" 2>/dev/null | awk 'NR == 2 {print $4}')"
    fi
    [[ "$free_bytes" =~ ^[0-9]+$ ]] || {
        echo "compiler-tmp: cannot determine free bytes for $tmp_path" >&2
        return 69
    }
    [ "$free_bytes" -lt "$threshold" ] || return 0
    if [ -n "${TMPDIR:-}" ]; then
        ihp_roster_report_tmp_pressure "$tmp_path" "$free_bytes" "$threshold" "retaining explicit TMPDIR=$TMPDIR"
        return 0
    fi

    local workspace parent workspace_id root marker artifacts
    workspace="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    workspace="$(realpath "$workspace")"
    parent="${BEPIS_COMPILER_TMP_PARENT:-/var/tmp/bepis-compiler-$(id -u)}"
    if [[ "$parent" == *$'\n'* || "$parent" == *$'\r'* ]] \
        || [ "$(realpath -m "$parent")" != "$parent" ]; then
        echo "compiler-tmp: temp parent must be canonical and must not traverse symlinks: $parent" >&2
        return 65
    fi
    if [ -e "$parent" ] || [ -L "$parent" ]; then
        [ -d "$parent" ] && [ ! -L "$parent" ] \
            && [ "$(stat -c %u "$parent" 2>/dev/null)" = "$(id -u)" ] || {
                echo "compiler-tmp: unsafe temp parent: $parent" >&2
                return 65
            }
    else
        mkdir -p "$parent" || return 73
    fi
    chmod 700 "$parent"

    ihp_roster_prepare_artifacts
    artifacts="$IHP_ROSTER_ARTIFACTS_BINARY"
    workspace_id="$("$artifacts" digest --truncate 12 "$workspace")"
    root="$parent/$workspace_id"
    marker="$root/.bepis-compiler-tmp"
    if [ -e "$root" ] || [ -L "$root" ]; then
        [ -d "$root" ] && [ ! -L "$root" ] \
            && [ "$(stat -c %u "$root" 2>/dev/null)" = "$(id -u)" ] \
            && [ -f "$marker" ] && [ ! -L "$marker" ] \
            && "$artifacts" manifest check "$marker" "$workspace" "compiler-tmp-v1" || {
                echo "compiler-tmp: foreign or unsafe workspace temp root: $root" >&2
                return 65
            }
    else
        mkdir -m 700 "$root" || return 73
        "$artifacts" manifest publish "$marker" "$workspace" "compiler-tmp-v1"
    fi
    chmod 700 "$root"
    export TMPDIR="$root"
    ihp_roster_report_tmp_pressure "$tmp_path" "$free_bytes" "$threshold" "using $TMPDIR"
}

# Persistent verification caches retain only successfully compiled dependencies.
# Callers still pass every validation subject to GHC on every invocation.
ihp_roster_prepare_verification_cache() {
    local purpose="$1" ghc_opts="$2" format="$3" workspace parent root source_hash option_hash stamp artifacts scripts_root inventory
    workspace="$(git rev-parse --show-toplevel)"
    parent="${BEPIS_GHC_CACHE_PARENT:-/var/tmp/bepis-ghc-cache-$(id -u)}"
    ihp_roster_prepare_artifacts
    artifacts="$IHP_ROSTER_ARTIFACTS_BINARY"
    root="$parent/$("$artifacts" digest --truncate 12 "$workspace")/$purpose"
    mkdir -p "$root"
    chmod 700 "$parent" "${root%/$purpose}" "$root"
    exec {IHP_ROSTER_GHC_CACHE_FD}>>"$root/lock"
    flock "$IHP_ROSTER_GHC_CACHE_FD"
    scripts_root="${BEPIS_SCRIPTS_ROOT:?}"
    inventory="${IHP_ROSTER_GHC_CACHE_INVENTORY:-$scripts_root/haskell/verification-cache-inputs}"
    source_hash="$("$artifacts" snapshot --root "$workspace" --inventory-command "$inventory")"
    option_hash="$("$artifacts" digest "$(ghc --numeric-version)" "$ghc_opts" "$format")"
    stamp="$root/fingerprint.json"
    if ! "$artifacts" manifest check "$stamp" "$source_hash" "$option_hash"; then
        rm -rf "$root/obj" "$root/hi"
        mkdir -p "$root/obj" "$root/hi"
        "$artifacts" manifest publish "$stamp" "$source_hash" "$option_hash"
    fi
    IHP_ROSTER_GHC_CACHE_DIR="$root"
}

ihp_roster_release_verification_cache() {
    [ -n "${IHP_ROSTER_GHC_CACHE_FD:-}" ] || return 0
    flock -u "$IHP_ROSTER_GHC_CACHE_FD"
    eval "exec ${IHP_ROSTER_GHC_CACHE_FD}>&-"
}

ihp_roster_prepare_ghc_build_dir() {
    local build_dir="$1"
    local ghc_opts="$2"
    local option_hash stamp_file artifacts
    ihp_roster_prepare_artifacts
    artifacts="$IHP_ROSTER_ARTIFACTS_BINARY"
    option_hash="$("$artifacts" digest "$(ghc --numeric-version)" "$ghc_opts")"
    # Keep the published evidence filename: reachability snapshots hash it.
    stamp_file="$build_dir/ghc-options.sha256"

    if ! "$artifacts" manifest check "$stamp_file" "$option_hash" "ghc-build-dir-v1"; then
        rm -rf "$build_dir/obj" "$build_dir/hi" "$build_dir/hie"
        mkdir -p "$build_dir/obj" "$build_dir/hi"
        "$artifacts" manifest publish "$stamp_file" "$option_hash" "ghc-build-dir-v1"
    else
        mkdir -p "$build_dir/obj" "$build_dir/hi"
    fi
}
