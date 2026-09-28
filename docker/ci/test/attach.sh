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

expect_status 0 "prints ci_alpha's extension id" docker exec "$c" fa-ci-ext-id ci_alpha
expect_contains "ci_alpha is extension 1" "1" "$OUT"
expect_status 0 "prints ci_beta's extension id" docker exec "$c" fa-ci-ext-id ci_beta
expect_contains "ci_beta is extension 2" "2" "$OUT"
expect_status 1 "an unregistered module has no id" docker exec "$c" fa-ci-ext-id ci_nothing

expect_status 0 "grants the test user every area" docker exec "$c" fa-ci-grant
expect_contains "to role FA CI" "to role FA CI" "$OUT"
# ci_alpha is extension 1, so FA maps its area to (1<<16)|(100<<8)|100.
expect_status 0 "role FA CI holds ci_alpha's area" sql \
    "SELECT 'has-area' FROM 0_security_roles WHERE role = 'FA CI' AND FIND_IN_SET('91236', REPLACE(areas, ';', ','))"
expect_contains "code 91236" "has-area" "$OUT"
# ci_alpha's second area, SA_CI_ALPHA_SALES = SS_SALES|71 = (12<<8)|71 = 3143,
# sits in the CORE section SS_SALES, so add_access_extensions() leaves its
# section untranslated (it's not one of ci_alpha's own $security_sections
# entries). With ci_alpha as extension 1 (extcode = 1<<16 = 65536) and this
# area declared second (acode starts at 100, so this one gets 101):
#   area    = extcode | SS_SALES | acode = 65536 | 3072 | 101 = 68709
#   section = area & ~0xff                = 65536 | 3072       = 68608
# grant.php has to add that section itself: it's not a $security_sections
# key, so the section scan alone would miss it and the area would stay
# unreachable (includes/current_user.inc keeps only areas whose section is
# granted).
expect_status 0 "role FA CI holds ci_alpha's core-section area" sql \
    "SELECT 'has-area' FROM 0_security_roles WHERE role = 'FA CI' AND FIND_IN_SET('68709', REPLACE(areas, ';', ','))"
expect_contains "code 68709" "has-area" "$OUT"
expect_status 0 "role FA CI holds that area's core section" sql \
    "SELECT 'has-section' FROM 0_security_roles WHERE role = 'FA CI' AND FIND_IN_SET('68608', REPLACE(sections, ';', ','))"
expect_contains "code 68608" "has-section" "$OUT"
expect_status 0 "the test user is on role FA CI" sql \
    "SELECT 'on-fa-ci' FROM 0_users u JOIN 0_security_roles r ON r.id = u.role_id WHERE u.user_id = 'test' AND r.role = 'FA CI'"
expect_contains "user test" "on-fa-ci" "$OUT"
expect_status 0 "role 2 is untouched" sql \
    "SELECT 'has-area' FROM 0_security_roles WHERE id = 2 AND FIND_IN_SET('91236', REPLACE(areas, ';', ','))"
expect_absent "role 2 lacks ci_alpha's area" "has-area" "$OUT"

expect_status 0 "grants one module's areas to a role" docker exec "$c" fa-ci-grant --role 2 --module ci_alpha
expect_contains "reporting what it granted" "of ci_alpha to role 2" "$OUT"
expect_status 0 "role 2 now holds ci_alpha's section and area" sql \
    "SELECT 'has-both' FROM 0_security_roles WHERE id = 2 AND FIND_IN_SET('91236', REPLACE(areas, ';', ',')) AND FIND_IN_SET('91136', REPLACE(sections, ';', ','))"
expect_contains "codes 91136 and 91236" "has-both" "$OUT"
# Same arithmetic as above (extcode 65536 | SS_SALES 3072 | acode 101 = 68709,
# section 65536 | 3072 = 68608): role 2's grant must add that core section
# too, not just the area.
expect_status 0 "role 2 also holds ci_alpha's core-section area and its section" sql \
    "SELECT 'has-both' FROM 0_security_roles WHERE id = 2 AND FIND_IN_SET('68709', REPLACE(areas, ';', ',')) AND FIND_IN_SET('68608', REPLACE(sections, ';', ','))"
expect_contains "codes 68608 and 68709" "has-both" "$OUT"
expect_status 0 "granting again adds nothing" docker exec "$c" fa-ci-grant --role 2 --module ci_alpha
expect_contains "zero the second time" "granted 0 areas of ci_alpha to role 2" "$OUT"
expect_status 2 "a malformed grant is refused" docker exec "$c" fa-ci-grant --role two --module ci_alpha
finish
