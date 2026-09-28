#!/usr/bin/env bash
#
# The CI image on its own: it boots ready, FrontAccounting signs in, the
# fixture is loaded, mail is caught, and the FA tree is writable by group
# www-data.
#
#   FA_CI_IMAGE=<image> docker/ci/test/image.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$here/../lib.sh"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"
: "${FA_CI_IMAGE:?set FA_CI_IMAGE to the image under test}"

c="fa-ci-test-image-$$"
trap 'docker rm -f "$c" >/dev/null 2>&1 || true' EXIT

echo "image: $FA_CI_IMAGE"
start="$(date +%s)"
expect_status 0 "boots and becomes ready" ci_boot "$c" "$FA_CI_IMAGE"
expect_status 0 "ready within 60s" test "$(( $(date +%s) - start ))" -lt 60
# shellcheck disable=SC2016 # expands in the container
expect_status 0 "FA signs in as test/test" docker exec "$c" sh -c 'fa-ci-login "$(mktemp)"'
expect_status 0 "the fixture is loaded" docker exec "$c" mariadb -N fa_test \
    -e "SELECT COUNT(*) FROM 0_users WHERE user_id = 'test'"
expect_contains "the fixture has the test user" "1" "$OUT"
expect_status 0 "user fa reaches fa_test over TCP" docker exec "$c" mariadb -h 127.0.0.1 -u fa -pfa -N fa_test -e 'SELECT 1'
expect_status 0 "mail() lands in the catcher" docker exec "$c" sh -c \
    'php -r "mail(\"a@example.com\", \"ci smoke subject\", \"body\");" && grep -l "ci smoke subject" /var/mail-catcher/*.eml'
expect_status 0 "the FA tree is writable by group www-data" docker exec "$c" \
    setpriv --reuid=4242 --regid=4242 --groups=33 sh -c \
    'umask 002; touch /var/www/html/tmp/ci-write-test /var/www/html/company/0/ci-write-test /var/www/html/config_db.php'
expect_status 0 "xdebug is not loaded" sh -c "! docker exec $c php -m | grep -qi xdebug"
expect_status 0 "opcache revalidates every request" docker exec "$c" sh -c \
    'php -i | grep -q "opcache.revalidate_freq => 0"'
# shellcheck disable=SC2016 # expands in the container
expect_status 0 "FA_DB_PREFIX is in the environment" docker exec "$c" sh -c 'test "$FA_DB_PREFIX" = 0_'
# shellcheck disable=SC2016 # expands in the container
expect_status 0 "Apache creates group-writable files" docker exec "$c" sh -c '. /etc/apache2/envvars && test "$(umask)" = 0002'
# shellcheck disable=SC2016 # expands in the container
expect_status 0 "the mail catcher's directory is not sticky" docker exec "$c" sh -c 'test "$(stat -c %a /var/mail-catcher)" = 777'
expect_status 0 "errors are logged, not displayed, and notices are off" docker exec "$c" php -r \
    'exit((ini_get("display_errors") == "" || ini_get("display_errors") == "0") && !(error_reporting() & E_NOTICE) && ini_get("memory_limit") === "512M" ? 0 : 1);'
expect_status 0 "databases default to utf8mb4_general_ci, as the plugins' old stacks did" docker exec "$c" mariadb -N -e "SELECT DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = 'fa_test'"
expect_contains "fa_test's collation" "utf8mb4_general_ci" "$OUT"
# shellcheck disable=SC2016 # expands in the container
expect_status 0 "tmp/errors.log is writable by group www-data from the start" docker exec "$c" sh -c \
    'test -f /var/www/html/tmp/errors.log && test "$(stat -c %G /var/www/html/tmp/errors.log)" = www-data && test -n "$(find /var/www/html/tmp/errors.log -perm -g+w)"'
expect_status 0 "the test uid can append to tmp/errors.log" docker exec "$c" \
    setpriv --reuid=4242 --regid=4242 --groups=33 sh -c 'echo ci-append >> /var/www/html/tmp/errors.log'
expect_status 0 "loads a dump file as the dataset, as it is" docker exec "$c" sh -c '
    mariadb-dump fa_test | gzip > /tmp/before.sql.gz &&
    mariadb fa_test -e "CREATE TABLE 0_ci_after (id int)" &&
    fa-ci-dataset /tmp/before.sql.gz &&
    ! mariadb -N fa_test -e "SHOW TABLES LIKE \"0_ci_after\"" | grep -q . &&
    mariadb -N fa_test -e "SELECT CONCAT(\"login=\", user_id) FROM 0_users WHERE user_id = \"test\""'
expect_contains "with the test login" "login=test" "$OUT"
expect_status 2 "a missing dataset file is refused" docker exec "$c" fa-ci-dataset /tmp/no-such.sql
finish
