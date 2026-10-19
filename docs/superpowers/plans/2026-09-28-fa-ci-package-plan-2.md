# FrontAccounting CI Package Implementation Plan (plan 2 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use cjp:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task, wave by wave per the Execution Schedule. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move graphql, sgw_sales and api onto the FrontAccounting CI package, each keeping its current test counts. Then delete the test-only docker stacks of sgw_sales and api.

**Architecture:** Task 1 adds what the three plugins turned out to share to the package (FA fork):
- `--dataset demo`;
- a grant that leaves role 2 alone, plus a per-module grant to a given role;
- `fa-ci-ext-id`;
- environment parity with the old stacks.

Each plugin then gets a `tools/ci.sh` that runs inside the image, and a `.github/workflows/ci.yml` calling `plugin-test.yml@master-cp`.

**Tech Stack:** bash/sh, Docker, PHP 7.4/8.3, PHPUnit 9, phpstan, phpcs, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-28-fa-ci-package-design.md` (§4 and §5)

## Global Constraints

- The package lives in `cambell-prince/frontaccounting` `docker/ci/`. The plugins call `.github/workflows/plugin-test.yml@master-cp`.
- Image env after Task 1: `FA_ROOT=/var/www/html`, `FA_URL=http://localhost`, `FA_DB_HOST=localhost`, `FA_DB_NAME=fa_test`, `FA_DB_USER=fa`, `FA_DB_PASSWORD=fa`, `FA_DB_PREFIX=0_`.
- Datasets: `test` (the image's seeded `fa_test`, the default) and `demo` (FA's `sql/en_US-demo.sql`, plus login `test`/`test` on role 2, with fiscal years reaching today). Both keep the login `test`/`test`. `demo` also has `admin`/`password` (role 2).
- `fa-ci-grant` (no arguments) gives role `FA CI` every section and area and assigns it to user `test`. It never changes role 2. `fa-ci-grant --role <id> --module <name>` adds that module's extension sections and areas to role `<id>`.
- `fa-ci-ext-id <module>` prints the module's extension id from `company/0/installed_extensions.php`. It exits 1 if the module isn't registered.
- An extension's codes: section `(id << 16) | (100 << 8)`, first area `section | 100`.
- Parity targets are spec §5's table. A count lower than the target is a failure to investigate, never a matrix entry to drop, unless the task's text says otherwise.
- graphql keeps `docker/`. sgw_sales and api delete theirs.
- Commit as `git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit ...` with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Every repo here has `core.fileMode=false`. Record executable modes with `git update-index --chmod=+x <file>` after `git add`.
- Name scratch directories for what they are (`TMP_A=$(mktemp -d)`). Never assign one to `HOME` or another variable with a fixed meaning.

## Review Focus

- `--dataset demo` followed by activation: the module's `update_*.sql` must run against the demo tables, and the driver's activation must still sign in as `test`. Test: Task 1 driver.sh, "--dataset demo".
- The grant must leave role 2 exactly as the dataset has it. graphql's `noapi` user is role 2 and must lack SA_GRAPHQL. Test: Task 1 attach.sh, "role 2 is untouched"; Task 2 StackTest.
- Extension ids depend on activation order: graphql is 2 when `--with sgw_sales` comes first, and 1 in sgw_sales' GraphQL job. Codes must be derived, not literal. Test: Task 2 `seed.sh` and StackTest under both orders (graphql's own run, and sgw_sales' job).
- A test that silently skips because the environment differs, e.g. no mail catcher or no demo customer, shows up as a lower count. Test: every task compares its counts with spec §5, and graphql and sgw_sales' GraphQL suite run with `--fail-on-skipped`.
- The second-company step rewrites `config_db.php` and must restore it even if the test fails. Test: Task 2 Step 6 checks `config_db.php` is unchanged after a forced failure.

## Execution Schedule

| Wave | Tasks | Model | Notes |
|------|-------|-------|-------|
| 1 | Task 1 | opus | Package additions in the FA fork. Every plugin task consumes them, through the local image `fa-ci:local-cp-7.4` and the driver in this worktree. |
| CP1 | — | — | plan base..end of wave 1: code-review medium + spec check (spec §5). Must finish before wave 2, which builds on the contract. |
| 2 | Task 2, Task 3, Task 4 | opus, sonnet, sonnet | Parallel: three different repositories (graphql, sgw_sales, api), each in its own worktree. They share the docker daemon and `~/.cache/composer`; neither is exclusive. Container names carry the pid. |
| CP2 | — | — | plan base..end of wave 2 in each repo: code-review medium + spec check (full spec, §4-§5). |
| 3 | Controller | — | FA PR, CI, then merge when the user says. After master-cp publishes, the three plugin PRs, CI, then merge when the user says. |

Worktrees (the controller creates them before the wave that uses them):
- FA fork: `/home/cambell/src/sgw/frontaccounting/.claude/worktrees/ci-datasets`, branch `feature/ci-datasets` from `origin/master-cp`. This is where this plan lives.
- graphql: `/home/cambell/src/sgw/frontaccounting/.claude/worktrees/graphql-ci`, branch `ci/fa-ci-package` from `origin/main`.
- sgw_sales: `/home/cambell/src/sgw/frontaccounting/.claude/worktrees/sgw_sales-ci`, branch `ci/fa-ci-package` from `origin/master`.
- api: `/home/cambell/src/sgw/frontaccounting/.claude/worktrees/api-ci`, branch `ci/fa-ci-package` from `origin/master`.

`$FA_CI` below means `/home/cambell/src/sgw/frontaccounting/.claude/worktrees/ci-datasets/docker/ci`.

---

### Task 1: Package additions: datasets, grants, extension ids, parity

**Files (FA fork worktree):**
- Create: `docker/ci/image/fa-ci-dataset`
- Create: `docker/ci/image/fa-ci-ext-id`
- Modify: `docker/ci/image/fa-ci-grant` (whole file)
- Modify: `docker/ci/image/grant.php` (whole file)
- Modify: `docker/ci/image/php.ini` (the error and memory lines)
- Modify: `docker/ci/image/apache-fa-ci.conf` (one line added)
- Modify: `docker/ci/Dockerfile` (mail dir mode, Apache umask, `FA_DB_PREFIX`)
- Modify: `docker/ci/plugin-test.sh` (`--dataset`)
- Modify: `.github/workflows/plugin-test.yml` (`dataset` input)
- Modify: `docker/ci/README.md`
- Test: `docker/ci/test/image.sh`, `docker/ci/test/attach.sh`, `docker/ci/test/driver.sh`

