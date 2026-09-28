#!/usr/bin/env bash
#
# Run one FrontAccounting plugin's tests in the CI image.
#
#   docker/ci/plugin-test.sh [options] <plugin-checkout> [--] <test command>
#
# The checkout is mounted at /var/www/html/modules/<name>, where <name> comes
# from `class hooks_<name>` in its hooks.php. Then:
#   1. each cloned --with module gets `composer install --no-dev`
#   2. --setup runs in the plugin directory
#   3. the --with modules (in the order given), then the plugin, are
#      registered and activated through FrontAccounting's own
#      Install/Activate Extensions form, and the admin role is granted their
#      areas. An activation failure fails the run.
#   4. the test command runs in the plugin directory
# Commands run with sh -c as your uid:gid, with group www-data added,
# umask 002 and HOME=/tmp. The exit status is the test command's.
#
# Options:
#   --image IMG            the CI image (default: $FA_CI_IMAGE, else the one
#                          --fa and --php name)
#   --fa cp|upstream       FrontAccounting flavour (default: cp)
#   --php 7.4|8.3          PHP version (default: 7.4)
#   --with NAME=REPO@REF   another module the plugin needs, cloned at REF
#                          (the part after the last @); repeatable
#   --with NAME=PATH       ... or a local checkout of it, used as it is
#   --setup CMD            run before activation, e.g. composer install
#   --no-activate          mount only: no registration, activation or grant
#   --name NAME            the module name, for a checkout without hooks.php
#   --mount HOST:CONTAINER another bind mount; repeatable
#   --keep                 leave the container running, with Apache on a
#                          printed localhost port (sign in as test/test)
#
# COMPOSER_CACHE_DIR, when set, is mounted as composer's cache.
# .github/workflows/plugin-test.yml runs exactly this, so a failing CI job
# can be reproduced locally with the same arguments.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

IMAGE="${FA_CI_IMAGE:-}"
# shellcheck disable=SC2209 # a flavour name, not the cp command
FLAVOUR=cp
PHP=7.4
SETUP=''
ACTIVATE=yes
NAME=''
KEEP=no
WITH=()
MOUNTS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --image) IMAGE="$2"; shift 2 ;;
        --fa) FLAVOUR="$2"; shift 2 ;;
        --php) PHP="$2"; shift 2 ;;
        --with) WITH+=("$2"); shift 2 ;;
        --setup) SETUP="$2"; shift 2 ;;
        --no-activate) ACTIVATE=no; shift ;;
        --name) NAME="$2"; shift 2 ;;
        --mount) MOUNTS+=("$2"); shift 2 ;;
        --keep) KEEP=yes; shift ;;
        --) shift; break ;;
        -*) die "unknown option: $1" ;;
        *) break ;;
    esac
done

[ "$#" -ge 2 ] || die "usage: plugin-test.sh [options] <plugin-checkout> [--] <test command>"
[ -d "$1" ] || die "$1 is not a directory"
CHECKOUT="$(cd "$1" && pwd)"
shift
[ "${1:-}" = -- ] && shift
TEST="$*"
[ -n "$TEST" ] || die "no test command"

[ -n "$IMAGE" ] || IMAGE="$(fa_ci_image "$FLAVOUR" "$PHP")"
[ -n "$NAME" ] || NAME="$(module_name "$CHECKOUT")" \
    || die "$CHECKOUT has no hooks.php declaring class hooks_<name>; pass --name"

FA=/var/www/html
CONTAINER="fa-ci-$NAME-$$"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

run_args=(-v "$CHECKOUT:$FA/modules/$NAME")
deps=()
cloned=()
for spec in "${WITH[@]+"${WITH[@]}"}"; do
    dep="${spec%%=*}"
    src="${spec#*=}"
    [ -n "$dep" ] && [ "$dep" != "$spec" ] && [ -n "$src" ] \
        || die "--with takes NAME=REPO@REF or NAME=PATH, not '$spec'"
    [ "$dep" != "$NAME" ] || die "--with $dep: $dep is the plugin under test"
    if [ -d "$src" ]; then
        path="$(cd "$src" && pwd)"
    else
        repo="${src%@*}"
        ref="${src##*@}"
        [ "$repo" != "$src" ] && [ -n "$ref" ] || die "--with $spec: not a directory, and no @REF"
        log "cloning $dep: $repo @ $ref"
        git clone --quiet --depth 1 --branch "$ref" "$repo" "$WORK/$dep"
        path="$WORK/$dep"
        cloned+=("$dep")
    fi
    run_args+=(-v "$path:$FA/modules/$dep")
    deps+=("$dep")
done
for m in "${MOUNTS[@]+"${MOUNTS[@]}"}"; do run_args+=(-v "$m"); done

exec_env=(-e HOME=/tmp)
if [ -n "${COMPOSER_CACHE_DIR:-}" ]; then
    mkdir -p "$COMPOSER_CACHE_DIR"
    run_args+=(-v "$COMPOSER_CACHE_DIR:/tmp/composer-cache")
    exec_env+=(-e COMPOSER_CACHE_DIR=/tmp/composer-cache)
fi
[ "$KEEP" = no ] || run_args+=(-p 127.0.0.1::80)

cleanup() {
    local rc=$?
    [ "$rc" -eq 0 ] || [ "${CI_DIAGNOSED:-}" = yes ] || ci_diagnostics "$CONTAINER"
    if [ "$KEEP" = yes ] && docker inspect "$CONTAINER" >/dev/null 2>&1; then
        log "leaving $CONTAINER running: http://$(docker port "$CONTAINER" 80 | head -n 1)/ (test/test);" \
            "docker exec -it $CONTAINER bash; docker rm -f $CONTAINER when done"
    else
        docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK"
    exit "$rc"
}
trap cleanup EXIT

ci_boot "$CONTAINER" "$IMAGE" "${run_args[@]}"

# as_user <dir> <command>: sh -c <command> in <dir> as the caller, group www-data added.
as_user() {
    docker exec -w "$1" "${exec_env[@]}" "$CONTAINER" \
        setpriv --reuid="$(id -u)" --regid="$(id -g)" --groups=33 \
        sh -c "umask 002; $2"
}

for dep in "${cloned[@]+"${cloned[@]}"}"; do
    log "composer install --no-dev: $dep"
    as_user "$FA/modules/$dep" '[ ! -f composer.json ] || composer install --no-dev --no-interaction --no-progress'
done

if [ -n "$SETUP" ]; then
    log "setup: $SETUP"
    as_user "$FA/modules/$NAME" "$SETUP"
fi

if [ "$ACTIVATE" = yes ]; then
    for module in "${deps[@]+"${deps[@]}"}" "$NAME"; do
        log "activating $module"
        docker exec -u www-data "$CONTAINER" fa-ci-register "$module" "modules/$module"
        docker exec "$CONTAINER" fa-ci-activate "$module"
    done
    docker exec "$CONTAINER" fa-ci-grant
fi

log "test: $TEST"
as_user "$FA/modules/$NAME" "$TEST"
