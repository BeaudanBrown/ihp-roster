#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C

usage() {
    cat <<'EOF'
Usage: collect-inventory.sh [--output .pi/tmp/maintenance-audit/RUN] [--since PERIOD]

Collects bounded, read-only repository inventory for a maintenance audit.
Output is restricted to .pi/tmp/maintenance-audit/. Default PERIOD is
"180 days ago". Rankings are discovery signals, not findings.
EOF
}

die() {
    printf 'collect-inventory: %s\n' "$*" >&2
    exit 1
}

output=""
since="180 days ago"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output)
            [ "$#" -ge 2 ] || die "--output requires a path"
            output="$2"
            shift 2
            ;;
        --since)
            [ "$#" -ge 2 ] || die "--since requires a Git date expression"
            since="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

for command in git realpath sort awk wc grep sed date find tr mktemp; do
    command -v "$command" >/dev/null 2>&1 || die "required command unavailable: $command"
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a Git worktree"
repo_root="$(realpath "$repo_root")"
head_sha="$(git -C "$repo_root" rev-parse HEAD)"
short_sha="$(git -C "$repo_root" rev-parse --short=8 HEAD)"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
temp_root="$repo_root/.pi/tmp/maintenance-audit"
mkdir -p "$temp_root"
temp_root="$(realpath "$temp_root")"

if [ -z "$output" ]; then
    output="$temp_root/$timestamp-$short_sha"
elif [[ "$output" != /* ]]; then
    output="$repo_root/$output"
fi
output="$(realpath -m "$output")"
case "$output/" in
    "$temp_root"/*/) ;;
    *) die "output must be beneath $temp_root" ;;
esac

if [ -d "$output" ] && [ -n "$(find "$output" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
    die "output directory is not empty: $output"
fi
mkdir -p "$output"

scratch="$(mktemp -d "$temp_root/.inventory.XXXXXX")"
cleanup() {
    rm -rf "$scratch"
}
trap cleanup EXIT

branch="$(git -C "$repo_root" branch --show-current)"
tracked_count="$(git -C "$repo_root" ls-files | wc -l | tr -d ' ')"
dirty_count="$(git -C "$repo_root" status --porcelain=v1 | wc -l | tr -d ' ')"

cat >"$output/metadata.txt" <<EOF
run_utc=$timestamp
repository=$repo_root
branch=$branch
head=$head_sha
history_since=$since
tracked_files=$tracked_count
dirty_entries=$dirty_count
EOF

git -C "$repo_root" status --short --branch >"$output/git-status.txt"
git -C "$repo_root" worktree list --porcelain >"$output/git-worktrees.txt"

metrics="$scratch/file-metrics.tsv"
: >"$metrics"
while IFS= read -r -d '' path; do
    [ -f "$repo_root/$path" ] || continue
    case "$path" in
        *.hs|*.lhs|*.sql|*.ts|*.tsx|*.js|*.mjs|*.cjs|*.css|*.scss|*.md|*.markdown|*.sh|*.bash|*.nix|*.json|*.yaml|*.yml)
            ;;
        *) continue ;;
    esac

    lines="$(wc -l <"$repo_root/$path" | tr -d ' ')"
    bytes="$(wc -c <"$repo_root/$path" | tr -d ' ')"
    case "$path" in
        vendor/*)
            class="vendor"
            ;;
        build/Generated/*|frontend/ts/generated/*|static/app*.js)
            class="generated"
            ;;
        Test/*|e2e/*|*Spec.hs|*-test|*/test/*|*/tests/*)
            class="test"
            ;;
        docs/*|specs/*|*.md|*.markdown)
            class="docs"
            ;;
        *)
            class="source"
            ;;
    esac
    basename="${path##*/}"
    case "$basename" in
        *.*) extension="${basename##*.}" ;;
        *) extension="(none)" ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$lines" "$bytes" "$class" "$extension" "$path" >>"$metrics"
done < <(git -C "$repo_root" ls-files -z)

write_ranked() {
    local destination="$1"
    local selector="$2"
    {
        printf 'lines\tbytes\tclass\textension\tpath\n'
        if [ "$selector" = all ]; then
            sort -t $'\t' -k1,1nr -k2,2nr -k5,5 "$metrics" | sed -n '1,250p'
        else
            awk -F '\t' -v class="$selector" '$3 == class' "$metrics" \
                | sort -t $'\t' -k1,1nr -k2,2nr -k5,5 \
                | sed -n '1,250p'
        fi
    } >"$destination"
}

write_ranked "$output/largest-tracked-files.tsv" all
write_ranked "$output/largest-source-files.tsv" source
write_ranked "$output/largest-test-files.tsv" test
write_ranked "$output/generated-files.tsv" generated

