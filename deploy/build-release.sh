#!/bin/sh
# Build a clean release tree to deploy, for `make.phar release`.
#
#   deploy/build-release.sh <ref> <dir> "<components>" <php>
#
# <ref>         FrontAccounting commit to release (git archive, so tracked files only)
# <dir>         where to build it; replaced
# <components>  space-separated path|repo|ref[|composer], each cloned into
#               <dir>/path at ref. The themes and extensions a site runs are
#               separate repositories, so they come in here rather than from
#               whatever happens to be in this checkout. If it has a composer.json,
#               composer then runs as <composer> says:
#                 nodev   install from composer.lock without dev packages (default)
#                 dev     install from composer.lock with dev packages, for a
#                         component that serves files from one (a theme's fonts)
#                 legacy  resolve afresh, with dev packages, and install versions
#                         that have security advisories against them. For an old
#                         component whose lock composer 2 cannot install from and
#                         whose dependencies it now refuses; the manifest says so.
#               A ref of 40 hex digits is a commit (deploy/resolve-refs.sh
#               pins them) and is fetched as exactly that commit.
# <php>         PHP version composer resolves for (config.platform.php): the
#               server's, not this machine's
#
# On success writes <dir>.ok, which deploy/upload.sh requires, and
# <dir>.manifest, recording what went into the release by full commit. A copy
# of the manifest goes into the release as .deploy-manifest, so the server
# keeps a record of what it runs. make.phar carries on
# past a failed command, so the marker is what stops a half-built tree from
# being uploaded.
set -eu

ref="$1"
dir="$2"
components="$3"
php="$4"

[ -n "$dir" ] && [ "$dir" != "/" ] || { echo "build-release: no release directory" >&2; exit 1; }

rm -f "$dir.ok" "$dir.manifest"
rm -rf "$dir"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"    # absolute, for docker's bind mount

fa_module="$(dirname "$0")/../docker/ci/fa-module"

is_sha() { [ "${#1}" -eq 40 ] && case "$1" in *[!0-9a-f]*) false ;; *) true ;; esac; }

sha="$(git rev-parse --verify "$ref^{commit}")"
git archive "$sha" | tar -x -C "$dir"
{
    echo "built $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(hostname)"
    echo "frontaccounting $ref $(git log -1 --format='%H %s' "$sha")"
} > "$dir.manifest"

for component in $components; do
    old_ifs="$IFS"; IFS='|'
    # shellcheck disable=SC2086
    set -- $component
    IFS="$old_ifs"
    path="${1:-}"; repo="${2:-}"; cref="${3:-}"; mode="${4:-nodev}"
    [ -n "$path" ] && [ -n "$repo" ] && [ -n "$cref" ] && [ $# -le 4 ] \
        || { echo "build-release: '$component' is not path|repo|ref[|composer]" >&2; exit 1; }
    case "$mode" in
        nodev) composer="composer install --no-dev" ;;
        dev) composer="composer install" ;;
        legacy) composer="composer update --no-security-blocking" ;;
        *) echo "build-release: '$mode' in '$component' is not nodev, dev or legacy" >&2; exit 1 ;;
    esac

    # git ignores --filter for a plain path; give it a URL.
    case "$repo" in
        *://*|*@*:*|[!/]*:*) ;;
        *) repo="file://$(cd "$repo" && pwd)" ;;
    esac

    echo "==> $path: $repo @ $cref"
    rm -rf "${dir:?}/$path"
    # Full history and tags, without trees or file contents (a partial clone;
    # checkout fetches what it needs), so fa-module can describe the commit.
    if is_sha "$cref"; then
        git init --quiet "$dir/$path"
        git -C "$dir/$path" fetch --quiet --filter=tree:0 --tags "$repo" "$cref"
        git -C "$dir/$path" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
    else
        git clone --quiet --filter=tree:0 --branch "$cref" "$repo" "$dir/$path"
    fi
    # Worked out before config writes _init/config, and checked: a failure
    # inside $(...) in an argument would not stop the build.
    versions="$(sh "$fa_module" version "$dir/$path")" \
        || { echo "build-release: cannot work out the version of $path" >&2; exit 1; }
    version="$(printf '%s\n' "$versions" | sed -n 2p)"
    [ -n "$version" ] || { echo "build-release: no version for $path" >&2; exit 1; }
    sh "$fa_module" config "$dir/$path" || exit 1
    echo "$path $cref $(git -C "$dir/$path" log -1 --format='%H %s')" >> "$dir.manifest"
    echo "    version: $version" >> "$dir.manifest"
    rm -rf "$dir/$path/.git"

    if [ -f "$dir/$path/composer.json" ]; then
        echo "==> $path: $composer"
        # No composer on the host: run it in the official image, as this user so
        # vendor/ is ours, against the server's PHP version.
        mkdir -p "${HOME}/.cache/composer"
        docker run --rm -u "$(id -u):$(id -g)" \
            -v "$dir/$path":/app -w /app \
            -v "${HOME}/.cache/composer":/tmp/composer-cache -e COMPOSER_CACHE_DIR=/tmp/composer-cache \
            composer:2 sh -c "composer config platform.php '$php' && $composer --no-interaction --no-progress --optimize-autoloader"
        if [ "$mode" = legacy ]; then
            packages="$(php -r '$l = json_decode(file_get_contents($argv[1]), true);
                foreach (array_merge($l["packages"], $l["packages-dev"]) as $p) echo $p["name"], " ", $p["version"], "\n";' \
                "$dir/$path/composer.lock" | paste -sd, -)"
            echo "    composer: legacy, SECURITY ADVISORIES IGNORED ($packages)" >> "$dir.manifest"
        else
            echo "    composer: $mode" >> "$dir.manifest"
        fi
    fi
done

cp "$dir.manifest" "$dir/.deploy-manifest"
touch "$dir.ok"
echo "==> release built in $dir"
cat "$dir.manifest"
