# shellcheck shell=bash
# Shared GHC option discovery for ihp-roster devenv scripts.

ihp_roster_ghc_opts() {
    make print-ghc-options GHC_RTS_FLAGS="" 2>/dev/null \
        | sed 's/-iIHP[^ ]* //g; s/-fbyte-code//g'
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

    local workspace parent workspace_id root marker temporary
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

    workspace_id="$(printf '%s' "$workspace" | sha256sum | cut -c1-12)"
    root="$parent/$workspace_id"
    marker="$root/.bepis-compiler-tmp"
    if [ -e "$root" ] || [ -L "$root" ]; then
        [ -d "$root" ] && [ ! -L "$root" ] \
            && [ "$(stat -c %u "$root" 2>/dev/null)" = "$(id -u)" ] \
            && [ -f "$marker" ] && [ ! -L "$marker" ] \
            && [ "$(cat "$marker" 2>/dev/null)" = "$workspace" ] || {
                echo "compiler-tmp: foreign or unsafe workspace temp root: $root" >&2
                return 65
            }
    else
        mkdir -m 700 "$root" || return 73
        temporary="$(mktemp "$root/.marker.XXXXXX")"
        printf '%s\n' "$workspace" >"$temporary"
        mv "$temporary" "$marker"
    fi
    chmod 700 "$root"
    export TMPDIR="$root"
    ihp_roster_report_tmp_pressure "$tmp_path" "$free_bytes" "$threshold" "using $TMPDIR"
}

ihp_roster_prepare_ghc_build_dir() {
    local build_dir="$1"
    local ghc_opts="$2"
    local fingerprint stamp_file previous_fingerprint
    fingerprint="$(printf '%s\n%s\n' "$(ghc --numeric-version)" "$ghc_opts" | sha256sum | cut -d' ' -f1)"
    stamp_file="$build_dir/ghc-options.sha256"
    previous_fingerprint="$(cat "$stamp_file" 2>/dev/null || true)"

    if [ "$previous_fingerprint" != "$fingerprint" ]; then
        rm -rf "$build_dir/obj" "$build_dir/hi"
    fi

    mkdir -p "$build_dir/obj" "$build_dir/hi"
    printf '%s\n' "$fingerprint" > "$stamp_file"
}