**Interfaces:**
- Consumes: plan 1's package (`lib.sh`, `test/lib.sh`, `fa-ci-login`, `fa-ci-register`, `fa-ci-activate`, `build-image.sh`, the fixtures).
- Produces (used by Tasks 2-4):
  - `plugin-test.sh --dataset test|demo`;
  - workflow input `dataset` (string, default `test`);
  - `fa-ci-dataset <test|demo>` (run as root);
  - `fa-ci-grant [--role <id> --module <name>]` (any user);
  - `fa-ci-ext-id <module>` (any user);
  - env `FA_DB_PREFIX=0_`;
  - the local image `fa-ci:local-cp-7.4` rebuilt with all of this. Also build `fa-ci:local-upstream-7.4` for Task 2's upstream check.

- [ ] **Step 1: Write the failing tests**

In `docker/ci/test/image.sh`, before `finish`, add:

```bash
expect_status 0 "FA_DB_PREFIX is in the environment" docker exec "$c" sh -c 'test "$FA_DB_PREFIX" = 0_'
expect_status 0 "Apache creates group-writable files" docker exec "$c" sh -c '. /etc/apache2/envvars && test "$(umask)" = 0002'
expect_status 0 "the mail catcher's directory is not sticky" docker exec "$c" sh -c 'test "$(stat -c %a /var/mail-catcher)" = 777'
expect_status 0 "errors are logged, not displayed, and notices are off" docker exec "$c" php -r \
    'exit((ini_get("display_errors") == "" || ini_get("display_errors") == "0") && !(error_reporting() & E_NOTICE) && ini_get("memory_limit") === "512M" ? 0 : 1);'
```

In `docker/ci/test/attach.sh`, replace everything from the line `expect_status 0 "grants the admin role every area" docker exec "$c" fa-ci-grant` up to (not including) `finish` with:

```bash
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
expect_status 0 "granting again adds nothing" docker exec "$c" fa-ci-grant --role 2 --module ci_alpha
expect_contains "zero the second time" "granted 0 areas of ci_alpha to role 2" "$OUT"
expect_status 2 "a malformed grant is refused" docker exec "$c" fa-ci-grant --role two --module ci_alpha
```

In `docker/ci/test/driver.sh`, before the line `expect_status 0 "no container is left behind"`, add:

```bash
expect_status 0 "--dataset demo loads FA's demo data before activation" \
    "$d" --dataset demo "$fx/ci_alpha" -- \
    'mariadb -h localhost -u fa -pfa -N fa_test -e "SELECT user_id FROM 0_users WHERE user_id IN (\"admin\", \"test\") ORDER BY user_id; SELECT marker FROM 0_ci_alpha; SELECT COUNT(*) FROM 0_debtors_master; SELECT IF(COUNT(*) > 0, \"today-covered\", \"no-year\") FROM 0_fiscal_year WHERE CURDATE() BETWEEN \`begin\` AND \`end\`"'
expect_contains "the demo admin" "admin" "$OUT"
expect_contains "and the package's test login" "test" "$OUT"
expect_contains "ci_alpha activated on top" "alpha-installed" "$OUT"
expect_contains "a fiscal year covers today" "today-covered" "$OUT"
expect_status 1 "an unknown dataset is refused" "$d" --dataset nope "$fx/ci_alpha" -- true
expect_contains "naming the choices" "test or demo" "$OUT"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `docker/ci/build-image.sh cp 7.4 fa-ci:local-cp-7.4 && FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/run.sh`
Expected: image.sh fails its four new checks; attach.sh fails from "prints ci_alpha's extension id" on; driver.sh fails the dataset cases (`unknown option: --dataset`). The line `FAILED: image.sh attach.sh driver.sh`.

- [ ] **Step 3: Implement the image changes**

`docker/ci/image/fa-ci-dataset`:

```sh
#!/bin/sh
# fa-ci-dataset <test|demo>: replace the fa_test database with a dataset.
#
#   test  the fixture the image was seeded with (modules/tests/data/fa_test.sql.gz)
#   demo  FrontAccounting's own sql/en_US-demo.sql: customers, items, orders.
#         Its fiscal years end in the past, so years are appended until one
#         covers today, and a test/test login (role 2) is added for the
#         package's helpers. The demo admin/password stays as it is.
#
# Run as root, before modules are activated, so their update SQL runs on it.
set -eu
[ "$#" -eq 1 ] || { echo "usage: fa-ci-dataset <test|demo>" >&2; exit 2; }
db="${FA_DB_NAME:-fa_test}"

case "$1" in
    test) load() { gunzip -c /usr/local/share/fa-ci/fa_test.sql.gz; } ;;
    demo) load() { cat "${FA_ROOT:-/var/www/html}/sql/en_US-demo.sql"; } ;;
    *) echo "fa-ci-dataset: the dataset is test or demo, not '$1'" >&2; exit 2 ;;
esac

mariadb -e "DROP DATABASE IF EXISTS \`$db\`; CREATE DATABASE \`$db\`;"
load | mariadb "$db"

mariadb "$db" <<'SQL'
INSERT INTO `0_users` (`user_id`, `password`, `real_name`, `role_id`, `email`, `language`)
SELECT 'test', MD5('test'), 'FA CI', 2, 'test@example.com', 'C'
FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM `0_users` WHERE `user_id` = 'test');
SQL

