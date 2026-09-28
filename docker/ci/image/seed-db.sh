#!/bin/sh
# Build time only: load the fixture into MariaDB's datadir, so every container
# of the image starts with fa_test ready. Accounts match the committed test
# fixtures: fa/fa for FrontAccounting, and a passwordless travis, which
# modules/tests/data/config_db.php expects.
set -eu

mkdir -p /run/mysqld
chown mysql:mysql /run/mysqld
mariadbd --user=mysql --skip-networking &
pid=$!

i=0
until mariadb-admin --silent ping >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -lt 60 ] || { echo "seed-db: MariaDB did not start" >&2; exit 1; }
    sleep 1
done

mariadb <<'SQL'
CREATE DATABASE fa_test;
CREATE USER 'fa'@'%' IDENTIFIED BY 'fa';
CREATE USER 'fa'@'localhost' IDENTIFIED BY 'fa';
GRANT ALL PRIVILEGES ON fa_test.* TO 'fa'@'%';
GRANT ALL PRIVILEGES ON fa_test.* TO 'fa'@'localhost';
CREATE USER 'travis'@'%' IDENTIFIED BY '';
CREATE USER 'travis'@'localhost' IDENTIFIED BY '';
GRANT ALL PRIVILEGES ON *.* TO 'travis'@'%';
GRANT ALL PRIVILEGES ON *.* TO 'travis'@'localhost';
SQL
gunzip -c /usr/local/share/fa-ci/fa_test.sql.gz | mariadb fa_test

mariadb-admin shutdown
wait "$pid" || true
