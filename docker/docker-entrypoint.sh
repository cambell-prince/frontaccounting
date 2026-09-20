#!/bin/sh
#
# Decide whether xdebug is loaded at all, then hand over to the stock php
# entrypoint.
#
# FrontAccounting guards its xdebug calls with function_exists('xdebug_call_file')
# — includes/db/connect_db_mysqli.inc, in the $go_debug branch that runs on
# every single query. Under xdebug 3 that guard is wrong: the function exists
# whenever the extension is loaded, but calling it throws
#
#   Function must be enabled in php.ini by setting 'xdebug.mode' to 'develop'
#
# unless the mode allows it. So an idle xdebug at mode=off does not sit out of
# the way — it takes down every request and every test. Leaving the extension
# unloaded instead makes function_exists() return false, which is the answer FA
# is actually asking for.
#
# XDEBUG_MODE is fixed when the container is created, so changing it in
# docker/.env needs `docker/fa up` (which recreates), not `docker/fa restart`.
set -eu

INI=/usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

case "${XDEBUG_MODE:-off}" in
    ''|off)
        if [ -f "$INI" ]; then
            mv "$INI" "$INI.disabled"
        fi
        ;;
    *)
        if [ -f "$INI.disabled" ]; then
            mv "$INI.disabled" "$INI"
        fi
        ;;
esac

exec docker-php-entrypoint "$@"