added=0
while [ "$(mariadb -N "$db" -e "SELECT COUNT(*) FROM \`0_fiscal_year\` WHERE CURDATE() BETWEEN \`begin\` AND \`end\`")" = 0 ]; do
    [ "$added" -lt 30 ] || { echo "fa-ci-dataset: no fiscal year reaches today after $added" >&2; exit 1; }
    mariadb "$db" -e "INSERT INTO \`0_fiscal_year\` (\`begin\`, \`end\`, \`closed\`)
        SELECT MAX(\`end\`) + INTERVAL 1 DAY, MAX(\`end\`) + INTERVAL 1 YEAR, 0 FROM \`0_fiscal_year\`
        HAVING MAX(\`end\`) IS NOT NULL"
    added=$((added + 1))
done
if [ "$added" -gt 0 ]; then
    mariadb "$db" -e "UPDATE \`0_sys_prefs\` SET \`value\` =
        (SELECT id FROM \`0_fiscal_year\` WHERE CURDATE() BETWEEN \`begin\` AND \`end\` LIMIT 1)
        WHERE \`name\` = 'f_year'"
fi
if [ "$added" -gt 0 ]; then
    echo "dataset $1 loaded ($added fiscal year(s) added to reach today)"
else
    echo "dataset $1 loaded"
fi
```

`docker/ci/image/fa-ci-ext-id`:

```sh
#!/bin/sh
# fa-ci-ext-id <module>: the extension id FrontAccounting gave a module (company
# 0's list). Ids follow activation order, so anything that encodes a module's
# security codes -- section (id << 16) | (100 << 8), first area section | 100 --
# has to be worked out from this. Exits 1 if the module is not registered.
set -eu
[ "$#" -eq 1 ] || { echo "usage: fa-ci-ext-id <module>" >&2; exit 2; }
php -r '
    $installed_extensions = array();
    include $argv[1];
    foreach ($installed_extensions as $id => $e)
        if ($e["package"] === $argv[2]) { echo $id, "\n"; exit(0); }
    fwrite(STDERR, "fa-ci-ext-id: " . $argv[2] . " is not registered\n");
    exit(1);' "${FA_ROOT:-/var/www/html}/company/0/installed_extensions.php" "$1"
```

`docker/ci/image/fa-ci-grant` (whole file):

```sh
#!/bin/sh
# fa-ci-grant
#     Every security section and area FrontAccounting knows, extension ones
#     included, to a role of its own, "FA CI", which the test user is moved to.
#     Role 2 is left as the dataset has it: plugins' own fixtures copy it and
#     assert what it lacks.
# fa-ci-grant --role <id> --module <name>
#     One module's sections and areas, added to role <id> (idempotent), e.g.
#     for a dataset user a plugin's tests sign in as.
#
# Codes are worked out inside a FrontAccounting request (/fa-ci/grant.php),
# since extension codes depend on the module's extension id.
set -eu
url="${FA_URL:-http://localhost}"
query=''
if [ "$#" -gt 0 ]; then
    if [ "$#" -ne 4 ] || [ "$1" != --role ] || [ "$3" != --module ]; then
        echo "usage: fa-ci-grant [--role <id> --module <name>]" >&2
        exit 2
    fi
    case "$2" in ''|*[!0-9]*) echo "fa-ci-grant: --role takes a role id" >&2; exit 2 ;; esac
    case "$4" in ''|*[!A-Za-z0-9_]*) echo "fa-ci-grant: --module takes a module name" >&2; exit 2 ;; esac
    query="?role=$2&module=$4"
fi
jar="$(mktemp)"
out="$(mktemp)"
trap 'rm -f "$jar" "$out"' EXIT
fa-ci-login "$jar"
curl -fsS -b "$jar" -o "$out" "$url/fa-ci/grant.php$query"
grep '^granted ' "$out" || {
    echo "fa-ci-grant: unexpected response from fa-ci/grant.php:" >&2
    head -c 2000 "$out" >&2
    exit 1
}
```

`docker/ci/image/grant.php` (whole file):

```php
<?php
/*
	CI image only (docker/ci), not part of FrontAccounting. Requested by
	fa-ci-grant. Extension security codes depend on each module's extension id
	and are only worked out during a request (add_access_extensions()), which is
	why this runs as a page.

	  (no query)            every section and area, to role "FA CI", which the
	                        test user is moved to; role 2 is left alone
	  ?role=N&module=NAME   that module's sections and areas, added to role N
*/
$page_security = 'SA_SECROLES';
$path_to_root = '..';
include_once($path_to_root . '/includes/session.inc');
include_once($path_to_root . '/admin/db/security_db.inc');

add_access_extensions();
header('Content-Type: text/plain');

if (isset($_GET['module'])) {
	$module = $_GET['module'];
	$role_id = (int) $_GET['role'];
	$ext_id = null;
	foreach ($installed_extensions as $id => $ext)
		if ($ext['package'] === $module)
			$ext_id = $id;
	$role = get_security_role($role_id);
	if ($ext_id === null || !$role) {
		http_response_code(404);
		echo $ext_id === null ? "no module $module\n" : "no role $role_id\n";
		exit;
	}
	$sections = array_filter($role['sections'], 'strlen');
	$areas = array_filter($role['areas'], 'strlen');
	$added = 0;
	foreach (array_keys($security_sections) as $code)
		if (($code >> 16) == $ext_id && !in_array((string) $code, $sections, true))
			$sections[] = (string) $code;
	foreach ($security_areas as $area)
		if (($area[0] >> 16) == $ext_id && !in_array((string) $area[0], $areas, true)) {
			$areas[] = (string) $area[0];
			$added++;
		}
	update_security_role($role_id, $role['role'], $role['description'], $sections, $areas);
	echo "granted $added areas of $module to role $role_id\n";
	exit;
}

$sections = array_keys($security_sections);
$areas = array();
foreach ($security_areas as $area)
	$areas[] = $area[0];
$row = db_fetch(db_query("SELECT id FROM " . TB_PREF . "security_roles WHERE role = 'FA CI'"));
if ($row) {
	$role_id = (int) $row['id'];
	update_security_role($role_id, 'FA CI', 'Every area (docker/ci)', $sections, $areas);
} else {
	add_security_role('FA CI', 'Every area (docker/ci)', $sections, $areas);
	$role_id = (int) db_insert_id();
}
db_query("UPDATE " . TB_PREF . "users SET role_id = $role_id WHERE user_id = 'test'");
echo 'granted ', count($areas), ' areas in ', count($sections), " sections to role FA CI\n";
```

`docker/ci/image/php.ini`: replace the lines `memory_limit = 256M`, `display_errors = On`, `display_startup_errors = On` and `error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT` with:

```ini
memory_limit = 512M
display_errors = Off
display_startup_errors = Off
log_errors = On
; As the plugins' own stacks had it; FrontAccounting logs its own to tmp/errors.log.
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT & ~E_NOTICE
```

`docker/ci/image/apache-fa-ci.conf`: before `ServerName localhost`, add:

```apache
# Bearer tokens (graphql): mod_php does not always see the Authorization header.
SetEnvIf Authorization "(.+)" HTTP_AUTHORIZATION=$1
```

`docker/ci/Dockerfile`:
- Change `install -d -m 1777 /var/mail-catcher` to `install -d -m 0777 /var/mail-catcher`. Tests delete what Apache writes there, and the sticky bit would stop them.
- After the line `RUN a2enmod rewrite && a2enconf fa-ci`, add:

```dockerfile
# Files Apache creates (tmp/faillog.php, tmp/errors.log) stay writable by the
# test uid, which runs with group www-data.
RUN echo 'umask 002' >> /etc/apache2/envvars
```

- In the `ENV PHP_VERSION=...` block, add `FA_DB_PREFIX=0_ \` after `FA_DB_NAME=fa_test \`.

Run: `chmod +x docker/ci/image/fa-ci-dataset docker/ci/image/fa-ci-ext-id`, then after `git add`: `git update-index --chmod=+x docker/ci/image/fa-ci-dataset docker/ci/image/fa-ci-ext-id`.

- [ ] **Step 4: The driver's `--dataset`**

In `docker/ci/plugin-test.sh`:
- In the header's option list, after the `--php` line, add:

```bash
#   --dataset test|demo    the database the run starts from (default: test,
#                          the image's fa_test; demo is FrontAccounting's demo
#                          company, loaded before activation)
```

- After `PHP=7.4`, add `DATASET=test`.
- In the option loop, after `--php) PHP="$2"; shift 2 ;;`, add `--dataset) DATASET="$2"; shift 2 ;;`.
- After the line `[ -n "$TEST" ] || die "no test command"`, add:

```bash
case "$DATASET" in test|demo) ;; *) die "--dataset is test or demo, not '$DATASET'" ;; esac
```

- After `ci_boot "$CONTAINER" "$IMAGE" "${run_args[@]}"`, add:

```bash
if [ "$DATASET" != test ]; then
    log "dataset: $DATASET"
    docker exec "$CONTAINER" fa-ci-dataset "$DATASET"
