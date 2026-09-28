#!/bin/sh
#
# Decide whether xdebug is loaded at all, then start Apache.
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
# phpdismod/phpenmod handle both SAPIs at once, which matters here: Debian has a
# separate conf.d for apache2 and for cli, and the test suite runs under the
# latter.
#
# XDEBUG_MODE is fixed when the container is created, so changing it in
# docker/.env needs `docker/fa up` (which recreates), not `docker/fa restart`.
set -eu

if command -v phpdismod >/dev/null 2>&1; then
    case "${XDEBUG_MODE:-off}" in
        ''|off) phpdismod -v "${PHP_VERSION:-ALL}" xdebug 2>/dev/null || true ;;
        *)      phpenmod  -v "${PHP_VERSION:-ALL}" xdebug 2>/dev/null || true ;;
    esac
fi

# Not sourcing /etc/apache2/envvars here on purpose: it references variables it
# has not set yet, so under `set -u` it aborts with "APACHE_CONFDIR: parameter
# not set". apache2ctl sources it itself, with the right shell options.
#
# The run directory is normally made by the init system, which a container does
# not have, and a pid file left by an unclean stop makes Apache refuse to start.
mkdir -p /var/run/apache2
rm -f /var/run/apache2/apache2.pid

exec "$@"
