#!/bin/sh
# Start MariaDB, wait for it, then hand over to the CMD (Apache in the
# foreground). Everything a plugin's tests need runs in this one container.
set -eu

mkdir -p /run/mysqld /var/run/apache2
chown mysql:mysql /run/mysqld
# A pid file left by an unclean stop makes Apache refuse to start.
rm -f /var/run/apache2/apache2.pid

mariadbd-safe --user=mysql >/dev/null 2>&1 &

i=0
until mariadb-admin --silent ping >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -lt 60 ] || { echo "fa-ci: MariaDB did not start" >&2; exit 1; }
    sleep 1
done

exec "$@"