fi
```

In `.github/workflows/plugin-test.yml`:
- Add an input after `php`:

```yaml
      dataset:
        description: The database the run starts from, test (the image's fa_test) or demo (FrontAccounting's demo company)
        type: string
        default: test
```

- In the Test step's `env:`, add `DATASET: ${{ inputs.dataset }}`. Change `args=(--fa "$FA" --php "$PHP")` to `args=(--fa "$FA" --php "$PHP" --dataset "$DATASET")`.

- [ ] **Step 5: Document**

In `docker/ci/README.md`:
- Add `dataset` to the inputs sentence of "In a plugin's CI": `` `dataset`: `test` (the image's `fa_test`, the default) or `demo` (FrontAccounting's demo company, with fiscal years reaching today) ``.
- Add `--dataset` to the "Locally" options.
- In "What a run does", add a step after booting: "With `--dataset demo`, replaces the database with FrontAccounting's demo company and adds the `test`/`test` login."
- In step 3, replace "Then gives the admin role every area." with "Then gives the `test` user a role of its own, `FA CI`, holding every area; role 2 stays as the dataset has it."
- At the end of the environment list, add a paragraph:

```markdown
Helpers for a plugin's own setup: `fa-ci-ext-id <module>` prints a module's
extension id, which follows activation order, so derive security codes from
it: section `(id << 16) | (100 << 8)`, first area `section | 100`.
`fa-ci-grant --role <id> --module <name>` adds a module's sections and areas
to a role, e.g. role 2 for a dataset user your tests sign in as.
```

- [ ] **Step 6: Run the tests**

Run: `docker/ci/build-image.sh cp 7.4 fa-ci:local-cp-7.4 && FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/run.sh`
Expected: every section ends `0 failed`, then `all passed`.

Run: `docker run --rm -v "$PWD":/mnt -w /mnt koalaman/shellcheck:stable -x docker/ci/plugin-test.sh docker/ci/image/fa-ci-dataset docker/ci/image/fa-ci-ext-id docker/ci/image/fa-ci-grant docker/ci/test/*.sh && php -l docker/ci/image/grant.php && docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:latest -color`
Expected: shellcheck and actionlint print nothing; `No syntax errors detected`.

Run: `docker/ci/build-image.sh upstream 7.4 fa-ci:local-upstream-7.4 && FA_CI_IMAGE=fa-ci:local-upstream-7.4 docker/ci/test/run.sh`
Expected: `all passed`.

- [ ] **Step 7: Commit**

```bash
git add docker/ci .github/workflows/plugin-test.yml
git update-index --chmod=+x docker/ci/image/fa-ci-dataset docker/ci/image/fa-ci-ext-id
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "ci: Datasets, per-module grants and extension ids for plugins

--dataset demo starts a run from FrontAccounting's demo company. fa-ci-grant
now gives the test user a role of its own and leaves role 2 as the dataset
has it; --role/--module grants one module's areas to a role. fa-ci-ext-id
prints a module's extension id, which follows activation order. The image
matches the plugins' old stacks: FA_DB_PREFIX, Apache umask 002, errors
logged not shown, 512M, a non-sticky mail directory, Authorization passed on.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: graphql runs its CI in the package

**Files (graphql worktree):**
- Create: `tools/ci.sh`
- Create: `tests/data/seed.sh`
- Modify: `tests/Http/StackTest.php` (`testSeedUsersExist`, plus a new private method)
- Modify: `tests/data/seed.sql` (header comment only)
- Modify: `.github/workflows/ci.yml` (whole file)
- Modify: `README.md` (testing section), `docker/README.md` (one paragraph at the top)

**Interfaces:**
- Consumes (Task 1): `--dataset demo`, `fa-ci-ext-id`, `FA_DB_PREFIX`, `FA_URL`, the mail catcher, a group-writable FA tree, and the local image `fa-ci:local-cp-7.4` (plus `fa-ci:local-upstream-7.4`).
- Produces:
  - `tests/data/seed.sh`: loads `seed.sql` with SS_GRAPHQL and SA_GRAPHQL worked out from graphql's extension id (Task 3 calls it as `sh ../graphql/tests/data/seed.sh`);
  - `tools/ci.sh`.

- [ ] **Step 1: Make StackTest derive SA_GRAPHQL (the failing test)**

In `tests/Http/StackTest.php`, in `testSeedUsersExist()`, replace the two lines

```php
        $this->assertContains('91236', explode(';', $rows['apitest']));
        $this->assertNotContains('91236', explode(';', $rows['noapi']));
```

with

```php
        $area = (string) $this->graphqlArea();
        $this->assertContains($area, explode(';', $rows['apitest']));
        $this->assertNotContains($area, explode(';', $rows['noapi']));
```

and add this method to the class, next to `pdo()`:

```php
    /**
     * SA_GRAPHQL as FrontAccounting numbers it for graphql's extension id:
     * (id << 16) | (100 << 8) | 100. docker/fa-graphql registers graphql as
     * extension 1 (91236); the FrontAccounting CI image numbers modules in the
     * order they are activated.
     */
    private function graphqlArea(): int
    {
        $installed_extensions = [];
        include dirname($this->moduleDir(), 2) . '/company/0/installed_extensions.php';
        foreach ($installed_extensions as $id => $ext) {
            if ($ext['package'] === 'graphql') {
                return ($id << 16) | (100 << 8) | 100;
            }
        }
        throw new \RuntimeException('graphql is not registered in company/0/installed_extensions.php');
    }
