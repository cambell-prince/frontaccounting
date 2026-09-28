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
# failed run.
ci_diagnostics() {
    printf '\n--- FrontAccounting tmp/errors.log\n' >&2
    docker exec "$1" sh -c 'tail -n 60 /var/www/html/tmp/errors.log 2>/dev/null' >&2 || true
    printf '\n--- Apache error.log\n' >&2
    docker exec "$1" sh -c 'tail -n 60 /var/log/apache2/error.log 2>/dev/null' >&2 || true
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
