# shellcheck shell=bash

# Both direnv and the direct Nix fallback must point devenv at the current
# checkout, not Nix's source snapshot. No workspace/runtime state is needed.
bepis_prepare_devenv_flake_args() {
    local checkout root_file
    checkout="$(pwd -P)" || return
    root_file="$checkout/.devenv/root"
    if [[ "$checkout" == *$'\n'* || -L "$checkout/.devenv" || -L "$root_file" ]]; then
        echo "devenv bootstrap: invalid or symlinked checkout state path: $root_file" >&2
        return 64
    fi
    mkdir -p -- "$checkout/.devenv" || return
    if [[ ! -f "$root_file" || "$(<"$root_file")" != "$checkout" ]]; then
        (
            tmp="$(mktemp -- "$root_file.XXXXXX")" || exit
            trap 'rm -f -- "$tmp"' EXIT
            printf %s "$checkout" >"$tmp" && mv -T -- "$tmp" "$root_file"
        ) || return
    fi
    bepis_devenv_flake_args=(
        --override-input devenv-root "file+file://$root_file"
        --accept-flake-config
        --no-write-lock-file
    )
}
