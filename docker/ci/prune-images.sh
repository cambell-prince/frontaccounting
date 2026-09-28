#!/usr/bin/env bash
#
# Delete the CI images nothing needs any more from
# ghcr.io/cambell-prince/frontaccounting-ci.
#
#   docker/ci/prune-images.sh [--dry-run] [--keep <n>]    prune
#   docker/ci/prune-images.sh [--dry-run] --pr <number>   drop one PR's images
#
# Prune keeps:
#
#   * every version with a tag it does not recognise: the moving
#     <flavour>-php<ver> tags plugins pull, above all;
#   * per flavour, the newest <n> (default 3) <flavour>-php<ver>-<sha>
#     versions, so a plugin can pin a known-good image;
#   * pr-<number>-* versions whose pull request is still open;
#
# and deletes the rest: older <sha> versions, closed pull requests' images, and
# untagged versions (left behind whenever a tag moves on).
#
# --pr <number> deletes that pull request's images only, open or not; CI runs
# it when the pull request closes.
#
# Needs GH_TOKEN with packages read/delete on the package and pull request read
# on the repository; in CI that is the workflow's GITHUB_TOKEN, since this
# repository publishes the package. PRUNE_VERSIONS_FILE and PRUNE_OPEN_PRS
# stand in for the two API reads (docker/ci/test/prune.sh).

set -euo pipefail

OWNER_PATH="${PRUNE_OWNER_PATH:-users/cambell-prince}"
PACKAGE="${PRUNE_PACKAGE:-frontaccounting-ci}"
REPO="${PRUNE_REPO:-cambell-prince/frontaccounting}"
KEEP=3
PR=''
DRY_RUN=no

die() { printf 'prune-images: %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=yes; shift ;;
        --keep) KEEP="${2:-}"; shift 2 ;;
        --pr) PR="${2:-}"; shift 2 ;;
        *) die "unknown argument: $1" ;;
    esac
done
case "$KEEP" in ''|*[!0-9]*) die "--keep takes a number" ;; esac
case "$PR" in *[!0-9]*) die "--pr takes a pull request number" ;; esac

VERSIONS_API="/$OWNER_PATH/packages/container/$PACKAGE/versions"

# Every version as {id, created_at, tags}. --paginate emits one array per page.
versions() {
    if [ -n "${PRUNE_VERSIONS_FILE:-}" ]; then
        cat "$PRUNE_VERSIONS_FILE"
    else
        gh api --paginate "$VERSIONS_API?per_page=100"
    fi | jq -s '[.[][] | {id, created_at, tags: .metadata.container.tags}]'
}

open_prs() {
    if [ -n "${PRUNE_OPEN_PRS+set}" ]; then
        # shellcheck disable=SC2086
        printf '%s\n' $PRUNE_OPEN_PRS
    else
        gh api --paginate "/repos/$REPO/pulls?state=open&per_page=100" --jq '.[].number'
    fi | jq -Rs '[split("\n")[] | select(length > 0) | tonumber]'
}

JQ_TAGS='
    def sha_tag: test("^(cp|upstream)-php[0-9.]+-[0-9a-f]{7,40}$");
    def pr_tag: test("^pr-[0-9]+-(cp|upstream)-php[0-9.]+$");
    def pr_number: capture("^pr-(?<n>[0-9]+)-").n | tonumber;
    # A tag it does not recognise (the moving ones above all) protects a version.
    def protected: any(.tags[]; (sha_tag or pr_tag) | not);
    def flavour: [.tags[] | select(sha_tag) | sub("-[0-9a-f]+$"; "")][0];
'

if [ -n "$PR" ]; then
    doomed="$(versions | jq --argjson pr "$PR" "$JQ_TAGS"'
        [ .[] | select((.tags | length) > 0
                       and all(.tags[]; pr_tag)
                       and any(.tags[]; pr_number == $pr))
              | {id, tags, why: "its pull request has closed"} ]')"
else
    open="$(open_prs)"
    jq -e 'type == "array"' <<< "$open" >/dev/null || die "open PR lookup returned no JSON array"
    doomed="$(versions | jq --argjson keep "$KEEP" --argjson open "$open" "$JQ_TAGS"'
        (map(select((.tags | length) > 0 and (protected | not) and any(.tags[]; sha_tag)))
         | group_by(flavour)
         | map(sort_by(.created_at) | reverse | .[$keep:])
         | add // []
         | map(.id)) as $old
        | [ .[]
            # untagged versions are safe to prune only because build-image.sh
            # builds single-manifest images (no provenance/SBOM index) -- see
            # its --provenance=false --sbom=false.
            | if (.tags | length) == 0 then
                  {id, tags, why: "untagged"}
              elif protected then
                  empty
              elif (.id | IN($old[])) then
                  {id, tags, why: "older than the newest \($keep) \(flavour)-<sha>"}
              elif all(.tags[]; pr_tag) and all(.tags[]; pr_number | IN($open[]) | not) then
                  {id, tags, why: "its pull request has closed"}
              else
                  empty
              end ]')"
fi

count="$(jq length <<< "$doomed")"
if [ "$count" -eq 0 ]; then
    echo "nothing to delete from ghcr.io/${OWNER_PATH#*/}/$PACKAGE"
    exit 0
fi

jq -r '.[] | "\(.id)\t\(if (.tags | length) == 0 then "(untagged)" else (.tags | join(",")) end)\t\(.why)"' \
    <<< "$doomed" |
while IFS=$'\t' read -r id tags why; do
    if [ "$DRY_RUN" = yes ]; then
        printf 'would delete %s %s: %s\n' "$id" "$tags" "$why"
    else
        gh api --silent -X DELETE "$VERSIONS_API/$id"
        printf 'deleted %s %s: %s\n' "$id" "$tags" "$why"
    fi
done

if [ "$DRY_RUN" = yes ]; then
    echo "$count version(s) would be deleted (dry run)"
else
    echo "$count version(s) deleted"
fi
