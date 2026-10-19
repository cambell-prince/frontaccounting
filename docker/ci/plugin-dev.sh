#!/usr/bin/env bash
#
# Persistent FrontAccounting development environments, from the CI image.
#
#   docker/ci/plugin-dev.sh [--env NAME] [--config FILE] <command>
#
# Commands:
#   up                    create the environment, or start it again and link
#   link                  apply FA_DEV_MODULES: activate what it lists,
#                         deactivate what it no longer lists
#   activate              activate every listed module again, from scratch
#   down                  stop it; its data stays
#   destroy --yes         remove the container and its database volume
#   status | url
#   shell                 bash in the FrontAccounting tree, as you
#   exec [--dir D] <cmd>  a command in the FrontAccounting tree (or D under it)
#   logs [app|errors]
#   mail [list|show <file>|clear]
#   db dump [file] | db load <file> | db shell
#
# The modules/ folder of a FrontAccounting checkout (FA_DEV_MODULES_ROOT,
# default: the modules/ of the checkout this script is in) is mounted at
# /var/www/html/modules, so an edit on this machine is live on the next
# request. Which of its folders are extensions is opt-in: FA_DEV_MODULES,
# activated in that order.
#
# Settings come from the environment's config file, docker/ci/dev/<env>.env
# (see example.env there; --config to name another), and FA_DEV_* variables
# already set in your shell win over it:
#
#   FA_DEV_MODULES        folders of modules/ to activate, in order
#   FA_DEV_MODULES_ROOT   the folder mounted as modules/
#   FA_DEV_THEMES         folders of FA_DEV_THEMES_ROOT to mount under themes/
#   FA_DEV_THEMES_ROOT    default: the themes/ of this checkout
#   FA_DEV_PORT           Apache's port on this machine (default 8100)
#   FA_DEV_BIND           the address it listens on (default 127.0.0.1; 0.0.0.0
#                         so containers reach it as host.docker.internal)
#   FA_DEV_DATASET        test, demo, or a .sql/.sql.gz backup (default test)
#   FA_DEV_EXTENSIONS     an installed_extensions.php (a live site's) whose
#                         extension ids the modules keep
#   FA_DEV_INIT           yes (default): run each activated module's own
#                         tools/init.sh after activation; no to skip
#   FA_DEV_MOUNTS         more HOST:CONTAINER mounts, space separated, e.g. a
#                         plugin checked out elsewhere over modules/NAME
#   FA_DEV_IMAGE          the image (default: FA_DEV_FA cp, FA_DEV_PHP 7.4)
#
# The environment is the container fa-dev-<env> (default env: dev), with its
# database on the volume fa-dev-<env>-db. The mounts, themes, port, address,
# image and dataset take effect when it is created; the module list on up and
# link.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"
checkout="$(cd "$here/../.." && pwd)"
FA=/var/www/html

ENV_NAME=dev
CONFIG=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --env) ENV_NAME="$2"; shift 2 ;;
        --config) CONFIG="$2"; shift 2 ;;
        *) break ;;
    esac
done
case "$ENV_NAME" in ''|*[!A-Za-z0-9_.-]*) die "--env takes letters, digits, '.', '_' and '-'" ;; esac
[ -n "$CONFIG" ] || CONFIG="$here/dev/$ENV_NAME.env"
[ "$#" -ge 1 ] || die "usage: plugin-dev.sh [--env NAME] [--config FILE] up|link|activate|down|destroy|status|url|shell|exec|logs|mail|db ..."
CMD="$1"
shift
CONTAINER="fa-dev-$ENV_NAME"
VOLUME="fa-dev-$ENV_NAME-db"

