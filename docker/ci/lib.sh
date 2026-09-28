# shellcheck shell=bash
# Shared by the docker/ci scripts. Sourced, not run.

log() { printf '\n\033[36m==>\033[0m %s\n' "$*" >&2; }
die() { printf '%s: %s\n' "$(basename "$0")" "$*" >&2; exit 1; }

# fa_ci_image <flavour> <php>: the published image for a FrontAccounting
# flavour (cp or upstream) and PHP version.
fa_ci_image() { printf 'ghcr.io/cambell-prince/frontaccounting-ci:%s-php%s\n' "$1" "$2"; }

# module_name <checkout>: the FrontAccounting module name, from the
# `class hooks_<name>` its hooks.php declares. FA requires the directory under
# modules/ to be that name, whatever the repository is called.
module_name() {
    local name
    name="$(sed -n 's/^[[:space:]]*class[[:space:]]\{1,\}hooks_\([A-Za-z0-9_]\{1,\}\).*/\1/p' \
        "$1/hooks.php" 2>/dev/null | head -n 1)"
    [ -n "$name" ] && printf '%s\n' "$name"
}

# ci_diagnostics <container>: what FrontAccounting and Apache logged, for a
# failed run. Sets CI_DIAGNOSED=yes so a caller's own cleanup (e.g.
# plugin-test.sh's trap) can skip printing it again.
ci_diagnostics() {
    printf '\n--- FrontAccounting tmp/errors.log\n' >&2
    docker exec "$1" sh -c 'tail -n 60 /var/www/html/tmp/errors.log 2>/dev/null' >&2 || true
    printf '\n--- Apache error.log\n' >&2
    docker exec "$1" sh -c 'tail -n 60 /var/log/apache2/error.log 2>/dev/null' >&2 || true
    # shellcheck disable=SC2034 # read by callers' own cleanup, e.g. plugin-test.sh
    CI_DIAGNOSED=yes
}

# ci_boot <container> <image> [docker run args...]: start the image and wait
# until MariaDB answers and FrontAccounting serves its login page.
ci_boot() {
    local container="$1" image="$2"
    shift 2
    log "booting $image"
    docker run -d --name "$container" "$@" "$image" >/dev/null
    if ! docker exec "$container" fa-ci-wait-ready 120; then
        ci_diagnostics "$container"
        die "$image did not become ready"
    fi
}

# ci_as_user <container> <dir> <command>: sh -c <command> in <dir> as the caller,
# with group www-data added, umask 002 and HOME=/tmp; composer's cache too when
# CI_COMPOSER_CACHE=yes (the caller mounted it at /tmp/composer-cache).
ci_as_user() {
    local env=(-e HOME=/tmp)
    [ "${CI_COMPOSER_CACHE:-}" != yes ] || env+=(-e COMPOSER_CACHE_DIR=/tmp/composer-cache)
    docker exec -w "$2" "${env[@]}" "$1" \
        setpriv --reuid="$(id -u)" --regid="$(id -g)" --groups=33 \
        sh -c "umask 002; $3"
}

# ci_activate <container> <module[:id]>...: register each module (under that
# extension id when given) and activate it through FrontAccounting, in order,
# then give the test user every area.
ci_activate() {
    local c="$1" m name id
    shift
    for m in "$@"; do
        name="${m%%:*}"
        id=''
        [ "$name" = "$m" ] || id="${m#*:}"
        log "activating $name${id:+ as extension $id}"
        if [ -n "$id" ]; then
            docker exec -u www-data "$c" fa-ci-register --id "$id" "$name" "modules/$name"
        else
            docker exec -u www-data "$c" fa-ci-register "$name" "modules/$name"
        fi
        docker exec "$c" fa-ci-activate "$name"
    done
    docker exec "$c" fa-ci-grant
}
