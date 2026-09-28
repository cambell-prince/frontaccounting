#!/usr/bin/env bash
#
# plugin-dev.sh end to end against the fixture modules: the modules folder
# mounted live, an opt-in list applied with link, environments that persist on
# their own port and volume, backups, live extension ids, db and mail.
#
#   FA_CI_IMAGE=<image> docker/ci/test/dev.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"
: "${FA_CI_IMAGE:?set FA_CI_IMAGE to the image under test}"
export FA_DEV_IMAGE="$FA_CI_IMAGE"

d="$here/../plugin-dev.sh"
TMP_A="$(mktemp -d)"
mods="$TMP_A/modules"
cp -R "$here/fixtures/modules" "$mods"
# A module with no install SQL, to show where unlisted modules' ids go.
mkdir -p "$mods/ci_gamma"
# shellcheck disable=SC2016 # PHP, not the shell
printf '<?php\nclass hooks_ci_gamma extends hooks\n{\n\tvar $module_name = "ci_gamma";\n}\n' > "$mods/ci_gamma/hooks.php"
# The init convention: ci_alpha's tools/init.sh leaves a row behind.
mkdir -p "$mods/ci_alpha/tools"
cat > "$mods/ci_alpha/tools/init.sh" <<'SH'
#!/bin/sh
mariadb -h "$FA_DB_HOST" -u "$FA_DB_USER" -p"$FA_DB_PASSWORD" "$FA_DB_NAME" \
    -e "INSERT INTO 0_ci_alpha (marker) VALUES (CONCAT('init', '-ran'))"
SH
export FA_DEV_MODULES_ROOT="$mods"

free_port() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
env_a="citest$$a"; env_b="citest$$b"; env_c="citest$$c"; env_e="citest$$e"; env_f="citest$$f"; env_g="citest$$g"
port_a="$(free_port)"; port_c="$(free_port)"; port_e="$(free_port)"; port_f="$(free_port)"; port_g="$(free_port)"
cleanup() {
    for e in "$env_a" "$env_b" "$env_c" "$env_e" "$env_f" "$env_g"; do
        docker rm -f "fa-dev-$e" >/dev/null 2>&1 || true
        docker volume rm "fa-dev-$e-db" >/dev/null 2>&1 || true
    done
    rm -rf "$TMP_A"
}
trap cleanup EXIT

cfg_a="$TMP_A/a.env"
# The config's port is wrong on purpose: FA_DEV_PORT in the shell must win.
printf 'FA_DEV_MODULES="ci_alpha ci_beta"\nFA_DEV_PORT=1\n' > "$cfg_a"
dev_a() { FA_DEV_PORT="$port_a" "$d" --env "$env_a" --config "$cfg_a" "$@"; }
# shellcheck disable=SC2016 # expanded by sh and PHP in the container
state() { "$d" --env "$1" exec 'php -r "include \"/var/www/html/company/0/installed_extensions.php\"; foreach (\$installed_extensions as \$id => \$e) echo \$e[\"package\"], \"@\", \$id, \"=\", \$e[\"active\"] ? \"on\" : \"off\", \" \";"'; }
sqlq() { "$d" --env "$1" exec "mariadb -h localhost -u fa -pfa -N fa_test -e \"$2\""; }

expect_status 0 "up creates an environment from the config, the shell winning" dev_a up
expect_contains "and prints its URL" "http://localhost:$port_a/" "$OUT"
expect_status 0 "FrontAccounting answers on the port" curl -fsS -o /dev/null "http://localhost:$port_a/index.php"
expect_status 0 "only on this machine by default" docker port "fa-dev-$env_a" 80/tcp
expect_contains "127.0.0.1" "127.0.0.1:$port_a" "$OUT"
expect_status 0 "reads the lists" state "$env_a"
expect_contains "ci_alpha on" "ci_alpha@1=on" "$OUT"
expect_contains "ci_beta on, after it" "ci_beta@2=on" "$OUT"
expect_absent "folders not listed are not extensions" "ci_plain" "$OUT"
expect_status 0 "ci_alpha's tools/init.sh ran" sqlq "$env_a" "SELECT marker FROM 0_ci_alpha"
expect_contains "its row" "init-ran" "$OUT"