# The config file, then the FA_DEV_* already in the environment on top.
load_config() {
    local saved line
    saved="$(env | grep '^FA_DEV_' || true)"
    if [ -f "$CONFIG" ]; then
        set -a
        # shellcheck disable=SC1090 # the environment's own config
        . "$CONFIG"
        set +a
    fi
    while IFS= read -r line; do [ -z "$line" ] || export "${line?}"; done <<< "$saved"
    FA_DEV_MODULES="${FA_DEV_MODULES:-}"
    FA_DEV_MODULES_ROOT="${FA_DEV_MODULES_ROOT:-$checkout/modules}"
    FA_DEV_THEMES="${FA_DEV_THEMES:-}"
    FA_DEV_THEMES_ROOT="${FA_DEV_THEMES_ROOT:-$checkout/themes}"
    FA_DEV_PORT="${FA_DEV_PORT:-8100}"
    FA_DEV_BIND="${FA_DEV_BIND:-127.0.0.1}"
    FA_DEV_DATASET="${FA_DEV_DATASET:-test}"
    FA_DEV_EXTENSIONS="${FA_DEV_EXTENSIONS:-}"
    FA_DEV_INIT="${FA_DEV_INIT:-yes}"
    FA_DEV_MOUNTS="${FA_DEV_MOUNTS:-}"
    FA_DEV_IMAGE="${FA_DEV_IMAGE:-$(fa_ci_image "${FA_DEV_FA:-cp}" "${FA_DEV_PHP:-7.4}")}"
}

exists() { docker inspect "$CONTAINER" >/dev/null 2>&1; }
running() { [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = true ]; }
require_env() { exists || die "no environment '$ENV_NAME' ($CONTAINER); create it with: plugin-dev.sh --env $ENV_NAME up"; }
label() { docker inspect -f "{{index .Config.Labels \"fa-dev.$1\"}}" "$CONTAINER"; }
url() { echo "http://localhost:$(label port)/"; }
applied() { docker exec "$CONTAINER" cat /var/lib/fa-dev/modules 2>/dev/null || true; }
save_applied() {
    docker exec "$CONTAINER" sh -c 'mkdir -p /var/lib/fa-dev && : > /var/lib/fa-dev/modules && for m in "$@"; do echo "$m" >> /var/lib/fa-dev/modules; done' sh "$@"
}

# Where a listed module comes from on this machine: a FA_DEV_MOUNTS entry over
# modules/<name>, else the modules folder.
module_source() {
    local spec c
    for spec in $FA_DEV_MOUNTS; do
        # HOST:CONTAINER[:OPTIONS]
        c="${spec#*:}"
        [ "${c%%:*}" != "$FA/modules/$1" ] || { echo "${spec%%:*}"; return; }
    done
    echo "$FA_DEV_MODULES_ROOT/$1"
}

# The modules to activate, as name or name:id, in FA_DEV_MODULES' order: ids
# from FA_DEV_EXTENSIONS where it lists the module.
module_specs() {
    local m id listed=''
    if [ -n "$FA_DEV_EXTENSIONS" ]; then
        docker cp "$FA_DEV_EXTENSIONS" "$CONTAINER:/tmp/fa-dev-extensions.php"
        listed="$(docker exec "$CONTAINER" fa-ci-ext-list /tmp/fa-dev-extensions.php)"
    fi
    for m in $FA_DEV_MODULES; do
        id="$(printf '%s\n' "$listed" | awk -v m="$m" '$2 == m {print $1; exit}')"
        if [ -n "$id" ]; then echo "$m:$id"; else echo "$m"; fi
    done
}

# FrontAccounting runs a module's install SQL only as it becomes active, so a
# re-activation (after the database changed) starts from inactive.
mark_inactive() {
    [ "$#" -gt 0 ] || return 0
    docker exec -u www-data "$CONTAINER" php -r '
        $f = "/var/www/html/company/0/installed_extensions.php";
        $installed_extensions = array();
        include $f;
        $names = array_slice($argv, 1);
        foreach ($installed_extensions as $k => $e)
            if (in_array($e["package"], $names, true)) $installed_extensions[$k]["active"] = false;
        file_put_contents($f, "<?php\n\n\$installed_extensions = " . var_export($installed_extensions, true) . ";\n");' "$@"
}

# Each module's own tools/init.sh, in its directory, unless FA_DEV_INIT=no.
run_inits() {
    [ "$FA_DEV_INIT" = yes ] || return 0
    local m
    for m in "$@"; do
        if docker exec "$CONTAINER" test -f "$FA/modules/$m/tools/init.sh"; then
            log "init: $m (tools/init.sh)"
            ci_as_user "$CONTAINER" "$FA/modules/$m" 'sh tools/init.sh'
        fi
    done
}

