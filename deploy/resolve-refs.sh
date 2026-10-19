#!/usr/bin/env bash
#
# Pin every part of a release to its newest commit that passed CI, for the bms
# deploy workflow (.github/workflows/deploy-bms.yml).
#
#   deploy/resolve-refs.sh <fa_branch> "<components>" ["<overrides>"]
#
# Run in a FrontAccounting checkout of <fa_branch> with full history. Prints,
# for $GITHUB_OUTPUT, with notes on stderr:
#
#   ref=<sha>                                  FrontAccounting
#   components=<path|repo|sha[|composer]> ...  <components>, each ref pinned
#
# FrontAccounting: G is the head of the newest successful push run of
# ci-image.yml on <fa_branch>, H is HEAD. H when nothing between them touches
# the image's paths (so a docs-only push still ships), else G: H is then still
# being tested, and its run triggers its own deploy, or it failed.
# A component: the head of the newest successful push run of its ci.yml on the
# branch its ref names.
# A ref that is already a 40-hex commit is used as it is.
# <overrides>: space-separated <path>=<sha>, and frontaccounting=<sha>, used
# as given.
#
# Needs gh signed in (GH_TOKEN in CI). RESOLVE_FA_REPO names FrontAccounting's
# repository (default cambell-prince/frontaccounting).

set -euo pipefail
die() { printf 'resolve-refs: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

[ "$#" -ge 2 ] || die 'usage: resolve-refs.sh <fa_branch> "<components>" ["<overrides>"]'
fa_branch="$1"
components="$2"
overrides="${3:-}"
fa_repo="${RESOLVE_FA_REPO:-cambell-prince/frontaccounting}"
image_workflow=.github/workflows/ci-image.yml

declare -A pin=() used=()
for o in $overrides; do
    k="${o%%=*}"
    v="${o#*=}"
    [[ "$o" == *=* && -n "$k" && "$v" =~ ^[0-9a-f]{40}$ ]] || die "override '$o' is not <path>=<40-hex commit>"
    pin[$k]="$v"
done

# newest_green <owner/repo> <workflow file> <branch>: the head commit of the
# newest successful push run, or nothing
newest_green() {
    gh api "repos/$1/actions/workflows/$2/runs?branch=$3&event=push&status=success&per_page=1" \
        --jq '.workflow_runs[0].head_sha // empty'
}

# repo_slug <url>: owner/name of a GitHub https or ssh URL
repo_slug() {
    local s="$1"
    s="${s#https://github.com/}"
    s="${s#git@github.com:}"
    s="${s%.git}"
    [[ "$s" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && printf '%s\n' "$s"
}

# The globs under "paths: &image-paths" in ci-image.yml
image_paths() {
    [ -f "$image_workflow" ] || die "no $image_workflow in $(pwd)"
    awk '/paths: &image-paths/ { on = 1; next }
         on && /^[[:space:]]*- / { sub(/^[[:space:]]*- /, ""); print; next }
         on { exit }' "$image_workflow" | tr -d "'\""
}

# touches_image <from> <to>: does any change between them fall under the
# image's paths? In a bash pattern * also matches /, so this can say yes where
# GitHub would say no; that only ever picks the older, green commit.
touches_image() {
    local f p pats
    mapfile -t pats < <(image_paths)
    [ "${#pats[@]}" -gt 0 ] || die "no paths under 'paths: &image-paths' in $image_workflow"
    while IFS= read -r f; do
        for p in "${pats[@]}"; do
            # shellcheck disable=SC2053 # $p is a glob on purpose
            [[ "$f" == $p ]] && return 0
        done
    done < <(git diff --name-only --no-renames "$1" "$2")
    return 1
}

if [ -n "${pin[frontaccounting]:-}" ]; then
    fa="${pin[frontaccounting]}"
    used[frontaccounting]=1
    note "frontaccounting: $fa (override)"
else
    head="$(git rev-parse HEAD)"
    green="$(newest_green "$fa_repo" ci-image.yml "$fa_branch")" \
        || die "frontaccounting: could not read CI runs of $fa_repo"
    [ -n "$green" ] || die "frontaccounting: no successful ci-image.yml push run on $fa_branch"
    git merge-base --is-ancestor "$green" "$head" 2>/dev/null \
        || die "frontaccounting: $green, the last green commit, is not in $fa_branch's history at $head (shallow checkout, or a rewritten branch?)"
    if [ "$green" = "$head" ]; then
        fa="$head"
        note "frontaccounting: $fa (green)"
    elif touches_image "$green" "$head"; then
        fa="$green"
        note "frontaccounting: $fa, the last green commit; ${head:0:7} changes the image and has not passed CI image"
    else
        fa="$head"
        note "frontaccounting: $fa (nothing the image builds from changed since green ${green:0:7})"
    fi
fi

out=()
for c in $components; do
    IFS='|' read -r path repo ref mode extra <<< "$c"
    [ -n "$path" ] && [ -n "$repo" ] && [ -n "$ref" ] && [ -z "${extra:-}" ] \
        || die "'$c' is not path|repo|ref[|composer]"
    if [ -n "${pin[$path]:-}" ]; then
        sha="${pin[$path]}"
        used[$path]=1
        note "$path: $sha (override)"
    elif [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
        sha="$ref"
        note "$path: $sha (pinned in components)"
    else
        slug="$(repo_slug "$repo")" || die "$path: '$repo' is not a GitHub repository URL"
        sha="$(newest_green "$slug" ci.yml "$ref")" || die "$path: could not read CI runs of $slug"
        [ -n "$sha" ] || die "$path: no successful ci.yml push run on $slug $ref"
        note "$path: $sha (green on $ref)"
    fi
    out+=("$path|$repo|$sha${mode:+|$mode}")
done

for k in "${!pin[@]}"; do
    [ -n "${used[$k]:-}" ] || die "override '$k' matches no component"
done

printf 'ref=%s\n' "$fa"
printf 'components=%s\n' "${out[*]}"
