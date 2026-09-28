#!/bin/sh
# Dump the server's database into backup/, for `make.phar db-backup`.
#
#   deploy/db-backup.sh <ssh> <db> "<mysqldump options>"
#
# mysqldump runs on the server, so its credentials come from there: the ssh
# user's ~/.my.cnf, or options such as --defaults-extra-file=... passed in.
# Prints the path of the dump, which ends up as backup/<db>-<stamp>.sql.gz.
set -eu

ssh_to="$1"
db="$2"
opts="${3:-}"

[ -n "$ssh_to" ] && [ -n "$db" ] || { echo "db-backup: set db_ssh and db in makefile.json or pass them" >&2; exit 1; }

mkdir -p backup
out="backup/$db-$(date +%Y%m%d-%H%M%S).sql.gz"
tmp="$out.part"

# Compressed on the server. The pipe hides mysqldump's exit status, so a failed
# dump is caught below by its missing trailer instead.
ssh -C "$ssh_to" "mysqldump --single-transaction --quick --routines --triggers $opts '$db' | gzip -c" > "$tmp"
gzip -t "$tmp"
gunzip -c "$tmp" | tail -n 1 | grep -q 'Dump completed' \
    || { echo "db-backup: $tmp does not end with 'Dump completed'; the dump is incomplete" >&2; exit 1; }
mv "$tmp" "$out"
echo "==> $out ($(du -h "$out" | cut -f1))"