# Reads FA_DEV_MODULES into SPECS (name or name:id) and NAMES; deactivates
# the modules applied before that it no longer lists, and records the ones
# kept, so a failed activation after this doesn't leave those listed. WAS is
# the list applied before, space separated and padded.
SPECS=()
NAMES=()
WAS=''
unlink_unlisted() {
    local kept=() s m
    SPECS=()
    NAMES=()
    while IFS= read -r s; do [ -z "$s" ] || SPECS+=("$s"); done < <(module_specs)
    for s in "${SPECS[@]+"${SPECS[@]}"}"; do NAMES+=("${s%%:*}"); done
    WAS=" $(applied | tr '\n' ' ') "
    for m in $WAS; do
        case " ${NAMES[*]-} " in
            *" $m "*) kept+=("$m") ;;
            *) log "deactivating $m"; docker exec "$CONTAINER" fa-ci-deactivate "$m" ;;
        esac
    done
    save_applied "${kept[@]+"${kept[@]}"}"
}

# Every listed module, activated from inactive, then their inits; those no
# longer listed deactivated first.
activate_all() {
    unlink_unlisted
    if [ "${#SPECS[@]}" -gt 0 ]; then
        mark_inactive "${NAMES[@]}"
        ci_activate "$CONTAINER" "${SPECS[@]}"
    fi
    save_applied "${NAMES[@]+"${NAMES[@]}"}"
    run_inits "${NAMES[@]+"${NAMES[@]}"}"
}

# The listed modules brought in line with FA_DEV_MODULES: those no longer
# listed deactivated, new ones activated (and their inits run).
cmd_link() {
    local new=() m
    unlink_unlisted
    for m in "${NAMES[@]+"${NAMES[@]}"}"; do
        case "$WAS" in *" $m "*) ;; *) new+=("$m") ;; esac
    done
    [ "${#SPECS[@]}" -eq 0 ] || ci_activate "$CONTAINER" "${SPECS[@]}"
    save_applied "${NAMES[@]+"${NAMES[@]}"}"
    run_inits "${new[@]+"${new[@]}"}"
}

# load_dataset <file on this machine>: replace the database with a backup.
# fa-ci-dataset tells .gz from plain SQL by the name.
load_dataset() {
    local src dest=/tmp/fa-dev-dataset.sql
    src="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
    case "$src" in *.gz) dest=/tmp/fa-dev-dataset.sql.gz ;; esac
    log "dataset: $src"
    docker cp "$src" "$CONTAINER:$dest"
    docker exec "$CONTAINER" fa-ci-dataset "$dest"
    docker exec "$CONTAINER" rm -f "$dest"
}

# What creation needs from this machine, checked before anything starts:
# the dataset file (when it will be loaded: $1 = yes), the extension list
# file, and each listed module's hooks.php.
check_inputs() {
    local m
    case "$1:$FA_DEV_DATASET" in
        yes:test|yes:demo) ;;
        yes:*) [ -f "$FA_DEV_DATASET" ] || { printf 'plugin-dev.sh: no such dataset file: %s\n' "$FA_DEV_DATASET" >&2; exit 2; } ;;
    esac
    [ -z "$FA_DEV_EXTENSIONS" ] || [ -f "$FA_DEV_EXTENSIONS" ] \
        || { printf 'plugin-dev.sh: no such file: %s\n' "$FA_DEV_EXTENSIONS" >&2; exit 2; }
    [ -d "$FA_DEV_MODULES_ROOT" ] || die "FA_DEV_MODULES_ROOT is not a directory: $FA_DEV_MODULES_ROOT"
    for m in $FA_DEV_MODULES; do
        [ -f "$(module_source "$m")/hooks.php" ] || die "FA_DEV_MODULES lists $m, but $(module_source "$m") has no hooks.php"
    done
}

# A failure from here on keeps the environment for inspection.
keep_on_failure() {
    # shellcheck disable=SC2154 # rc is assigned inside the trap
    trap 'rc=$?; if [ "$rc" -ne 0 ]; then [ "${CI_DIAGNOSED:-}" = yes ] || ci_diagnostics "$CONTAINER"; log "$CONTAINER kept for inspection: plugin-dev.sh --env $ENV_NAME logs | shell | activate | destroy --yes; up again finishes creating it"; fi' EXIT
}