```

- [ ] **Step 2: Write `seed.sh` and `tools/ci.sh`**

`tests/data/seed.sh`:

```sh
#!/bin/sh
# Load seed.sql into the FrontAccounting CI image's database, with SS_GRAPHQL
# and SA_GRAPHQL worked out from the extension id graphql has there. seed.sql
# is written for extension 1 (91136 / 91236), as docker/fa-graphql registers
# it; the CI image numbers modules in the order they are activated.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
ext="$(fa-ci-ext-id graphql)"
section=$(( (ext << 16) | (100 << 8) ))
area=$(( section | 100 ))
sed -e "s/91136/$section/g" -e "s/91236/$area/g" "$here/seed.sql" \
    | mariadb -h "$FA_DB_HOST" -u "$FA_DB_USER" -p"$FA_DB_PASSWORD" "$FA_DB_NAME"
echo "seeded: graphql is extension $ext (SS_GRAPHQL $section, SA_GRAPHQL $area)"
```

`tools/ci.sh`:

```sh
#!/bin/sh
# graphql's CI. Runs inside the FrontAccounting CI image (docker/ci in
# cambell-prince/frontaccounting), from this module's directory, on the demo
# dataset, with sgw_sales activated alongside. It checks what docker/fa-graphql
# ci checks against its own stack: lint, analyze, the suites, sgw_sales'
# GraphQL suite, and the default-company report.
set -eu
: "${FA_ROOT:?run this inside the FrontAccounting CI image (docker/ci/plugin-test.sh)}"
export FA_DB_PREFIX="${FA_DB_PREFIX:-0_}"
export FA_GRAPHQL_URL="${FA_URL%/}/modules/graphql/"

echo "==> lint"
composer run lint
composer run cs:check

echo "==> analyze"
composer run analyze

echo "==> config and seed"
if [ ! -f config_graphql.php ]; then
    secret="$(php -r 'echo bin2hex(random_bytes(24));')"
    printf "<?php\n\n/* Written by tools/ci.sh for the CI image. Not for production:\n\tsee config_graphql.example.php. */\n\nreturn array(\n    'secret' => '%s',\n    'allow_insecure_login' => true,\n    'debug' => true,\n);\n" \
        "$secret" > config_graphql.php
fi
sh tests/data/seed.sh

echo "==> phpunit"
composer run test

if [ -f ../sgw_sales/phpunit-graphql.xml ]; then
    echo "==> sgw_sales' GraphQL suite"
    php vendor/bin/phpunit -c ../sgw_sales/phpunit-graphql.xml --fail-on-skipped
fi

# ReportDefaultCompanyTest needs a company other than 0 to be the default.
# config_db.php and company/1 are put back whatever happens.
cfg="$FA_ROOT/config_db.php"
c1="$FA_ROOT/company/1"
mark=second-company-test
second_company_remove() {
    if grep -q "$mark" "$cfg"; then
        mv "$cfg.before-second-company" "$cfg"
    else
        rm -f "$cfg.before-second-company"
    fi
    if [ -f "$c1/.$mark" ]; then rm -rf "$c1"; fi
    rm -rf "$c1.$mark"
}
second_company_add() {
    if [ -d "$c1" ] && [ ! -f "$c1/.$mark" ]; then
        echo "company/1 exists and was not made by tools/ci.sh: refusing" >&2
        exit 3
    fi
    cp "$cfg" "$cfg.before-second-company"
    sed -i 's/^\$def_coy = [0-9]*;/$def_coy = 1;/' "$cfg"
    printf '%s\n' "/* $mark: tools/ci.sh */" \
        '$db_connections[1] = array_merge($db_connections[0], array("name" => "Second (test)"));' >> "$cfg"
    rm -rf "$c1.$mark"
    cp -R "$FA_ROOT/company/0" "$c1.$mark"
    touch "$c1.$mark/.$mark"
    mv "$c1.$mark" "$c1"
    php -r '
        $installed_extensions = array();
        include $argv[1];
        foreach ($installed_extensions as $k => $e)
            if ($e["package"] === "graphql") $installed_extensions[$k]["active"] = false;
        file_put_contents($argv[1], "<?php\n\n\$installed_extensions = " . var_export($installed_extensions, true) . ";\n");' \
        "$c1/installed_extensions.php"
}

echo "==> as the default company of two"
trap second_company_remove EXIT
second_company_remove
second_company_add
composer run test -- --fail-on-skipped --filter ReportDefaultCompanyTest
trap - EXIT
second_company_remove
echo "==> all checks passed"
```

In `tests/data/seed.sql`, change the header's third paragraph (`-- 91136 / 91236 are SS_GRAPHQL / SA_GRAPHQL ...` through `... (includes/access_levels.inc).`) to end with an added line:

```sql
-- In the FrontAccounting CI image, tests/data/seed.sh rewrites both codes for
-- the extension id graphql has there.
```

Run: `chmod +x tools/ci.sh tests/data/seed.sh`.

- [ ] **Step 3: Run it on the cp image**

From the graphql worktree:

```bash
export COMPOSER_CACHE_DIR="$HOME/.cache/composer"
FA_CI_IMAGE=fa-ci:local-cp-7.4 "$FA_CI/plugin-test.sh" --dataset demo \
  --setup 'composer install --no-interaction --no-progress' \
  --with sgw_sales=https://github.com/saygoweb/frontaccounting-module-sgw_sales.git@master \
  . -- sh tools/ci.sh 2>&1 | tee "$TMPDIR/graphql-cp.log"; echo "exit=$?"
