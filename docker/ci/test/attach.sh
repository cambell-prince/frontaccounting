#!/usr/bin/env bash
#
# The image's module helpers against fixture modules: registration,
# activation through FrontAccounting's own form, dependency order, a failing
# activation, and the grant.
#
#   FA_CI_IMAGE=<image> docker/ci/test/attach.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$here/../lib.sh"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"
: "${FA_CI_IMAGE:?set FA_CI_IMAGE to the image under test}"

fx="$here/fixtures/modules"
c="fa-ci-test-attach-$$"
trap 'docker rm -f "$c" >/dev/null 2>&1 || true' EXIT

mounts=()
for m in ci_alpha ci_beta ci_broken; do mounts+=(-v "$fx/$m:/var/www/html/modules/$m:ro"); done
ci_boot "$c" "$FA_CI_IMAGE" "${mounts[@]}"

reg() { docker exec -u www-data "$c" fa-ci-register "$1" "modules/$1"; }
act() { docker exec "$c" fa-ci-activate "$1"; }
sql() { docker exec "$c" mariadb -N fa_test -e "$1"; }

expect_status 0 "registers ci_alpha" reg ci_alpha
expect_contains "as extension 1" "registered ci_alpha as extension 1" "$OUT"
expect_status 0 "registering again is a no-op" reg ci_alpha
expect_contains "and says so" "already registered" "$OUT"
expect_status 0 "activates ci_alpha" act ci_alpha
expect_status 0 "activation ran ci_alpha's update SQL" sql "SELECT marker FROM 0_ci_alpha"
expect_contains "ci_alpha's table holds its marker" "alpha-installed" "$OUT"

expect_status 0 "registers ci_beta" reg ci_beta
expect_status 0 "activates ci_beta, which needs ci_alpha" act ci_beta
# shellcheck disable=SC2016 # expands in the container
expect_status 0 "ci_alpha stays active after ci_beta" docker exec "$c" php -r '
    include "/var/www/html/company/0/installed_extensions.php";
    foreach ($installed_extensions as $e) if ($e["package"] === "ci_alpha" && $e["active"]) exit(0);
    exit(1);'

expect_status 0 "registers ci_broken" reg ci_broken
expect_status 1 "a failing activation is reported" act ci_broken
expect_contains "naming the module" "did not activate ci_broken" "$OUT"
expect_status 1 "an unregistered module is refused" act ci_nothing
expect_contains "saying why" "not registered" "$OUT"

expect_status 0 "grants the admin role every area" docker exec "$c" fa-ci-grant
expect_contains "reporting the count" "granted " "$OUT"
# ci_alpha is extension 1, so FA maps its area to (1<<16)|(100<<8)|100.
expect_status 0 "role 2 holds ci_alpha's area" sql \
    "SELECT 'has-area' FROM 0_security_roles WHERE id = 2 AND FIND_IN_SET('91236', REPLACE(areas, ';', ','))"
expect_contains "code 91236" "has-area" "$OUT"
finish