printf '<?php echo "live-" . "edit";\n' > "$mods/ci_alpha/probe.php"
expect_status 0 "an edit on the host is live" curl -fsS "http://localhost:$port_a/modules/ci_alpha/probe.php"
expect_contains "served as written" "live-edit" "$OUT"
# shellcheck disable=SC2016 # expanded in the container
expect_status 0 "exec runs as the caller in the FA tree" "$d" --env "$env_a" exec 'echo "uid=$(id -u) dir=$(pwd)"'
expect_contains "as the caller" "uid=$(id -u)" "$OUT"
expect_contains "in the FA tree" "dir=/var/www/html" "$OUT"
expect_status 0 "exec --dir runs under it" "$d" --env "$env_a" exec --dir modules/ci_beta pwd
expect_contains "in modules/ci_beta" "/var/www/html/modules/ci_beta" "$OUT"

id_before="$(docker inspect -f '{{.Id}}' "fa-dev-$env_a")"
printf 'FA_DEV_MODULES="ci_alpha"\nFA_DEV_PORT=1\n' > "$cfg_a"
expect_status 0 "link applies a smaller list" dev_a link
expect_status 0 "reads the lists" state "$env_a"
expect_contains "ci_beta off" "ci_beta@2=off" "$OUT"
expect_contains "ci_alpha still on" "ci_alpha@1=on" "$OUT"
printf 'FA_DEV_MODULES="ci_alpha ci_beta"\nFA_DEV_PORT=1\n' > "$cfg_a"
expect_status 0 "link applies it again" dev_a link
expect_status 0 "reads the lists" state "$env_a"
expect_contains "ci_beta on again" "ci_beta@2=on" "$OUT"
expect_status 0 "the same container" test "$(docker inspect -f '{{.Id}}' "fa-dev-$env_a")" = "$id_before"
printf 'FA_DEV_MODULES="ci_alpha"\nFA_DEV_PORT=1\n' > "$cfg_a"
expect_status 0 "activate with a smaller list" dev_a activate
expect_status 0 "reads the lists" state "$env_a"
expect_contains "deactivates what it no longer lists" "ci_beta@2=off" "$OUT"
expect_status 0 "status" "$d" --env "$env_a" status
expect_absent "no longer listing it" "ci_beta" "$OUT"
printf 'FA_DEV_MODULES="ci_alpha ci_beta"\nFA_DEV_PORT=1\n' > "$cfg_a"

expect_status 0 "a row to keep" sqlq "$env_a" "INSERT INTO 0_ci_alpha (marker) VALUES (CONCAT('kept', '-across-restarts'))"
expect_status 0 "down stops it" "$d" --env "$env_a" down
expect_status 0 "up again keeps the data" env FA_DEV_DATASET=demo FA_DEV_PORT="$port_a" "$d" --env "$env_a" --config "$cfg_a" up
expect_contains "saying what stays as created" "stay as created" "$OUT"
expect_status 0 "the row is still there" sqlq "$env_a" "SELECT marker FROM 0_ci_alpha"
expect_contains "kept" "kept-across-restarts" "$OUT"
expect_status 0 "status" "$d" --env "$env_a" status
expect_contains "running" "running" "$OUT"
expect_status 0 "url" "$d" --env "$env_a" url
expect_contains "the port" "http://localhost:$port_a/" "$OUT"

expect_status 1 "a busy port is reported" env FA_DEV_MODULES=ci_alpha FA_DEV_PORT="$port_a" "$d" --env "$env_b" up
expect_contains "naming the port" "port $port_a" "$OUT"
expect_status 0 "and nothing was created" sh -c "! docker inspect fa-dev-$env_b >/dev/null 2>&1"
expect_status 1 "a listed folder without hooks.php is refused" env FA_DEV_MODULES=ci_plain FA_DEV_PORT="$(free_port)" "$d" --env "$env_b" up
expect_contains "naming it" "ci_plain" "$OUT"