```

(Use a scratch dir named for what it is, e.g. `TMP_A=$(mktemp -d)`, if `$TMPDIR` is unset.)

Expected:
- `seeded: graphql is extension 2 (SS_GRAPHQL 156672, SA_GRAPHQL 156772)`.
- The main phpunit run ends `OK, but incomplete, skipped, or risky tests! Tests: 966, ... Skipped: 1.` The skip is `ReportDefaultCompanyTest`.
- sgw_sales' GraphQL suite: `OK (66 tests, ...)`.
- The default-company run: `OK (1 test, ...)`.
- `==> all checks passed`, `exit=0`.

If a count is lower, find which tests skipped (`composer run test -- --display-skipped`, or `--testdox` for the run's skip list) and fix the environment or `tools/ci.sh`. The inventory's list of data- and environment-dependent skips: `CustomerServiceTest:116`, `BranchServiceTest:252`, `CustomerBalanceTest:64`, `MachineTokenFlowTest:35`, `PanelFlowTest:57`, `RecurringGenerationFlowTest:70`, `SalesOrderTypeTest:185`, the mail-catcher tests, `OutputCaptureServerTest:25,40`. Record what you changed and why in the report. If the cause is in the package (Task 1), stop and report NEEDS_CONTEXT with the evidence rather than working around it here.

- [ ] **Step 4: Run it on the upstream image**

Same command with `FA_CI_IMAGE=fa-ci:local-upstream-7.4`.
Expected: main run `Tests: 966 ... Skipped: 2` (adds `CompatDriftTest`), then 66 and 1 as before, `exit=0`.

- [ ] **Step 5: Check the old dev stack still passes StackTest**

If the stack from `docker/fa-graphql` is up (`docker ps` shows `fa-graphql-graphql-app-1`), run `docker/fa-graphql test --filter StackTest`.
Expected: OK, with graphql as extension 1 there. If it isn't running, say so in the report and skip; don't start or rebuild it.

- [ ] **Step 6: Check the second-company step restores on failure**

Run the Step 3 command, replacing `sh tools/ci.sh` with:

```sh
sh -c 'sed -i "s/^composer run test -- --fail-on-skipped --filter ReportDefaultCompanyTest$/false/" tools/ci.sh; cp "$FA_ROOT/config_db.php" /tmp/cfg.before; sh tools/ci.sh; rc=$?; git checkout -- tools/ci.sh; cmp "$FA_ROOT/config_db.php" /tmp/cfg.before && test ! -e "$FA_ROOT/company/1" && echo restored; exit 0'
```

Expected: the output ends with `restored`. `git status` shows `tools/ci.sh` unmodified afterwards.

- [ ] **Step 7: The workflow and docs**

`.github/workflows/ci.yml` (whole file):

```yaml
name: CI

# Runs tools/ci.sh in the FrontAccounting CI image (cambell-prince/frontaccounting
# docker/ci), on FrontAccounting's demo company, with sgw_sales activated
# alongside. docker/fa-graphql stays the development stack.

on:
  push:
    branches:
      - main
      - 'feature/**'
      - 'fix/**'
      - 'ci/**'
  pull_request:
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        fa: [cp, upstream]
        php: ['7.4', '8.3']
    uses: cambell-prince/frontaccounting/.github/workflows/plugin-test.yml@master-cp
    with:
      fa: ${{ matrix.fa }}
      php: ${{ matrix.php }}
      dataset: demo
      setup: composer install --no-interaction --no-progress
      with: |
        sgw_sales=https://github.com/saygoweb/frontaccounting-module-sgw_sales.git@master
      test: sh tools/ci.sh
```

In `README.md`, replace the section that describes running the tests or CI through `docker/fa-graphql ci` or `test` (find it with `grep -n 'fa-graphql' README.md`) with:

```markdown
## Tests

