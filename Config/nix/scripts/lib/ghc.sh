# Shared GHC option discovery for ihp-roster devenv scripts.

ihp_roster_ghc_opts() {
    make print-ghc-options GHC_RTS_FLAGS="" 2>/dev/null \
        | sed 's/-iIHP[^ ]* //g; s/-fbyte-code//g'
}

ihp_roster_verification_build_dir() {
    printf '%s\n' "${VERIFICATION_BUILD_DIR:-$PWD/build/Verification}"
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
