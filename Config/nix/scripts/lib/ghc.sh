# Shared GHC option discovery for ihp-roster devenv scripts.

ihp_roster_ghc_opts() {
    make print-ghc-options GHC_RTS_FLAGS="" 2>/dev/null \
        | sed 's/-iIHP[^ ]* //g; s/-fbyte-code//g'
}