CI runs `tools/ci.sh` in the FrontAccounting CI image
([cambell-prince/frontaccounting `docker/ci`](https://github.com/cambell-prince/frontaccounting/tree/master-cp/docker/ci)),
on FrontAccounting's demo company, with sgw_sales activated alongside. With
that repository checked out beside this one, the same run locally is:

    ../frontaccounting/docker/ci/plugin-test.sh --dataset demo \
      --setup 'composer install --no-interaction --no-progress' \
      --with sgw_sales=https://github.com/saygoweb/frontaccounting-module-sgw_sales.git@master \
      . -- sh tools/ci.sh

`docker/fa-graphql` remains the development stack: dev fixtures, Voyager, the
mail listing, anorm-graphql co-development (see `docker/README.md`).
```

In `docker/README.md`, after the first heading, add:

```markdown
CI no longer uses this stack: it runs `tools/ci.sh` in the FrontAccounting CI
image (see the README's Tests section). This stack is for development.
```

Run: `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:latest -color .github/workflows/ci.yml`
Expected: nothing, or only a note that it can't fetch the remote reusable workflow.

- [ ] **Step 8: Commit**

```bash
git add tools/ci.sh tests/data/seed.sh tests/data/seed.sql tests/Http/StackTest.php .github/workflows/ci.yml README.md docker/README.md
git update-index --chmod=+x tools/ci.sh tests/data/seed.sh
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "ci: Run CI in the FrontAccounting CI image

tools/ci.sh runs lint, analyze, the suites, sgw_sales' GraphQL suite and the
default-company report inside the shared image, on the demo company with
sgw_sales alongside. SA_GRAPHQL follows graphql's extension id (seed.sh,
StackTest), which the image assigns in activation order. docker/fa-graphql
stays as the development stack.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: sgw_sales runs its CI in the package

**Files (sgw_sales worktree):**
- Create: `tools/ci.sh`, `tools/ci-graphql.sh`
- Modify: `.github/workflows/ci.yml` (whole file)
- Delete: `docker/` (whole directory)
- Modify: `README.md` (testing section), and any other file that references `docker/fa-sgw-sales` (find with `git grep -n 'fa-sgw-sales\|docker/'`)

**Interfaces:**
- Consumes (Task 1): `--dataset demo`, `fa-ci-grant --role 2 --module sgw_sales`, `FA_DB_PREFIX`, `FA_URL`, and the local image `fa-ci:local-cp-7.4`. (Task 2): `../graphql/tests/data/seed.sh` when present. Before graphql's change is merged, fall back to `seed.sql`, which is right because graphql is extension 1 in this job.
- Produces: sgw_sales' CI.

- [ ] **Step 1: Write the scripts**

`tools/ci.sh`:

```sh
#!/bin/sh
# sgw_sales' CI. Runs inside the FrontAccounting CI image (docker/ci in
# cambell-prince/frontaccounting), from this module's directory, on the demo
# dataset, after the module has been activated.
set -eu
: "${FA_ROOT:?run this inside the FrontAccounting CI image (docker/ci/plugin-test.sh)}"
export FA_DB_PREFIX="${FA_DB_PREFIX:-0_}"

# The Http tests sign in as the demo admin (role 2) and expect the module's
# menu: give role 2 this module's areas, as docker/fa-sgw-sales did.
fa-ci-grant --role 2 --module sgw_sales

echo "==> lint"
composer run lint
echo "==> phpcs (advisory, as before)"
composer run cs:check -- --report=summary || true

echo "==> analyze"
composer run analyze

echo "==> phpunit"
composer run test
```

`tools/ci-graphql.sh`:

```sh
#!/bin/sh
# sgw_sales' GraphQL-extension suite (phpunit-graphql.xml), run with graphql's
# PHPUnit from ../graphql, as `docker/fa-graphql test-extension sgw_sales`
# did. Inside the FrontAccounting CI image, with graphql activated first (so
# graphql is extension 1) and graphql's dev dependencies installed by the
# workflow's setup.
set -eu
: "${FA_ROOT:?run this inside the FrontAccounting CI image (docker/ci/plugin-test.sh)}"
export FA_DB_PREFIX="${FA_DB_PREFIX:-0_}"
export FA_GRAPHQL_URL="${FA_URL%/}/modules/graphql/"

[ -f ../graphql/vendor/bin/phpunit ] || {
    echo "graphql's dev dependencies are missing: run composer install in ../graphql (the workflow's setup does)" >&2
    exit 1
}
fa-ci-grant --role 2 --module sgw_sales

echo "==> graphql's seed"
if [ -f ../graphql/tests/data/seed.sh ]; then
    sh ../graphql/tests/data/seed.sh
else
    mariadb -h "$FA_DB_HOST" -u "$FA_DB_USER" -p"$FA_DB_PASSWORD" "$FA_DB_NAME" < ../graphql/tests/data/seed.sql
fi

echo "==> phpunit-graphql.xml"
cd ../graphql
php vendor/bin/phpunit -c ../sgw_sales/phpunit-graphql.xml --fail-on-skipped
```

Run: `chmod +x tools/ci.sh tools/ci-graphql.sh`

- [ ] **Step 2: Run the main suite**

From the sgw_sales worktree:

```bash
export COMPOSER_CACHE_DIR="$HOME/.cache/composer"
FA_CI_IMAGE=fa-ci:local-cp-7.4 "$FA_CI/plugin-test.sh" --dataset demo \
  --setup 'composer install --no-interaction --no-progress' \
  . -- sh tools/ci.sh; echo "exit=$?"
```

Expected: `activated sgw_sales`, `granted 3 areas of sgw_sales to role 2`, lint OK, phpstan `[OK] No errors`. PHPUnit `Tests: 66, ... Skipped: 1.` The skip is `ServiceWithoutAPageTest::testAnOrderTheStockCannotCoverIsRefusedAndNothingIsWritten`, as before. `exit=0`.

If more tests skip, list them (`--display-skipped`) and fix the cause, e.g. environment variables, grants or dataset. If the cause is in the package, stop and report NEEDS_CONTEXT with evidence.

- [ ] **Step 3: Run the GraphQL-extension suite**

```bash
FA_CI_IMAGE=fa-ci:local-cp-7.4 "$FA_CI/plugin-test.sh" --dataset demo \
  --setup 'composer install --no-interaction --no-progress && (cd ../graphql && composer install --no-interaction --no-progress)' \
  --with graphql=https://github.com/saygoweb/frontaccounting-module-graphql.git@main \
  . -- sh tools/ci-graphql.sh; echo "exit=$?"
```

Expected: `activated graphql` then `activated sgw_sales`, graphql's seed loaded, `OK (66 tests, ...)`, `exit=0`. With `@main`, `seed.sh` doesn't exist yet, so the `seed.sql` fallback runs. Also run it once with `--with graphql=/home/cambell/src/sgw/frontaccounting/.claude/worktrees/graphql-ci` if Task 2 has committed its `seed.sh` there. First run `composer install --no-interaction --no-progress` in that worktree if its `vendor/` is missing. Expected: `seeded: graphql is extension 1`, then 66 OK.

- [ ] **Step 4: The workflow**

`.github/workflows/ci.yml` (whole file):

```yaml
name: CI

# Runs in the FrontAccounting CI image (cambell-prince/frontaccounting
# docker/ci) on FrontAccounting's demo company: the module's own suites, and
# its GraphQL-extension suite with graphql activated alongside.

on:
  push:
    branches:
      - master
      - 'feature/**'
      - 'fix/**'
      - 'bug/**'
      - 'issue/**'
      - 'ci/**'
  pull_request:
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        php: ['7.4', '8.3']
    uses: cambell-prince/frontaccounting/.github/workflows/plugin-test.yml@master-cp
    with:
      fa: cp
      php: ${{ matrix.php }}
      dataset: demo
      setup: composer install --no-interaction --no-progress
      test: sh tools/ci.sh

  graphql-extension:
    strategy:
      fail-fast: false
      matrix:
        fa: [cp, upstream]
        php: ['7.4', '8.3']
    uses: cambell-prince/frontaccounting/.github/workflows/plugin-test.yml@master-cp
    with:
      fa: ${{ matrix.fa }}
      php: ${{ matrix.php }}
      dataset: demo
      setup: composer install --no-interaction --no-progress && (cd ../graphql && composer install --no-interaction --no-progress)
      with: |
        graphql=https://github.com/saygoweb/frontaccounting-module-graphql.git@main
      test: sh tools/ci-graphql.sh
```

- [ ] **Step 5: Delete the old stack and its references**

Run: `git rm -r -q docker`, then `git grep -n 'fa-sgw-sales\|docker/'` and update each hit that describes the old stack.
- In `README.md`, replace the testing section with the same shape as graphql's: CI runs `tools/ci.sh` and `tools/ci-graphql.sh` in the image, followed by the two local commands from Steps 2 and 3, with `../frontaccounting/docker/ci/plugin-test.sh` as the path.
- `upload-exclude*.txt` lines naming `docker` can stay; they're harmless.

Run: `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:latest -color .github/workflows/ci.yml`
Expected: nothing, or only the remote-workflow note.

- [ ] **Step 6: Commit**

```bash
git add -A tools .github/workflows/ci.yml README.md
git update-index --chmod=+x tools/ci.sh tools/ci-graphql.sh
git status --short   # docker/ deleted, the two scripts added, docs changed
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "ci: Run CI in the FrontAccounting CI image

tools/ci.sh (lint, analyze, phpunit) and tools/ci-graphql.sh (the GraphQL
suite, with graphql activated first) run in the shared image on the demo
company; role 2 gets the module's areas through fa-ci-grant. The docker/
test stack is gone.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: api runs its CI in the package

**Files (api worktree):**
- Create: `tools/ci.sh`
- Modify: `tests/TestEnvironment.php:18` (base URI)
- Modify: `.github/workflows/ci.yml` (whole file)
- Delete: `docker/` (whole directory)
- Modify: `README.md` (testing section), and other references to `docker/fa-api` (`git grep -n 'fa-api\|docker/'`)

**Interfaces:**
- Consumes (Task 1): `FA_URL`, the local images `fa-ci:local-cp-7.4` and `fa-ci:local-upstream-7.4`, and the driver's `--name api --no-activate`.
- Produces: api's CI.

- [ ] **Step 1: Point the tests at `FA_URL` (the failing run)**

First, the failing run from the api worktree:

```bash
export COMPOSER_CACHE_DIR="$HOME/.cache/composer"
FA_CI_IMAGE=fa-ci:local-upstream-7.4 "$FA_CI/plugin-test.sh" --name api --no-activate \
  --setup 'composer install --no-interaction --no-progress' \
  . -- 'composer run test'; echo "exit=$?"
```

Expected: failures with Guzzle `ConnectException` / connection refused to `localhost:8000`, and a non-zero exit.

Then in `tests/TestEnvironment.php`, change `'base_uri' => 'http://localhost:8000'` to:

```php
            'base_uri' => getenv('FA_URL') ?: 'http://localhost:8000'
```

- [ ] **Step 2: Write `tools/ci.sh`**

```sh
#!/bin/sh
# api's CI. Runs inside the FrontAccounting CI image (docker/ci in
# cambell-prince/frontaccounting) with this checkout at modules/api; api is
# not a FrontAccounting extension, so the run is --name api --no-activate.
set -eu
: "${FA_URL:?run this inside the FrontAccounting CI image (docker/ci/plugin-test.sh)}"

echo "==> lint"
composer run lint
echo "==> phpcs (advisory, as before)"
composer run cs:check -- --report=summary || true

echo "==> analyze"
composer run analyze

echo "==> phpunit"
curl -fsS -o /dev/null "$FA_URL/modules/api/category/" -H 'X-COMPANY: 0' -H 'X-USER: test' -H 'X-PASSWORD: test' \
    || echo "(modules/api/category/ did not answer 2xx; the suite will say why)"
composer run test
```

Run: `chmod +x tools/ci.sh`

- [ ] **Step 3: Run it on both flavours**

```bash
for fa in upstream cp; do
  FA_CI_IMAGE=fa-ci:local-$fa-7.4 "$FA_CI/plugin-test.sh" --name api --no-activate \
    --setup 'composer install --no-interaction --no-progress' \
    . -- sh tools/ci.sh; echo "$fa exit=$?"
done
```

Expected, for each: lint OK, phpstan OK, `OK (31 tests, 362 assertions)`, `exit=0`.
- If **cp** fails for reasons in api's own code (the fork differs from upstream), keep upstream in the matrix and report the cp failure verbatim. Remove `cp` from the workflow matrix with a comment naming the failing test, and mark the report DONE_WITH_CONCERNS.
- If upstream fails, fix it: that is parity.

- [ ] **Step 4: The workflow**

`.github/workflows/ci.yml` (whole file):

```yaml
name: CI

# Runs tools/ci.sh in the FrontAccounting CI image (cambell-prince/frontaccounting
# docker/ci), with this checkout at modules/api. api is not a FrontAccounting
# extension, so it is mounted, not activated.

on:
  push:
    branches:
      - master
      - master-cp
      - 'feature/**'
      - 'fix/**'
      - 'bug/**'
      - 'issue/**'
      - 'ci/**'
  pull_request:
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        fa: [upstream, cp]
        php: ['7.4', '8.3']
    uses: cambell-prince/frontaccounting/.github/workflows/plugin-test.yml@master-cp
    with:
      fa: ${{ matrix.fa }}
      php: ${{ matrix.php }}
      name: api
      activate: false
      setup: composer install --no-interaction --no-progress
      test: sh tools/ci.sh
```

- [ ] **Step 5: Delete the old stack and its references**

Run: `git rm -r -q docker`, then `git grep -n 'fa-api\|docker/'` and update each hit that describes the old stack. In `README.md`, replace the testing section with: CI runs `tools/ci.sh` in the image; locally, `../frontaccounting/docker/ci/plugin-test.sh --name api --no-activate --setup 'composer install --no-interaction --no-progress' . -- sh tools/ci.sh`.

Run: `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:latest -color .github/workflows/ci.yml`
Expected: nothing, or only the remote-workflow note.

- [ ] **Step 6: Commit**

```bash
git add -A tools tests/TestEnvironment.php .github/workflows/ci.yml README.md
git update-index --chmod=+x tools/ci.sh
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "ci: Run CI in the FrontAccounting CI image

tools/ci.sh (lint, analyze, phpunit) runs with this checkout mounted at
modules/api in the shared image; the tests take their base URL from FA_URL.
The docker/ test stack is gone.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Wave 3 (controller): publish, then adopt

- [ ] FA fork:
  1. Run `docker/ci/test/run.sh` on the cp and upstream 7.4 images.
  2. Push `feature/ci-datasets` and open a PR to `master-cp` (`--repo cambell-prince/frontaccounting`).
  3. Wait for CI to go green (four builds with smoke tests, and the prune dry run).
  4. Ask the user to merge, then squash-merge when they say.
  5. Wait for master-cp's CI image run to publish.
- [ ] graphql, sgw_sales, api:
  1. Push each `ci/fa-ci-package` branch and open its PR.
  2. Watch CI. Every matrix job must be green, with spec §5's counts in the job logs.
  3. Merge when the user says, graphql first. sgw_sales' GraphQL job then uses graphql's `seed.sh`.