{
    printf 'files\tlines\tbytes\tarea\n'
    awk -F '\t' '
        {
            path = $5
            split(path, pieces, "/")
            area = (path ~ /\//) ? pieces[1] : "(root)"
            files[area] += 1
            lines[area] += $1
            bytes[area] += $2
        }
        END {
            for (area in files) {
                printf "%d\t%d\t%d\t%s\n", files[area], lines[area], bytes[area], area
            }
        }
    ' "$metrics" | sort -t $'\t' -k2,2nr -k1,1nr -k4,4
} >"$output/areas.tsv"

{
    printf 'files\tlines\textension\n'
    awk -F '\t' '
        {
            files[$4] += 1
            lines[$4] += $1
        }
        END {
            for (extension in files) {
                printf "%d\t%d\t%s\n", files[extension], lines[extension], extension
            }
        }
    ' "$metrics" | sort -t $'\t' -k2,2nr -k1,1nr -k3,3
} >"$output/extensions.tsv"

imports="$scratch/haskell-imports.tsv"
: >"$imports"
while IFS= read -r -d '' path; do
    [ -f "$repo_root/$path" ] || continue
    count="$(grep -Ec '^import([[:space:]]|$)' "$repo_root/$path" || true)"
    lines="$(wc -l <"$repo_root/$path" | tr -d ' ')"
    printf '%s\t%s\t%s\n' "$count" "$lines" "$path" >>"$imports"
done < <(git -C "$repo_root" ls-files -z '*.hs')
{
    printf 'imports\tlines\tpath\n'
    sort -t $'\t' -k1,1nr -k2,2nr -k3,3 "$imports" | sed -n '1,250p'
} >"$output/haskell-import-counts.tsv"

churn="$scratch/churn.tsv"
git -C "$repo_root" log --since="$since" --numstat --format= -- . \
    | awk -F '\t' '
        $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {
            additions[$3] += $1
            deletions[$3] += $2
            total[$3] += $1 + $2
        }
        END {
            for (path in total) {
                printf "%d\t%d\t%d\t%s\n", total[path], additions[path], deletions[path], path
            }
        }
    ' >"$churn"
{
    printf 'changed_lines\tadditions\tdeletions\tpath\n'
    sort -t $'\t' -k1,1nr -k2,2nr -k4,4 "$churn" | sed -n '1,250p'
} >"$output/recent-churn.tsv"

frequency="$scratch/frequency.tsv"
git -C "$repo_root" log --since="$since" --name-only --format= -- . \
    | awk 'NF { changes[$0] += 1 } END { for (path in changes) printf "%d\t%s\n", changes[path], path }' \
    >"$frequency"
{
    printf 'commits_touching\tpath\n'
    sort -t $'\t' -k1,1nr -k2,2 "$frequency" | sed -n '1,250p'
} >"$output/recent-change-frequency.tsv"

(
    cd "$repo_root"
    git grep -n -E '(^|[^[:alnum:]_])(TODO|FIXME|HACK|XXX)([^[:alnum:]_]|$)' -- \
        '*.hs' '*.sql' '*.ts' '*.js' '*.css' '*.sh' '*.nix' '*.md' 2>/dev/null || true
) | sed -n '1,500p' >"$output/todo-markers.txt"

(
    cd "$repo_root"
    git grep -n -E 'shouldContain|isInfixOf|isPrefixOf|readFile|grep|rg[[:space:]]' -- \
        'Test/**' 'e2e/**' 'Config/nix/scripts/**' 2>/dev/null || true
) | sed -n '1,500p' >"$output/text-coupled-test-candidates.txt"

cat >"$output/README.md" <<'EOF'
# Maintenance audit inventory

This directory is ignored, temporary evidence. Rankings are discovery signals,
not findings. Generated files, exact compatibility tests, and high-churn files
may be correct as-is.

Suggested next steps:

1. Read root/local agent and subsystem documentation.
2. Run project architecture hotspot, convention, generated-contract, and focused
   neighborhood queries.
3. Inspect callers/tests/history for candidates before recording findings.
4. Build the source-of-truth map and record rejected candidates as well as
   accepted ones.
5. Keep live work and dependencies in GitHub, not this directory.

Files:

- `metadata.txt`, `git-status.txt`, `git-worktrees.txt`: baseline identity.
- `largest-*.tsv`: bounded line/byte rankings by ownership class.
- `areas.tsv`, `extensions.tsv`: tracked source census.
- `haskell-import-counts.tsv`: coupling/navigation signal only.
- `recent-churn.tsv`, `recent-change-frequency.tsv`: history signals for the
  configured period.
- `todo-markers.txt`: bounded explicit debt markers.
- `text-coupled-test-candidates.txt`: noisy candidates requiring classification;
  exact string checks are often legitimate contracts.
EOF

printf '%s\n' "$output"
