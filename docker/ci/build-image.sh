#!/usr/bin/env bash
#
# Build the FrontAccounting CI image for one flavour and PHP version.
#
#   docker/ci/build-image.sh [--cache-gha] <cp|upstream> <php> <tag> [<tag>...]
#
#   cp          FrontAccounting from this checkout's HEAD (git archive, so
#               committed files only; docker/ci itself is read from the
#               working tree)
#   upstream    FrontAccounting from $FA_UPSTREAM_REPO at $FA_UPSTREAM_REF
#               (default FrontAccountingERP/FA master)
#   --cache-gha use GitHub Actions' cache for the layers (CI only)
#
# The database is always seeded from this checkout's
# modules/tests/data/fa_test.sql.gz.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"
root="$(cd "$here/../.." && pwd)"

gha=no
if [ "${1:-}" = --cache-gha ]; then gha=yes; shift; fi
[ "$#" -ge 3 ] || die "usage: build-image.sh [--cache-gha] <cp|upstream> <php> <tag>..."
flavour="$1"
php="$2"
shift 2

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/fa" "$stage/fixture"

case "$flavour" in
    cp)
        git -C "$root" archive HEAD | tar -x -C "$stage/fa"
        fa_ref="$(git -C "$root" rev-parse --abbrev-ref HEAD)"
        fa_sha="$(git -C "$root" rev-parse HEAD)"
        ;;
    upstream)
        repo="${FA_UPSTREAM_REPO:-https://github.com/FrontAccountingERP/FA.git}"
        fa_ref="${FA_UPSTREAM_REF:-master}"
        git clone --quiet --depth 1 --branch "$fa_ref" "$repo" "$stage/fa"
        fa_sha="$(git -C "$stage/fa" rev-parse HEAD)"
        rm -rf "$stage/fa/.git"
        ;;
    *) die "flavour must be cp or upstream, not '$flavour'" ;;
esac
cp "$root/modules/tests/data/fa_test.sql.gz" "$stage/fixture/"

tags=()
for tag in "$@"; do tags+=(-t "$tag"); done
cache=()
if [ "$gha" = yes ]; then
    cache=(--cache-from "type=gha,scope=fa-ci-$flavour-$php"
           --cache-to "type=gha,mode=max,scope=fa-ci-$flavour-$php")
fi

log "building FrontAccounting $flavour ($fa_ref ${fa_sha:0:7}) on PHP $php: $*"
docker buildx build --load "${cache[@]}" \
    --build-arg PHP_VERSION="$php" \
    --build-context fa="$stage/fa" \
    --build-context fixture="$stage/fixture" \
    --label org.opencontainers.image.source=https://github.com/cambell-prince/frontaccounting \
    --label org.opencontainers.image.revision="$(git -C "$root" rev-parse HEAD)" \
    --label org.opencontainers.image.description="FrontAccounting ($flavour, PHP $php) for plugin CI" \
    --label io.frontaccounting.ref="$fa_ref" \
    --label io.frontaccounting.commit="$fa_sha" \
    -f "$here/Dockerfile" "${tags[@]}" "$here"