cat > "$TMP_A/live-extensions.php" <<'PHP'
<?php
$next_extension_id = 12;
$installed_extensions = array (
  7 => array ('package' => 'ci_beta', 'name' => 'ci_beta', 'version' => '-', 'available' => '', 'type' => 'extension', 'path' => 'modules/ci_beta', 'active' => true),
  5 => array ('package' => 'ci_alpha', 'name' => 'ci_alpha', 'version' => '-', 'available' => '', 'type' => 'extension', 'path' => 'modules/ci_alpha', 'active' => true),
  9 => array ('package' => 'not_here', 'name' => 'not_here', 'version' => '-', 'available' => '', 'type' => 'extension', 'path' => 'modules/not_here', 'active' => true),
);
PHP
dev_c() { FA_DEV_MODULES="ci_alpha ci_beta ci_gamma" FA_DEV_PORT="$port_c" FA_DEV_BIND=0.0.0.0 FA_DEV_EXTENSIONS="$TMP_A/live-extensions.php" "$d" --env "$env_c" "$@"; }
expect_status 0 "a live site's extension ids, in the list's own order (ci_beta needs ci_alpha first)" dev_c up
expect_status 0 "FA_DEV_BIND sets the address it listens on" docker port "fa-dev-$env_c" 80/tcp
expect_contains "all addresses" "0.0.0.0:$port_c" "$OUT"
expect_status 0 "reads the lists" state "$env_c"
expect_contains "ci_alpha keeps 5" "ci_alpha@5=on" "$OUT"
expect_contains "ci_beta keeps 7" "ci_beta@7=on" "$OUT"
expect_contains "an unlisted module comes after the file's ids" "ci_gamma@12=on" "$OUT"

expect_status 0 "a row to find in the dump" sqlq "$env_c" "INSERT INTO 0_ci_alpha (marker) VALUES (CONCAT('in', '-the-dump'))"
expect_status 0 "without ci_alpha's table, as a site before the module" sqlq "$env_c" "RENAME TABLE 0_ci_alpha TO 0_ci_alpha_aside"
expect_status 0 "db dump writes a gzipped file" "$d" --env "$env_c" db dump "$TMP_A/dump.sql.gz"
expect_status 0 "that is a real dump" sh -c "gunzip -c '$TMP_A/dump.sql.gz' | grep -q 'in-the-dump'"
expect_status 0 "db load" dev_c db load "$TMP_A/dump.sql.gz"
expect_status 0 "db load re-runs the modules' install SQL" sqlq "$env_c" "SELECT marker FROM 0_ci_alpha"
expect_contains "ci_alpha's table is back" "alpha-installed" "$OUT"
expect_contains "and its init ran again" "init-ran" "$OUT"
expect_status 0 "reads the lists" state "$env_c"
expect_contains "still at 5" "ci_alpha@5=on" "$OUT"

expect_status 0 "a mail is caught" "$d" --env "$env_c" exec 'php -r "mail(\"a@example.com\", \"dev mail \" . \"subject\", \"body\");"'
expect_status 0 "mail list shows it" "$d" --env "$env_c" mail list
expect_contains "an .eml" ".eml" "$OUT"
eml="$(printf '%s\n' "$OUT" | grep '\.eml$' | head -n 1)"
expect_status 0 "mail show prints it" "$d" --env "$env_c" mail show "$eml"
expect_contains "the subject" "dev mail subject" "$OUT"
expect_status 0 "mail clear" "$d" --env "$env_c" mail clear
expect_status 0 "leaves none" "$d" --env "$env_c" mail list
expect_contains "none" "(no mail)" "$OUT"

expect_status 0 "a backup as the dataset" env FA_DEV_MODULES=ci_alpha FA_DEV_PORT="$port_e" FA_DEV_DATASET="$TMP_A/dump.sql.gz" "$d" --env "$env_e" up
expect_status 0 "with the backup's data" sqlq "$env_e" "SELECT marker FROM 0_ci_alpha_aside"
expect_contains "the dumped row" "in-the-dump" "$OUT"
expect_status 0 "destroy it" "$d" --env "$env_e" destroy --yes