# The creation steps after the container is up: the dataset (only into a
# database volume that was new: fresh=yes), a live site's extension ids, the
# modules; then /var/lib/fa-dev/created, so a later up knows it finished.
finish_creation() {
    if [ "$1" = yes ]; then
        case "$FA_DEV_DATASET" in
            test) ;;
            demo) log "dataset: demo"; docker exec "$CONTAINER" fa-ci-dataset demo ;;
            *) load_dataset "$FA_DEV_DATASET" ;;
        esac
    fi
    if [ -n "$FA_DEV_EXTENSIONS" ]; then
        # Modules the site's list doesn't have get ids after every id it has
        # used, and after any a creation that didn't finish already gave out.
        docker cp "$FA_DEV_EXTENSIONS" "$CONTAINER:/tmp/fa-dev-extensions.php"
        docker exec -u www-data "$CONTAINER" php -r '
            function fa_dev_next($file) {
                $next_extension_id = 1; $installed_extensions = array();
                include $file;
                return max((int) $next_extension_id, count($installed_extensions) ? max(array_keys($installed_extensions)) + 1 : 1);
            }
            $f = "/var/www/html/installed_extensions.php";
            $n = max(fa_dev_next("/tmp/fa-dev-extensions.php"), fa_dev_next($f));
            file_put_contents($f, preg_replace("/next_extension_id = \\d+/", "next_extension_id = $n", file_get_contents($f)));'
    fi
    activate_all
    docker exec "$CONTAINER" sh -c 'mkdir -p /var/lib/fa-dev && date > /var/lib/fa-dev/created'
}

report() {
    log "$ENV_NAME is up: $(url)"
    printf '  sign in as test/test, or as the dataset'"'"'s own users (admin/password on demo)\n' >&2
    printf '  modules: %s\n' "$(applied | tr '\n' ' ')" >&2
    url
}

cmd_up() {
    load_config
    if exists; then
        running || { log "starting $CONTAINER"; docker start "$CONTAINER" >/dev/null; }
        if ! docker exec "$CONTAINER" fa-ci-wait-ready 120; then
            ci_diagnostics "$CONTAINER"
            die "$CONTAINER did not become ready"
        fi
        if ! docker exec "$CONTAINER" test -f /var/lib/fa-dev/created; then
            log "creating $CONTAINER did not finish; finishing it: dataset, extension ids, modules (its mounts, themes, port and image stay as created)"
            local fresh
            fresh="$(label fresh)"
            check_inputs "$fresh"
            keep_on_failure
            finish_creation "$fresh"
            trap - EXIT
            report
            return
        fi
        log "$CONTAINER exists: its mounts, themes, port, image and dataset stay as created (destroy --yes to change them); applying FA_DEV_MODULES"
        cmd_link
        report
        return
    fi

    case "$FA_DEV_PORT" in ''|*[!0-9]*) die "FA_DEV_PORT takes a number, not '$FA_DEV_PORT'" ;; esac
    check_inputs yes
    local m t
    for t in $FA_DEV_THEMES; do
        [ -d "$FA_DEV_THEMES_ROOT/$t" ] || die "FA_DEV_THEMES lists $t, but $FA_DEV_THEMES_ROOT/$t is not a directory"
    done
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$FA_DEV_PORT\$"; then
        die "port $FA_DEV_PORT is already in use on this machine; set FA_DEV_PORT to another"
    fi

    local fresh=yes
    if docker volume inspect "$VOLUME" >/dev/null 2>&1; then
        fresh=no
        log "keeping the database already in $VOLUME"
    fi

    local run_args=(-p "$FA_DEV_BIND:$FA_DEV_PORT:80" -v "$VOLUME:/var/lib/mysql"
                    -v "$(cd "$FA_DEV_MODULES_ROOT" && pwd):$FA/modules"
                    --label "fa-dev.port=$FA_DEV_PORT" --label "fa-dev.dataset=$FA_DEV_DATASET"
                    --label "fa-dev.fresh=$fresh")
    for t in $FA_DEV_THEMES; do run_args+=(-v "$(cd "$FA_DEV_THEMES_ROOT/$t" && pwd):$FA/themes/$t"); done
    for m in $FA_DEV_MOUNTS; do run_args+=(-v "$m"); done

    keep_on_failure
    ci_boot "$CONTAINER" "$FA_DEV_IMAGE" "${run_args[@]}"
    finish_creation "$fresh"
    trap - EXIT
    report
}

