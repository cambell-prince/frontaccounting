#!/usr/bin/env bash
#
# plugin-test.sh end to end against the fixture modules: where and as whom
# commands run, activation order, --with (path and git), failures and clean-up.
#
#   FA_CI_IMAGE=<image> docker/ci/test/driver.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$here/../lib.sh"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"
: "${FA_CI_IMAGE:?set FA_CI_IMAGE to the image under test}"
export FA_CI_IMAGE

d="$here/../plugin-test.sh"
fx="$here/fixtures/modules"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A git repository of ci_alpha on branch main, under a path containing '@',
# for --with NAME=REPO@REF.
mkdir -p "$tmp/with@at"
git init -q -b main "$tmp/with@at/alpha"
cp -R "$fx/ci_alpha/." "$tmp/with@at/alpha/"
git -C "$tmp/with@at/alpha" add -A
git -C "$tmp/with@at/alpha" -c user.name=ci -c user.email=ci@example.com commit -q -m alpha
# ci_alpha under a path containing a space.
mkdir -p "$tmp/with space"
cp -R "$fx/ci_alpha" "$tmp/with space/ci_alpha"

expect_status 0 "runs the test in the plugin directory, after activation" \
    "$d" "$fx/ci_alpha" -- 'pwd; mariadb -h localhost -u fa -pfa -N fa_test -e "SELECT marker FROM 0_ci_alpha"'
expect_contains "in modules/ci_alpha" "/var/www/html/modules/ci_alpha" "$OUT"
expect_contains "after ci_alpha's SQL ran" "alpha-installed" "$OUT"

expect_status 0 "as the caller's uid, with group www-data" \
    "$d" --no-activate "$fx/ci_alpha" -- "test \"\$(id -u)\" = $(id -u) && id -G | tr ' ' '\n' | grep -qx 33"
expect_status 3 "exits with the test command's status" "$d" "$fx/ci_alpha" -- 'exit 3'
expect_contains "and shows FA's error log on failure" "FrontAccounting tmp/errors.log" "$OUT"
expect_status 1 "fails when activation fails" "$d" "$fx/ci_broken" -- true
expect_contains "saying which module" "did not activate ci_broken" "$OUT"
expect_status 1 "a dependency has to be activated first" "$d" "$fx/ci_beta" -- true
expect_status 0 "--with PATH activates the dependency first" \
    "$d" --with "ci_alpha=$fx/ci_alpha" "$fx/ci_beta" -- true
expect_status 0 "--with REPO@REF clones it ('@' inside the repo path)" \
    "$d" --with "ci_alpha=$tmp/with@at/alpha@main" "$fx/ci_beta" -- \
    'mariadb -h localhost -u fa -pfa -N fa_test -e "SELECT marker FROM 0_ci_alpha"'
expect_contains "and activates the clone" "alpha-installed" "$OUT"
expect_status 1 "--with naming the plugin itself is refused" \
    "$d" --with "ci_alpha=$fx/ci_alpha" "$fx/ci_alpha" -- true
expect_contains "with a reason" "is the plugin under test" "$OUT"
expect_status 0 "a checkout path with a space" "$d" "$tmp/with space/ci_alpha" -- true
# shellcheck disable=SC2016 # expands in the container
expect_status 0 "--setup runs before activation" \
    "$d" --setup 'grep -c ci_alpha /var/www/html/company/0/installed_extensions.php > /tmp/at-setup || true' \
    "$fx/ci_alpha" -- 'test "$(cat /tmp/at-setup)" = 0'
expect_status 0 "--no-activate leaves it unregistered" \
    "$d" --no-activate "$fx/ci_alpha" -- '! grep -q ci_alpha /var/www/html/company/0/installed_extensions.php'
expect_status 0 "--name for a checkout without hooks.php" \
    "$d" --no-activate --name ci_plain "$fx/ci_plain" -- 'test -f /var/www/html/modules/ci_plain/README'
expect_status 1 "no hooks.php and no --name" "$d" "$fx/ci_plain" -- true
expect_contains "says to pass --name" "pass --name" "$OUT"
expect_status 0 "--mount adds a bind mount" \
    "$d" --no-activate --mount "$fx/ci_plain:/opt/extra:ro" "$fx/ci_alpha" -- 'test -f /opt/extra/README'
# shellcheck disable=SC2016 # expands in the container
expect_status 0 "COMPOSER_CACHE_DIR is mounted for composer" \
    env COMPOSER_CACHE_DIR="$tmp/composer-cache" "$d" --no-activate "$fx/ci_alpha" -- \
    'test "$COMPOSER_CACHE_DIR" = /tmp/composer-cache && touch /tmp/composer-cache/seen'
expect_status 0 "and writes land in the host directory" test -f "$tmp/composer-cache/seen"
# shellcheck disable=SC2016 # expands in the container
expect_status 0 "--dataset demo loads FA's demo data before activation" \
    "$d" --dataset demo "$fx/ci_alpha" -- \
    'mariadb -h localhost -u fa -pfa -N fa_test -e "SELECT CONCAT(\"user\", \"=\", user_id) FROM 0_users WHERE user_id IN (\"admin\", \"test\") ORDER BY user_id; SELECT marker FROM 0_ci_alpha; SELECT COUNT(*) FROM 0_debtors_master; SELECT IF(COUNT(*) > 0, CONCAT(\"fiscal\", \"-\", \"covered\"), \"no-year\") FROM 0_fiscal_year WHERE CURDATE() BETWEEN \`begin\` AND \`end\`"'
expect_contains "the demo admin" "user=admin" "$OUT"
expect_contains "and the package's test login" "user=test" "$OUT"
expect_contains "ci_alpha activated on top" "alpha-installed" "$OUT"
expect_contains "a fiscal year covers today" "fiscal-covered" "$OUT"
expect_status 0 "--dataset demo keeps the general collation" "$d" --dataset demo "$fx/ci_alpha" -- 'mariadb -h localhost -u fa -pfa -N -e "SELECT DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = \"fa_test\""'
expect_contains "general_ci after the reload" "utf8mb4_general_ci" "$OUT"
expect_status 1 "an unknown dataset is refused" "$d" --dataset nope "$fx/ci_alpha" -- true
expect_contains "naming the choices" "test or demo" "$OUT"
expect_status 0 "no container is left behind" sh -c "! docker ps -a --format '{{.Names}}' | grep -q '^fa-ci-ci_'"
finish