printf 'THIS IS NOT SQL;\n' > "$TMP_A/f.sql"
dev_f() { FA_DEV_MODULES=ci_alpha FA_DEV_PORT="$port_f" FA_DEV_DATASET="$TMP_A/f.sql" "$d" --env "$env_f" "$@"; }
expect_status 1 "a backup that won't load fails the creation" dev_f up
expect_status 0 "leaving it unfinished" sh -c "! docker exec fa-dev-$env_f test -f /var/lib/fa-dev/created"
gunzip -c "$TMP_A/dump.sql.gz" > "$TMP_A/f.sql"
expect_status 0 "up again, the backup fixed, finishes creating it" dev_f up
expect_contains "saying so" "did not finish" "$OUT"
expect_status 0 "with the backup's data" sqlq "$env_f" "SELECT marker FROM 0_ci_alpha_aside"
expect_contains "the dumped row" "in-the-dump" "$OUT"
expect_status 0 "and its modules" state "$env_f"
expect_contains "ci_alpha on" "ci_alpha@1=on" "$OUT"
expect_status 0 "marked created" docker exec "fa-dev-$env_f" test -f /var/lib/fa-dev/created
expect_status 0 "up once more takes the usual path" dev_f up
expect_contains "stays as created" "stay as created" "$OUT"
expect_status 0 "destroy it" "$d" --env "$env_f" destroy --yes

# A resumed creation with a live site's ids: the first attempt gives ci_gamma
# an id (12) and ci_broken the next before failing; the second, with a module
# added, must not hand out 12 again. Its database volume was already there,
# so its dataset file isn't loaded and needn't exist any more.
mkdir -p "$mods/ci_delta"
# shellcheck disable=SC2016 # PHP, not the shell
printf '<?php\nclass hooks_ci_delta extends hooks\n{\n\tvar $module_name = "ci_delta";\n}\n' > "$mods/ci_delta/hooks.php"
docker volume create "fa-dev-$env_g-db" >/dev/null
printf 'THIS IS NOT SQL;\n' > "$TMP_A/g.sql"
dev_g() { local m="$1"; shift; FA_DEV_MODULES="$m" FA_DEV_PORT="$port_g" FA_DEV_DATASET="$TMP_A/g.sql" FA_DEV_EXTENSIONS="$TMP_A/live-extensions.php" "$d" --env "$env_g" "$@"; }
expect_status 1 "a creation that fails after an unlisted module got its id" dev_g "ci_alpha ci_gamma ci_broken" up
rm -f "$TMP_A/g.sql"
expect_status 0 "up again finishes it, the unloaded dataset file gone" dev_g "ci_alpha ci_gamma ci_delta" up
expect_contains "saying so" "did not finish" "$OUT"
expect_status 0 "reads the lists" state "$env_g"
expect_contains "ci_gamma keeps 12" "ci_gamma@12=on" "$OUT"
expect_contains "ci_delta gets an id after every one given out" "ci_delta@14=on" "$OUT"
expect_status 0 "destroy it" "$d" --env "$env_g" destroy --yes
expect_status 2 "a missing backup is refused before anything starts" env FA_DEV_MODULES=ci_alpha FA_DEV_PORT="$port_e" FA_DEV_DATASET="$TMP_A/nope.sql" "$d" --env "$env_e" up
expect_status 0 "and nothing was created" sh -c "! docker inspect fa-dev-$env_e >/dev/null 2>&1"

expect_status 1 "destroy wants --yes" "$d" --env "$env_a" destroy
expect_contains "saying so" "--yes" "$OUT"
expect_status 0 "destroy --yes" "$d" --env "$env_a" destroy --yes
expect_status 0 "destroy removes only this environment" sh -c \
    "! docker inspect fa-dev-$env_a >/dev/null 2>&1 && ! docker volume inspect fa-dev-$env_a-db >/dev/null 2>&1 && docker inspect fa-dev-$env_c >/dev/null 2>&1"
expect_status 0 "the modules folder on the host is untouched" test -f "$mods/ci_alpha/hooks.php"
expect_status 1 "an unknown command is refused" "$d" --env "$env_c" frobnicate
expect_status 0 "destroy the other" "$d" --env "$env_c" destroy --yes
finish