main() {
    case "$CMD" in
        up) cmd_up ;;
        link) load_config; require_env; cmd_link ;;
        activate) load_config; require_env; activate_all ;;
        down) require_env; docker stop "$CONTAINER" >/dev/null; log "$CONTAINER stopped; its data stays" ;;
        destroy)
            [ "${1:-}" = --yes ] || die "destroy removes $CONTAINER and its database ($VOLUME); run it with --yes"
            docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
            docker volume rm "$VOLUME" >/dev/null 2>&1 || true
            log "$ENV_NAME destroyed (the modules folder on this machine is untouched)" ;;
        status)
            require_env
            printf '%s: %s at %s\nmodules: %s\n' "$ENV_NAME" "$(running && echo running || echo stopped)" "$(url)" "$(applied | tr '\n' ' ')" ;;
        url) require_env; url ;;
        shell)
            require_env
            docker exec -it -w "$FA" -e HOME=/tmp "$CONTAINER" \
                setpriv --reuid="$(id -u)" --regid="$(id -g)" --groups=33 bash -c 'umask 002; exec bash' ;;
        exec)
            require_env
            local dir="$FA"
            if [ "${1:-}" = --dir ]; then dir="$FA/${2#/}"; shift 2; fi
            [ "$#" -ge 1 ] || die "usage: plugin-dev.sh [--env NAME] exec [--dir D] <command>"
            ci_as_user "$CONTAINER" "$dir" "$*" ;;
        logs)
            require_env
            case "${1:-errors}" in
                errors) docker exec "$CONTAINER" sh -c 'f=/var/www/html/tmp/errors.log; if [ -s "$f" ]; then tail -n 100 "$f"; else echo "(no errors logged)"; fi' ;;
                app) docker exec "$CONTAINER" sh -c 'tail -n 100 /var/log/apache2/error.log' ;;
                *) die "usage: plugin-dev.sh [--env NAME] logs [app|errors]" ;;
            esac ;;
        mail)
            require_env
            case "${1:-list}" in
                list) docker exec "$CONTAINER" sh -c 'cd /var/mail-catcher && ls -1t -- *.eml 2>/dev/null || echo "(no mail)"' ;;
                show) [ -n "${2:-}" ] || die "usage: plugin-dev.sh [--env NAME] mail show <file>"
                      docker exec "$CONTAINER" cat "/var/mail-catcher/$(basename "$2")" ;;
                clear) docker exec "$CONTAINER" sh -c 'rm -f /var/mail-catcher/*.eml' ;;
                *) die "usage: plugin-dev.sh [--env NAME] mail [list|show <file>|clear]" ;;
            esac ;;
        db)
            require_env
            case "${1:-}" in
                dump)
                    local out="${2:-fa-dev-$ENV_NAME-$(date +%Y%m%d-%H%M%S).sql.gz}"
                    docker exec "$CONTAINER" bash -c 'set -o pipefail; mariadb-dump --single-transaction --routines fa_test | gzip -c' > "$out"
                    gzip -t "$out"
                    log "dumped to $out" ;;
                load)
                    [ -f "${2:-}" ] || { printf 'plugin-dev.sh: no such file: %s\n' "${2:-}" >&2; exit 2; }
                    load_config
                    load_dataset "$2"
                    activate_all ;;
                shell) docker exec -it "$CONTAINER" mariadb fa_test ;;
                *) die "usage: plugin-dev.sh [--env NAME] db dump [file] | db load <file> | db shell" ;;
            esac ;;
        *) printf 'plugin-dev.sh: unknown command %s\n' "$CMD" >&2; exit 1 ;;
    esac
}
main "$@"
