# FrontAccounting CI Package: Development Environments (plan 3A)

> **For agentic workers:** REQUIRED SUB-SKILL: Use cjp:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task, wave by wave per the Execution Schedule. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the package persistent development environments (`docker/ci/plugin-dev.sh`). The host's `modules/` folder is mounted whole into FrontAccounting, edits are live, and a list you opt into decides which modules are active, including on a copy of a live database. Then retire graphql's own `docker/` stack onto it.

**Architecture:** Following imscp's development stack, `plugin-dev.sh` bind-mounts the `modules/` folder of a FrontAccounting checkout at `/var/www/html/modules` in a named container (`fa-dev-<env>`). Its database is on a named volume and Apache is on a fixed port. `FA_DEV_MODULES`, read from `docker/ci/dev/<env>.env` or the shell, lists the modules to register and activate through FA. `link` applies a changed list without recreating anything. `plugin-test.sh` and `plugin-dev.sh` share run-as-you and activation through `lib.sh`, and four small in-image helpers support backups, live extension ids and deactivation. graphql moves its setup and dev fixtures into `tools/`.

**Tech Stack:** bash/sh, Docker (bind mounts, named volumes, labels), MariaDB, PHP CLI helpers, the existing `docker/ci` test harness.

**Spec:** `docs/superpowers/specs/2026-09-28-fa-ci-package-design.md` (§6; §1-§5 for context)

## Global Constraints

- Container `fa-dev-<env>`, volume `fa-dev-<env>-db` at `/var/lib/mysql`, Apache on `127.0.0.1:<FA_DEV_PORT>` (default 8100). The default env is `dev`.
- The modules mount: `FA_DEV_MODULES_ROOT` (default `<the checkout plugin-dev.sh is in>/modules`) goes at `/var/www/html/modules`, **not** elsewhere with symlinks. FA plugins resolve FA through their real path.
- Settings come from `docker/ci/dev/<env>.env` (or `--config FILE`). `FA_DEV_*` variables already in the shell win over the file. `docker/ci/dev/*.env` is gitignored; `docker/ci/dev/example.env` is committed.
- Settings and defaults:
  - `FA_DEV_MODULES` (empty)
  - `FA_DEV_MODULES_ROOT`
  - `FA_DEV_THEMES` (empty)
  - `FA_DEV_THEMES_ROOT` (`<checkout>/themes`)
  - `FA_DEV_PORT` (8100)
  - `FA_DEV_DATASET` (`test`)
  - `FA_DEV_EXTENSIONS` (empty)
  - `FA_DEV_INIT` (`yes`)
  - `FA_DEV_MOUNTS` (empty)
  - `FA_DEV_IMAGE` (default from `FA_DEV_FA`, `cp`, and `FA_DEV_PHP`, `7.4`)
- These apply only at creation: the mounts, themes, port, image and dataset. The module list applies on `up` and `link`. A dataset loads only into a new volume.
- Activation follows `FA_DEV_MODULES`' order. With `FA_DEV_EXTENSIONS`, the listed ids are kept, and unlisted modules get ids after every id the file has used.
- Re-activation after the database changed first marks the modules inactive, because FA runs a module's install SQL only when it becomes active.
- The init convention: after activation, each activated module's `tools/init.sh`, if present, runs in its directory, unless `FA_DEV_INIT=no`.
- Commands inside run as the host uid:gid with group www-data (33), `umask 002`, `HOME=/tmp`.
- `destroy` refuses without `--yes`. A failed creation keeps the environment.
- `plugin-test.sh`'s behaviour and `docker/ci/test/driver.sh` must not change, apart from sharing code through `lib.sh`.
- Every repo has `core.fileMode=false`. Record executable modes with `git update-index --chmod=+x <file>` after `git add`.
- Scratch dirs get their own names (`TMP_A=$(mktemp -d)`), never `HOME`. Tests never touch the user's real checkout or config.
- The machine thermally throttles, so run one docker build or suite at a time.
- Commit as `git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit ...` with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

- An edit on the host must show on the next request, with no restart. Test: Task 2, "an edit on the host is live".
- Changing `FA_DEV_MODULES` and running `link` must activate and deactivate modules without recreating the container. Test: Task 2, "link applies a smaller list" and "the same container".
- `up` on an existing environment must keep its database, even with a different `FA_DEV_DATASET`. Test: Task 2, "up again keeps the data".
- `db load` of a dump that lacks a module's tables must leave the module working. Its install SQL must run again, which requires the inactive-then-active step. Test: Task 2, "db load re-runs the modules' install SQL".
- `FA_DEV_EXTENSIONS`: listed ids hold, an unlisted module gets an id after the file's ids, and activation keeps `FA_DEV_MODULES`' order even when the file lists them differently. Test: Task 2, the extension-id cases.

## Execution Schedule

| Wave | Tasks | Model | Notes |
|------|-------|-------|-------|
| 1 | Task 1 | sonnet | Shared `lib.sh` functions (`plugin-test.sh` switched onto them) and the in-image helpers. Complete code given. |
| 2 | Task 2 | opus | `plugin-dev.sh`: environments, the modules mount, `link`, data commands, README. Judgment around docker lifecycle and failures. |
| CP1 | — | — | plan base..end of wave 2: code-review medium + spec check (spec §6, package part). Must finish before wave 3, which builds on it. |
| 3 | Task 3 | opus | graphql moves onto the dev mode (graphql repo). |
| CP2 | — | — | plan base..end of wave 3 in both repos: code-review medium + spec check (full §6). |
| 4 | Controller | — | FA PR, CI, merge when the user says, then republish. graphql PR, CI, merge when the user says. Then, with the user's go-ahead, move their old graphql dev stack's data into the new environment. |

Worktrees:
- FA fork: `/home/cambell/src/sgw/frontaccounting/.claude/worktrees/ci-dev`, branch `feature/ci-dev` from `origin/master-cp`. This is where this plan lives.
- graphql: `/home/cambell/src/sgw/frontaccounting/.claude/worktrees/graphql-dev`, branch `dev/fa-ci-dev` from `origin/main`. The controller creates it before wave 3.

`$FA_CI` below means `/home/cambell/src/sgw/frontaccounting/.claude/worktrees/ci-dev/docker/ci`. The local test image is `fa-ci:local-cp-7.4`, rebuilt from the FA worktree with `docker/ci/build-image.sh cp 7.4 fa-ci:local-cp-7.4` whenever `docker/ci/image/*` or the Dockerfile changes.

---

### Task 1: Shared functions and in-image helpers

**Files (FA worktree):**
- Modify: `docker/ci/lib.sh` (add `ci_as_user`, `ci_activate`)
- Modify: `docker/ci/plugin-test.sh` (use them; behaviour unchanged)
- Modify: `docker/ci/image/fa-ci-register` (`--id N`)
- Modify: `docker/ci/image/fa-ci-dataset` (a file path as the dataset)
- Create: `docker/ci/image/fa-ci-ext-list`, `docker/ci/image/fa-ci-deactivate`
- Test: `docker/ci/test/attach.sh`, `docker/ci/test/image.sh`; `docker/ci/test/driver.sh` unchanged, as the regression guard

**Interfaces:**
- Consumes: the merged package: `log`, `die`, `ci_boot`, `ci_diagnostics`, `fa_ci_image` and `module_name` in `lib.sh`; the in-image `fa-ci-login`, `fa-ci-register`, `fa-ci-activate`, `fa-ci-grant` and `fa-ci-dataset`.
- Produces:
  - `ci_as_user <container> <dir> <command>`: `sh -c` as the caller. It passes `COMPOSER_CACHE_DIR=/tmp/composer-cache` when `CI_COMPOSER_CACHE=yes`.
  - `ci_activate <container> <module[:id]>...`: registers each module (under the id when given) and activates it, in order, then runs `fa-ci-grant`.
  - `fa-ci-register [--id N] <name> <path>`: prints `registered <name> as extension <id>`. It exits 1 with `extension <N> is <other>` if the id is taken, or `<name> is extension <M>, not <N>`.
  - `fa-ci-dataset <test|demo|/abs/path.sql[.gz]>`: a file is loaded as it is, plus the `test` login.
  - `fa-ci-ext-list <file>`: `<id> <package>` for each `'type' => 'extension'` entry, in the file's order.
  - `fa-ci-deactivate <name>`: prints `deactivated <name>`. It exits 1 with `FrontAccounting did not deactivate <name>`, or `<name> is not registered`.

- [ ] **Step 1: Write the failing tests**

In `docker/ci/test/attach.sh`, before `finish`, add:

```bash
expect_status 0 "registers with a chosen id" docker exec -u www-data "$c" fa-ci-register --id 9 ci_gamma modules/ci_gamma
expect_contains "as extension 9" "registered ci_gamma as extension 9" "$OUT"
expect_status 0 "the next registration follows the highest id" docker exec -u www-data "$c" fa-ci-register ci_delta modules/ci_delta
expect_contains "as extension 10" "registered ci_delta as extension 10" "$OUT"
expect_status 1 "an id another module has is refused" docker exec -u www-data "$c" fa-ci-register --id 1 ci_epsilon modules/ci_epsilon
expect_contains "naming who has it" "extension 1 is ci_alpha" "$OUT"
expect_status 1 "a module keeps the id it has" docker exec -u www-data "$c" fa-ci-register --id 4 ci_alpha modules/ci_alpha
expect_contains "saying so" "ci_alpha is extension 1, not 4" "$OUT"
expect_status 0 "the same module and id again is a no-op" docker exec -u www-data "$c" fa-ci-register --id 9 ci_gamma modules/ci_gamma
expect_contains "already registered" "already registered as extension 9" "$OUT"

state() { docker exec "$c" php -r 'include "/var/www/html/company/0/installed_extensions.php"; foreach ($installed_extensions as $e) echo $e["package"], "=", $e["active"] ? "on" : "off", "\n";'; }
expect_status 0 "deactivates a module through FA's form" docker exec "$c" fa-ci-deactivate ci_beta
expect_contains "saying so" "deactivated ci_beta" "$OUT"
expect_status 0 "reads the lists" state
expect_contains "ci_beta is off" "ci_beta=off" "$OUT"
expect_contains "ci_alpha stays on" "ci_alpha=on" "$OUT"
expect_status 0 "deactivating again is a no-op" docker exec "$c" fa-ci-deactivate ci_beta
expect_status 1 "an unregistered module is refused" docker exec "$c" fa-ci-deactivate ci_nothing
expect_contains "saying why" "not registered" "$OUT"
expect_status 0 "and it activates again" docker exec "$c" fa-ci-activate ci_beta

docker exec "$c" sh -c "cat > /tmp/ext.php" <<'PHP'
<?php
$next_extension_id = 8;
$installed_extensions = array (
  0 => array ('package' => 'chart_en_AU', 'name' => 'chart', 'version' => '-', 'available' => '', 'type' => 'chart', 'active' => false, 'path' => 'sql'),
  5 => array ('package' => 'sgw_sales', 'name' => 'sgw_sales', 'version' => '-', 'available' => '', 'type' => 'extension', 'path' => 'modules/sgw_sales', 'active' => false),
  3 => array ('package' => 'sgw_import', 'name' => 'sgw_import', 'version' => '-', 'available' => '', 'type' => 'extension', 'path' => 'modules/sgw_import', 'active' => false),
);
PHP
expect_status 0 "lists the extensions of an installed_extensions.php" docker exec "$c" fa-ci-ext-list /tmp/ext.php
expect_contains "sgw_sales as 5" "5 sgw_sales" "$OUT"
expect_contains "sgw_import as 3" "3 sgw_import" "$OUT"
expect_absent "not the chart" "chart_en_AU" "$OUT"
expect_status 0 "in the file's order" test "$(printf '%s\n' "$OUT" | head -n 1)" = "5 sgw_sales"
```

In `docker/ci/test/image.sh`, before `finish`, add:

```bash
expect_status 0 "loads a dump file as the dataset, as it is" docker exec "$c" sh -c '
    mariadb-dump fa_test | gzip > /tmp/before.sql.gz &&
    mariadb fa_test -e "CREATE TABLE 0_ci_after (id int)" &&
    fa-ci-dataset /tmp/before.sql.gz &&
    ! mariadb -N fa_test -e "SHOW TABLES LIKE \"0_ci_after\"" | grep -q . &&
    mariadb -N fa_test -e "SELECT CONCAT(\"login=\", user_id) FROM 0_users WHERE user_id = \"test\""'
expect_contains "with the test login" "login=test" "$OUT"
expect_status 2 "a missing dataset file is refused" docker exec "$c" fa-ci-dataset /tmp/no-such.sql
```

- [ ] **Step 2: Run them to verify they fail**

Run: `docker/ci/build-image.sh cp 7.4 fa-ci:local-cp-7.4 && FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/image.sh; FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/attach.sh`
Expected: the new checks FAIL. `--id` is taken as the module name, `fa-ci-deactivate` and `fa-ci-ext-list` are not found, and the dataset file is refused.

- [ ] **Step 3: The in-image helpers**

`docker/ci/image/fa-ci-register`: replace the argument handling at the top, from `if ($argc !== 3) {` through `$root = getenv('FA_ROOT') ?: '/var/www/html';`, with:

```php
$args = array_slice($argv, 1);
$want = null;
if (count($args) === 4 && $args[0] === '--id' && ctype_digit($args[1])) {
	$want = (int) $args[1];
	$args = array_slice($args, 2);
}
if (count($args) !== 2) {
	fwrite(STDERR, "usage: fa-ci-register [--id N] <name> <path relative to the FA root>\n");
	exit(2);
}
list($name, $path) = $args;
$root = getenv('FA_ROOT') ?: '/var/www/html';
```

Replace the block from `foreach ($global as $id => $ext) {` through `$id = $next ?: (count($global) ? max(array_keys($global)) + 1 : 1);` with:

```php
foreach ($global as $id => $ext) {
	if ($ext['package'] === $name) {
		if ($want !== null && $want !== $id) {
			fwrite(STDERR, "fa-ci-register: $name is extension $id, not $want\n");
			exit(1);
		}
		echo "$name is already registered as extension $id\n";
		exit(0);
	}
}
if ($want !== null) {
	if (isset($global[$want])) {
		fwrite(STDERR, "fa-ci-register: extension $want is {$global[$want]['package']}\n");
		exit(1);
	}
	$id = $want;
} else {
	$id = $next ?: (count($global) ? max(array_keys($global)) + 1 : 1);
}
```

Change `save_extensions("$root/installed_extensions.php", $global, $id + 1);` to `save_extensions("$root/installed_extensions.php", $global, max((int) $next, $id + 1));`. Update the header comment: `--id N` registers under that id (a live site's), refuses an id another module holds, and moves `$next_extension_id` past it.

`docker/ci/image/fa-ci-dataset`: change the header comment and the argument handling to:

```sh
# fa-ci-dataset <test|demo|/path/to/file.sql[.gz]>: replace the fa_test database with a dataset.
#
#   test  the fixture the image was seeded with (modules/tests/data/fa_test.sql.gz)
#   demo  FrontAccounting's own sql/en_US-demo.sql: customers, items, orders.
#         Its fiscal years end in the past, so years are appended until one
#         covers today.
#   file  a dump (a backup of a real site), loaded as it is: nothing in it is
#         changed, and its fiscal years are left alone.
#
# Every dataset gets a test/test login (role 2) for the package's helpers.
# Run as root, before modules are activated, so their update SQL runs on it.
set -eu
[ "$#" -eq 1 ] || { echo "usage: fa-ci-dataset <test|demo|/path/to/file.sql[.gz]>" >&2; exit 2; }
db="${FA_DB_NAME:-fa_test}"
src="$1"
extend_years=yes

case "$src" in
    test) load() { gunzip -c /usr/local/share/fa-ci/fa_test.sql.gz; } ;;
    demo) load() { cat "${FA_ROOT:-/var/www/html}/sql/en_US-demo.sql"; } ;;
    /*)
        [ -f "$src" ] || { echo "fa-ci-dataset: no such file: $src" >&2; exit 2; }
        extend_years=no
        case "$src" in
            *.gz) load() { gunzip -c "$src"; } ;;
            *) load() { cat "$src"; } ;;
        esac ;;
    *) echo "fa-ci-dataset: the dataset is test, demo or an absolute path, not '$src'" >&2; exit 2 ;;
esac
```

Wrap the existing fiscal-year loop and its `f_year` update in `if [ "$extend_years" = yes ]; then ... fi`. Keep the `test` user insert unconditional. Print `dataset $src loaded`, plus the years added when there were any.

`docker/ci/image/fa-ci-ext-list`:

```sh
#!/bin/sh
# fa-ci-ext-list <installed_extensions.php>: "<id> <package>" for each extension
# (type 'extension') in a FrontAccounting extension list, in the file's order.
# A live site's list gives the ids its security roles were built with, so a
# copy of its database needs its modules registered under the same ids.
set -eu
[ "$#" -eq 1 ] || { echo "usage: fa-ci-ext-list <installed_extensions.php>" >&2; exit 2; }
[ -f "$1" ] || { echo "fa-ci-ext-list: no such file: $1" >&2; exit 2; }
php -r '
    $installed_extensions = array();
    include $argv[1];
    foreach ($installed_extensions as $id => $e)
        if (($e["type"] ?? "") === "extension") echo $id, " ", $e["package"], "\n";' "$1"
```

`docker/ci/image/fa-ci-deactivate`:

```sh
#!/bin/sh
# fa-ci-deactivate <name>: deactivate a module for company 0 through
# FrontAccounting's own Setup -> Install/Activate Extensions form, so its
# deactivate_extension() runs as it would on a real install. Every other
# active module is sent ticked, so it stays active. Fails unless FrontAccounting
# then lists the module as inactive.
set -eu
[ "$#" -eq 1 ] || { echo "usage: fa-ci-deactivate <name>" >&2; exit 2; }
name="$1"
root="${FA_ROOT:-/var/www/html}"
url="${FA_URL:-http://localhost}"
list="$root/company/0/installed_extensions.php"
jar="$(mktemp)"
page="$(mktemp)"
trap 'rm -f "$jar" "$page"' EXIT

# The extension ids to send ticked: everything active now except $name.
ids="$(php -r '
    $installed_extensions = array();
    include $argv[1];
    $found = false;
    foreach ($installed_extensions as $id => $e) {
        if ($e["package"] === $argv[2]) $found = true;
        elseif (!empty($e["active"])) echo $id, "\n";
    }
    exit($found ? 0 : 1);' "$list" "$name")" \
    || { echo "fa-ci-deactivate: $name is not registered" >&2; exit 1; }

fa-ci-login "$jar"
set -- --data-urlencode extset=0 --data-urlencode Refresh=Update
for id in $ids; do set -- "$@" --data-urlencode "Active$id=1"; done
curl -fsS -c "$jar" -b "$jar" -o "$page" "$@" "$url/admin/inst_module.php"

if php -r '
    $installed_extensions = array();
    include $argv[1];
    foreach ($installed_extensions as $e)
        if ($e["package"] === $argv[2] && !empty($e["active"])) exit(0);
    exit(1);' "$list" "$name"; then
    echo "fa-ci-deactivate: FrontAccounting did not deactivate $name" >&2
    exit 1
fi
echo "deactivated $name"
```

Run: `chmod +x docker/ci/image/fa-ci-ext-list docker/ci/image/fa-ci-deactivate`.

- [ ] **Step 4: The shared functions in `lib.sh`**

Append to `docker/ci/lib.sh`:

```bash
# ci_as_user <container> <dir> <command>: sh -c <command> in <dir> as the caller,
# with group www-data added, umask 002 and HOME=/tmp; composer's cache too when
# CI_COMPOSER_CACHE=yes (the caller mounted it at /tmp/composer-cache).
ci_as_user() {
    local env=(-e HOME=/tmp)
    [ "${CI_COMPOSER_CACHE:-}" != yes ] || env+=(-e COMPOSER_CACHE_DIR=/tmp/composer-cache)
    docker exec -w "$2" "${env[@]}" "$1" \
        setpriv --reuid="$(id -u)" --regid="$(id -g)" --groups=33 \
        sh -c "umask 002; $3"
}

# ci_activate <container> <module[:id]>...: register each module (under that
# extension id when given) and activate it through FrontAccounting, in order,
# then give the test user every area.
ci_activate() {
    local c="$1" m name id
    shift
    for m in "$@"; do
        name="${m%%:*}"
        id=''
        [ "$name" = "$m" ] || id="${m#*:}"
        log "activating $name${id:+ as extension $id}"
        if [ -n "$id" ]; then
            docker exec -u www-data "$c" fa-ci-register --id "$id" "$name" "modules/$name"
        else
            docker exec -u www-data "$c" fa-ci-register "$name" "modules/$name"
        fi
        docker exec "$c" fa-ci-activate "$name"
    done
    docker exec "$c" fa-ci-grant
}
```

- [ ] **Step 5: Switch `plugin-test.sh` onto them**

In `docker/ci/plugin-test.sh`:
- Replace the `exec_env=(-e HOME=/tmp)` block, through its closing `fi`, with:

```bash
if [ -n "${COMPOSER_CACHE_DIR:-}" ]; then
    mkdir -p "$COMPOSER_CACHE_DIR"
    run_args+=(-v "$COMPOSER_CACHE_DIR:/tmp/composer-cache")
    CI_COMPOSER_CACHE=yes
fi
```

- Delete the local `as_user()` function. Replace each `as_user "<dir>" "<cmd>"` call with `ci_as_user "$CONTAINER" "<dir>" "<cmd>"`.
- Replace the activation block (`if [ "$ACTIVATE" = yes ]; then ... fi`) with:

```bash
if [ "$ACTIVATE" = yes ]; then
    ci_activate "$CONTAINER" "${deps[@]+"${deps[@]}"}" "$NAME"
fi
```

- [ ] **Step 6: Run the tests**

Run, one at a time: `docker/ci/build-image.sh cp 7.4 fa-ci:local-cp-7.4 && FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/run.sh`
Expected: every section `0 failed`, `all passed`. driver.sh passing unchanged proves the refactor kept `plugin-test.sh`'s behaviour.

Run: `docker run --rm -v "$PWD":/mnt -w /mnt koalaman/shellcheck:stable -x docker/ci/lib.sh docker/ci/plugin-test.sh docker/ci/image/fa-ci-ext-list docker/ci/image/fa-ci-deactivate docker/ci/image/fa-ci-dataset docker/ci/test/*.sh && php -l docker/ci/image/fa-ci-register`
Expected: clean, `No syntax errors detected`.

- [ ] **Step 7: Commit**

```bash
git add docker/ci
git update-index --chmod=+x docker/ci/image/fa-ci-ext-list docker/ci/image/fa-ci-deactivate
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "ci: Shared driver functions; ids, dumps and deactivation in the image

lib.sh gains ci_as_user and ci_activate, which plugin-test.sh now uses and
plugin-dev.sh will. fa-ci-register takes --id (a live site's extension id),
fa-ci-dataset loads a dump file as it is, fa-ci-ext-list reads the ids out of
an installed_extensions.php, and fa-ci-deactivate uses FA's own form.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `plugin-dev.sh`: the modules mount, opt-in modules, persistence

**Files (FA worktree):**
- Create: `docker/ci/plugin-dev.sh`
- Create: `docker/ci/dev/example.env`
- Modify: `.gitignore` (the environments' own configs)
- Modify: `docker/ci/README.md` (a "Development environments" section)
- Test: `docker/ci/test/dev.sh`
- Modify: `docker/ci/test/run.sh` (run dev.sh after driver.sh)

**Interfaces:**
- Consumes (Task 1): `ci_as_user`, `ci_activate`, `ci_boot`, `ci_diagnostics`, `fa_ci_image`, `log`, `die`; the in-image `fa-ci-dataset`, `fa-ci-ext-list`, `fa-ci-deactivate` and `fa-ci-wait-ready`.
- Produces (used by Task 3 and plan 3B):

```
docker/ci/plugin-dev.sh [--env NAME] [--config FILE] up | link | activate | down | destroy --yes
                                                    | status | url | shell | exec [--dir D] <command>
                                                    | logs [app|errors] | mail [list|show <file>|clear]
                                                    | db dump [file] | db load <file> | db shell
settings: FA_DEV_MODULES FA_DEV_MODULES_ROOT FA_DEV_THEMES FA_DEV_THEMES_ROOT FA_DEV_PORT
          FA_DEV_DATASET FA_DEV_EXTENSIONS FA_DEV_INIT FA_DEV_MOUNTS FA_DEV_IMAGE FA_DEV_FA FA_DEV_PHP
```

  `up` prints the URL on stdout as its last line. The applied module list is recorded in the container at `/var/lib/fa-dev/modules`, one name per line.

- [ ] **Step 1: Write the failing test**

`docker/ci/test/dev.sh`:

```bash
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
env_a="citest$$a"; env_b="citest$$b"; env_c="citest$$c"; env_e="citest$$e"
port_a="$(free_port)"; port_c="$(free_port)"; port_e="$(free_port)"
cleanup() {
    for e in "$env_a" "$env_b" "$env_c" "$env_e"; do
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
state() { "$d" --env "$1" exec 'php -r "include \"/var/www/html/company/0/installed_extensions.php\"; foreach (\$installed_extensions as \$id => \$e) echo \$e[\"package\"], \"@\", \$id, \"=\", \$e[\"active\"] ? \"on\" : \"off\", \" \";"'; }
sqlq() { "$d" --env "$1" exec "mariadb -h localhost -u fa -pfa -N fa_test -e \"$2\""; }

expect_status 0 "up creates an environment from the config, the shell winning" dev_a up
expect_contains "and prints its URL" "http://localhost:$port_a/" "$OUT"
expect_status 0 "FrontAccounting answers on the port" curl -fsS -o /dev/null "http://localhost:$port_a/index.php"
expect_status 0 "reads the lists" state "$env_a"
expect_contains "ci_alpha on" "ci_alpha@1=on" "$OUT"
expect_contains "ci_beta on, after it" "ci_beta@2=on" "$OUT"
expect_absent "folders not listed are not extensions" "ci_plain" "$OUT"
expect_status 0 "ci_alpha's tools/init.sh ran" sqlq "$env_a" "SELECT marker FROM 0_ci_alpha"
expect_contains "its row" "init-ran" "$OUT"

printf '<?php echo "live-" . "edit";\n' > "$mods/ci_alpha/probe.php"
expect_status 0 "an edit on the host is live" curl -fsS "http://localhost:$port_a/modules/ci_alpha/probe.php"
expect_contains "served as written" "live-edit" "$OUT"
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
dev_c() { FA_DEV_MODULES="ci_alpha ci_beta ci_gamma" FA_DEV_PORT="$port_c" FA_DEV_EXTENSIONS="$TMP_A/live-extensions.php" "$d" --env "$env_c" "$@"; }
expect_status 0 "a live site's extension ids, in the list's own order (ci_beta needs ci_alpha first)" dev_c up
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
```

Add `run dev.sh` after `run driver.sh` inside the `if [ -n "$image" ]` block of `docker/ci/test/run.sh`. Run: `chmod +x docker/ci/test/dev.sh`.

- [ ] **Step 2: Run it to verify it fails**

Run: `FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/dev.sh`
Expected: FAIL from the first case (`plugin-dev.sh: No such file or directory`).

- [ ] **Step 3: Write `plugin-dev.sh`**

`docker/ci/plugin-dev.sh`:

```bash
#!/usr/bin/env bash
#
# Persistent FrontAccounting development environments, from the CI image.
#
#   docker/ci/plugin-dev.sh [--env NAME] [--config FILE] <command>
#
# Commands:
#   up                    create the environment, or start it again and link
#   link                  apply FA_DEV_MODULES: activate what it lists,
#                         deactivate what it no longer lists
#   activate              activate every listed module again, from scratch
#   down                  stop it; its data stays
#   destroy --yes         remove the container and its database volume
#   status | url
#   shell                 bash in the FrontAccounting tree, as you
#   exec [--dir D] <cmd>  a command in the FrontAccounting tree (or D under it)
#   logs [app|errors]
#   mail [list|show <file>|clear]
#   db dump [file] | db load <file> | db shell
#
# The modules/ folder of a FrontAccounting checkout (FA_DEV_MODULES_ROOT,
# default: the modules/ of the checkout this script is in) is mounted at
# /var/www/html/modules, so an edit on this machine is live on the next
# request. Which of its folders are extensions is opt-in: FA_DEV_MODULES,
# activated in that order.
#
# Settings come from the environment's config file, docker/ci/dev/<env>.env
# (see example.env there; --config to name another), and FA_DEV_* variables
# already set in your shell win over it:
#
#   FA_DEV_MODULES        folders of modules/ to activate, in order
#   FA_DEV_MODULES_ROOT   the folder mounted as modules/
#   FA_DEV_THEMES         folders of FA_DEV_THEMES_ROOT to mount under themes/
#   FA_DEV_THEMES_ROOT    default: the themes/ of this checkout
#   FA_DEV_PORT           Apache's port on this machine (default 8100)
#   FA_DEV_DATASET        test, demo, or a .sql/.sql.gz backup (default test)
#   FA_DEV_EXTENSIONS     an installed_extensions.php (a live site's) whose
#                         extension ids the modules keep
#   FA_DEV_INIT           yes (default): run each activated module's own
#                         tools/init.sh after activation; no to skip
#   FA_DEV_MOUNTS         more HOST:CONTAINER mounts, space separated, e.g. a
#                         plugin checked out elsewhere over modules/NAME
#   FA_DEV_IMAGE          the image (default: FA_DEV_FA cp, FA_DEV_PHP 7.4)
#
# The environment is the container fa-dev-<env> (default env: dev), with its
# database on the volume fa-dev-<env>-db. The mounts, themes, port, image and
# dataset take effect when it is created; the module list on up and link.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"
checkout="$(cd "$here/../.." && pwd)"
FA=/var/www/html

ENV_NAME=dev
CONFIG=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --env) ENV_NAME="$2"; shift 2 ;;
        --config) CONFIG="$2"; shift 2 ;;
        *) break ;;
    esac
done
case "$ENV_NAME" in ''|*[!A-Za-z0-9_.-]*) die "--env takes letters, digits, '.', '_' and '-'" ;; esac
[ -n "$CONFIG" ] || CONFIG="$here/dev/$ENV_NAME.env"
[ "$#" -ge 1 ] || die "usage: plugin-dev.sh [--env NAME] [--config FILE] up|link|activate|down|destroy|status|url|shell|exec|logs|mail|db ..."
CMD="$1"
shift
CONTAINER="fa-dev-$ENV_NAME"
VOLUME="fa-dev-$ENV_NAME-db"

# The config file, then the FA_DEV_* already in the environment on top.
load_config() {
    local saved line
    saved="$(env | grep '^FA_DEV_' || true)"
    if [ -f "$CONFIG" ]; then
        set -a
        # shellcheck disable=SC1090 # the environment's own config
        . "$CONFIG"
        set +a
    fi
    while IFS= read -r line; do [ -z "$line" ] || export "${line?}"; done <<< "$saved"
    FA_DEV_MODULES="${FA_DEV_MODULES:-}"
    FA_DEV_MODULES_ROOT="${FA_DEV_MODULES_ROOT:-$checkout/modules}"
    FA_DEV_THEMES="${FA_DEV_THEMES:-}"
    FA_DEV_THEMES_ROOT="${FA_DEV_THEMES_ROOT:-$checkout/themes}"
    FA_DEV_PORT="${FA_DEV_PORT:-8100}"
    FA_DEV_DATASET="${FA_DEV_DATASET:-test}"
    FA_DEV_EXTENSIONS="${FA_DEV_EXTENSIONS:-}"
    FA_DEV_INIT="${FA_DEV_INIT:-yes}"
    FA_DEV_MOUNTS="${FA_DEV_MOUNTS:-}"
    FA_DEV_IMAGE="${FA_DEV_IMAGE:-$(fa_ci_image "${FA_DEV_FA:-cp}" "${FA_DEV_PHP:-7.4}")}"
}

exists() { docker inspect "$CONTAINER" >/dev/null 2>&1; }
running() { [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = true ]; }
require_env() { exists || die "no environment '$ENV_NAME' ($CONTAINER); create it with: plugin-dev.sh --env $ENV_NAME up"; }
label() { docker inspect -f "{{index .Config.Labels \"fa-dev.$1\"}}" "$CONTAINER"; }
url() { echo "http://localhost:$(label port)/"; }
applied() { docker exec "$CONTAINER" cat /var/lib/fa-dev/modules 2>/dev/null || true; }
save_applied() {
    docker exec "$CONTAINER" sh -c 'mkdir -p /var/lib/fa-dev && : > /var/lib/fa-dev/modules && for m in "$@"; do echo "$m" >> /var/lib/fa-dev/modules; done' sh "$@"
}

# Where a listed module comes from on this machine: a FA_DEV_MOUNTS entry over
# modules/<name>, else the modules folder.
module_source() {
    local spec
    for spec in $FA_DEV_MOUNTS; do
        [ "${spec#*:}" != "$FA/modules/$1" ] || { echo "${spec%%:*}"; return; }
    done
    echo "$FA_DEV_MODULES_ROOT/$1"
}

# The modules to activate, as name or name:id, in FA_DEV_MODULES' order: ids
# from FA_DEV_EXTENSIONS where it lists the module.
module_specs() {
    local m id listed=''
    if [ -n "$FA_DEV_EXTENSIONS" ]; then
        docker cp "$FA_DEV_EXTENSIONS" "$CONTAINER:/tmp/fa-dev-extensions.php"
        listed="$(docker exec "$CONTAINER" fa-ci-ext-list /tmp/fa-dev-extensions.php)"
    fi
    for m in $FA_DEV_MODULES; do
        id="$(printf '%s\n' "$listed" | awk -v m="$m" '$2 == m {print $1; exit}')"
        if [ -n "$id" ]; then echo "$m:$id"; else echo "$m"; fi
    done
}

# FrontAccounting runs a module's install SQL only as it becomes active, so a
# re-activation (after the database changed) starts from inactive.
mark_inactive() {
    [ "$#" -gt 0 ] || return 0
    docker exec -u www-data "$CONTAINER" php -r '
        $f = "/var/www/html/company/0/installed_extensions.php";
        $installed_extensions = array();
        include $f;
        $names = array_slice($argv, 1);
        foreach ($installed_extensions as $k => $e)
            if (in_array($e["package"], $names, true)) $installed_extensions[$k]["active"] = false;
        file_put_contents($f, "<?php\n\n\$installed_extensions = " . var_export($installed_extensions, true) . ";\n");' "$@"
}

# Each module's own tools/init.sh, in its directory, unless FA_DEV_INIT=no.
run_inits() {
    [ "$FA_DEV_INIT" = yes ] || return 0
    local m
    for m in "$@"; do
        if docker exec "$CONTAINER" test -f "$FA/modules/$m/tools/init.sh"; then
            log "init: $m (tools/init.sh)"
            ci_as_user "$CONTAINER" "$FA/modules/$m" 'sh tools/init.sh'
        fi
    done
}

# Every listed module, activated from inactive, then their inits.
activate_all() {
    local specs=() names=() s
    while IFS= read -r s; do [ -z "$s" ] || specs+=("$s"); done < <(module_specs)
    for s in "${specs[@]+"${specs[@]}"}"; do names+=("${s%%:*}"); done
    if [ "${#specs[@]}" -gt 0 ]; then
        mark_inactive "${names[@]}"
        ci_activate "$CONTAINER" "${specs[@]}"
    fi
    save_applied "${names[@]+"${names[@]}"}"
    run_inits "${names[@]+"${names[@]}"}"
}

# The listed modules brought in line with FA_DEV_MODULES: those no longer
# listed deactivated, new ones activated (and their inits run).
cmd_link() {
    local specs=() names=() new=() was s m
    while IFS= read -r s; do [ -z "$s" ] || specs+=("$s"); done < <(module_specs)
    for s in "${specs[@]+"${specs[@]}"}"; do names+=("${s%%:*}"); done
    was=" $(applied | tr '\n' ' ') "
    for m in $was; do
        case " ${names[*]-} " in *" $m "*) ;; *) log "deactivating $m"; docker exec "$CONTAINER" fa-ci-deactivate "$m" ;; esac
    done
    for m in "${names[@]+"${names[@]}"}"; do
        case "$was" in *" $m "*) ;; *) new+=("$m") ;; esac
    done
    [ "${#specs[@]}" -eq 0 ] || ci_activate "$CONTAINER" "${specs[@]}"
    save_applied "${names[@]+"${names[@]}"}"
    run_inits "${new[@]+"${new[@]}"}"
}

report() {
    log "$ENV_NAME is up: $(url)"
    printf '  sign in as test/test, or as the dataset'"'"'s own users (admin/password on demo)\n' >&2
    printf '  modules: %s\n' "$(applied | tr '\n' ' ')" >&2
    url
}

cmd_up() {
    load_config
    if exists; then
        running || { log "starting $CONTAINER"; docker start "$CONTAINER" >/dev/null; }
        if ! docker exec "$CONTAINER" fa-ci-wait-ready 120; then
            ci_diagnostics "$CONTAINER"
            die "$CONTAINER did not become ready"
        fi
        log "$CONTAINER exists: its mounts, themes, port, image and dataset stay as created (destroy --yes to change them); applying FA_DEV_MODULES"
        cmd_link
        report
        return
    fi

    case "$FA_DEV_PORT" in ''|*[!0-9]*) die "FA_DEV_PORT takes a number, not '$FA_DEV_PORT'" ;; esac
    local dataset_file=''
    case "$FA_DEV_DATASET" in
        test|demo) ;;
        *)
            [ -f "$FA_DEV_DATASET" ] || { printf 'plugin-dev.sh: no such dataset file: %s\n' "$FA_DEV_DATASET" >&2; exit 2; }
            dataset_file="$(cd "$(dirname "$FA_DEV_DATASET")" && pwd)/$(basename "$FA_DEV_DATASET")" ;;
    esac
    [ -z "$FA_DEV_EXTENSIONS" ] || [ -f "$FA_DEV_EXTENSIONS" ] \
        || { printf 'plugin-dev.sh: no such file: %s\n' "$FA_DEV_EXTENSIONS" >&2; exit 2; }
    [ -d "$FA_DEV_MODULES_ROOT" ] || die "FA_DEV_MODULES_ROOT is not a directory: $FA_DEV_MODULES_ROOT"
    local m t
    for m in $FA_DEV_MODULES; do
        [ -f "$(module_source "$m")/hooks.php" ] || die "FA_DEV_MODULES lists $m, but $(module_source "$m") has no hooks.php"
    done
    for t in $FA_DEV_THEMES; do
        [ -d "$FA_DEV_THEMES_ROOT/$t" ] || die "FA_DEV_THEMES lists $t, but $FA_DEV_THEMES_ROOT/$t is not a directory"
    done
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$FA_DEV_PORT\$"; then
        die "port $FA_DEV_PORT is already in use on this machine; set FA_DEV_PORT to another"
    fi

    local run_args=(-p "127.0.0.1:$FA_DEV_PORT:80" -v "$VOLUME:/var/lib/mysql"
                    -v "$(cd "$FA_DEV_MODULES_ROOT" && pwd):$FA/modules"
                    --label "fa-dev.port=$FA_DEV_PORT" --label "fa-dev.dataset=$FA_DEV_DATASET")
    for t in $FA_DEV_THEMES; do run_args+=(-v "$(cd "$FA_DEV_THEMES_ROOT/$t" && pwd):$FA/themes/$t"); done
    for m in $FA_DEV_MOUNTS; do run_args+=(-v "$m"); done

    local fresh=yes
    if docker volume inspect "$VOLUME" >/dev/null 2>&1; then
        fresh=no
        log "keeping the database already in $VOLUME"
    fi

    # From here on a failure keeps the environment for inspection.
    trap 'rc=$?; if [ "$rc" -ne 0 ]; then [ "${CI_DIAGNOSED:-}" = yes ] || ci_diagnostics "$CONTAINER"; log "$CONTAINER kept for inspection: plugin-dev.sh --env $ENV_NAME logs | shell | activate | destroy --yes"; fi' EXIT
    ci_boot "$CONTAINER" "$FA_DEV_IMAGE" "${run_args[@]}"
    if [ "$fresh" = yes ] && [ -n "$dataset_file" ]; then
        log "dataset: $dataset_file"
        docker cp "$dataset_file" "$CONTAINER:/tmp/fa-dev-dataset.${dataset_file##*.}"
        docker exec "$CONTAINER" fa-ci-dataset "/tmp/fa-dev-dataset.${dataset_file##*.}"
    elif [ "$fresh" = yes ] && [ "$FA_DEV_DATASET" != test ]; then
        log "dataset: $FA_DEV_DATASET"
        docker exec "$CONTAINER" fa-ci-dataset "$FA_DEV_DATASET"
    fi
    if [ -n "$FA_DEV_EXTENSIONS" ]; then
        # Modules the site's list doesn't have get ids after every id it has used.
        docker cp "$FA_DEV_EXTENSIONS" "$CONTAINER:/tmp/fa-dev-extensions.php"
        docker exec -u www-data "$CONTAINER" php -r '
            $next_extension_id = 1; $installed_extensions = array();
            include "/tmp/fa-dev-extensions.php";
            $n = max((int) $next_extension_id, count($installed_extensions) ? max(array_keys($installed_extensions)) + 1 : 1);
            $f = "/var/www/html/installed_extensions.php";
            file_put_contents($f, preg_replace("/next_extension_id = \\d+/", "next_extension_id = $n", file_get_contents($f)));'
    fi
    activate_all
    trap - EXIT
    report
}

main() {
    case "$CMD" in
        up) cmd_up ;;
        link) load_config; require_env; cmd_link ;;
        activate) load_config; require_env; activate_all ;;
        down) require_env; docker stop "$CONTAINER" >/dev/null; log "$CONTAINER stopped; its data stays" ;;
        destroy)
            [ "${1:-}" = --yes ] || die "destroy removes $CONTAINER and its database ($VOLUME); run it with --yes"
            docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
            docker volume rm "$VOLUME" >/dev/null 2>&1 || true
            log "$ENV_NAME destroyed (the modules folder on this machine is untouched)" ;;
        status)
            require_env
            printf '%s: %s at %s\nmodules: %s\n' "$ENV_NAME" "$(running && echo running || echo stopped)" "$(url)" "$(applied | tr '\n' ' ')" ;;
        url) require_env; url ;;
        shell)
            require_env
            docker exec -it -w "$FA" -e HOME=/tmp "$CONTAINER" \
                setpriv --reuid="$(id -u)" --regid="$(id -g)" --groups=33 bash ;;
        exec)
            require_env
            local dir="$FA"
            if [ "${1:-}" = --dir ]; then dir="$FA/${2#/}"; shift 2; fi
            [ "$#" -ge 1 ] || die "usage: plugin-dev.sh [--env NAME] exec [--dir D] <command>"
            ci_as_user "$CONTAINER" "$dir" "$*" ;;
        logs)
            require_env
            case "${1:-errors}" in
                errors) docker exec "$CONTAINER" sh -c 'tail -n 100 /var/www/html/tmp/errors.log 2>/dev/null || echo "(no errors logged)"' ;;
                app) docker exec "$CONTAINER" sh -c 'tail -n 100 /var/log/apache2/error.log' ;;
                *) die "usage: plugin-dev.sh [--env NAME] logs [app|errors]" ;;
            esac ;;
        mail)
            require_env
            case "${1:-list}" in
                list) docker exec "$CONTAINER" sh -c 'cd /var/mail-catcher && ls -1t -- *.eml 2>/dev/null || echo "(no mail)"' ;;
                show) [ -n "${2:-}" ] || die "usage: plugin-dev.sh [--env NAME] mail show <file>"
                      docker exec "$CONTAINER" cat "/var/mail-catcher/$(basename "$2")" ;;
                clear) docker exec "$CONTAINER" sh -c 'rm -f /var/mail-catcher/*.eml' ;;
                *) die "usage: plugin-dev.sh [--env NAME] mail [list|show <file>|clear]" ;;
            esac ;;
        db)
            require_env
            case "${1:-}" in
                dump)
                    local out="${2:-fa-dev-$ENV_NAME-$(date +%Y%m%d-%H%M%S).sql.gz}"
                    docker exec "$CONTAINER" sh -c 'mariadb-dump --single-transaction --routines fa_test | gzip -c' > "$out"
                    gzip -t "$out"
                    log "dumped to $out" ;;
                load)
                    [ -f "${2:-}" ] || { printf 'plugin-dev.sh: no such file: %s\n' "${2:-}" >&2; exit 2; }
                    load_config
                    docker cp "$2" "$CONTAINER:/tmp/fa-dev-dataset.${2##*.}"
                    docker exec "$CONTAINER" fa-ci-dataset "/tmp/fa-dev-dataset.${2##*.}"
                    activate_all ;;
                shell) docker exec -it "$CONTAINER" mariadb fa_test ;;
                *) die "usage: plugin-dev.sh [--env NAME] db dump [file] | db load <file> | db shell" ;;
            esac ;;
        *) printf 'plugin-dev.sh: unknown command %s\n' "$CMD" >&2; exit 1 ;;
    esac
}
main "$@"
```

`docker/ci/dev/example.env`:

```sh
# A development environment's settings: copy to docker/ci/dev/<env>.env (the
# default env is "dev") and run docker/ci/plugin-dev.sh [--env <env>] up.
# FA_DEV_* variables set in your shell win over this file.

# Folders of modules/ to activate, in order (a module that needs another comes after it).
FA_DEV_MODULES="sgw_sales graphql"

# Apache's port on this machine.
FA_DEV_PORT=8100

# test, demo, or a .sql/.sql.gz backup. Loaded only when the environment is created.
FA_DEV_DATASET=demo

# A live site's installed_extensions.php, so a copy of its database keeps its
# users' access: the modules keep the extension ids it lists.
#FA_DEV_EXTENSIONS=~/backups/installed_extensions.php

# Themes (folders of this checkout's themes/) to mount.
#FA_DEV_THEMES=bootstrap

# Run each activated module's own tools/init.sh after activation (yes/no).
#FA_DEV_INIT=yes

# The folder mounted as modules/ (default: this checkout's modules/), and
# more mounts, e.g. a plugin checked out elsewhere over its folder:
#FA_DEV_MODULES_ROOT=/path/to/frontaccounting/modules
#FA_DEV_MOUNTS="/path/to/graphql-worktree:/var/www/html/modules/graphql"
```

In `.gitignore`, add:

```
/docker/ci/dev/*.env
!/docker/ci/dev/example.env
```

In `docker/ci/README.md`, add after the "Locally" section:

````markdown
## Development environments

`plugin-dev.sh` keeps FrontAccounting running between sessions from the same
image. It mounts your checkout's whole `modules/` folder, so edits are live on
the next request. Its database is on a volume, and it listens on a fixed port.
Which modules are extensions in it is opt-in, in `docker/ci/dev/<env>.env`:

    cp docker/ci/dev/example.env docker/ci/dev/dev.env    # then edit FA_DEV_MODULES
    docker/ci/plugin-dev.sh up          # create it, or start it again
    docker/ci/plugin-dev.sh link        # after changing FA_DEV_MODULES
    docker/ci/plugin-dev.sh status
    docker/ci/plugin-dev.sh shell
    docker/ci/plugin-dev.sh exec --dir modules/graphql composer test
    docker/ci/plugin-dev.sh mail list
    docker/ci/plugin-dev.sh down        # stop; the data stays
    docker/ci/plugin-dev.sh destroy --yes

`--env NAME` keeps several side by side, each with its own
`docker/ci/dev/NAME.env`, port and database. After activation, each module's
own `tools/init.sh` (if it has one) runs in its directory.

A copy of a real site: set `FA_DEV_DATASET` to its backup and
`FA_DEV_EXTENSIONS` to its `installed_extensions.php`. The modules then keep
the extension ids the site's security roles were built with. Set
`FA_DEV_INIT=no` to add nothing to the copy. Sign in as your own users, or
as `test`/`test`. Mail is caught (`mail list`), never sent.

`db dump [file]` writes the database out. `db load <file>` replaces it and
activates the modules again, so their install SQL runs on the new data.
`activate` does that without a load, e.g. after fixing whatever stopped an
activation.
````

Run: `chmod +x docker/ci/plugin-dev.sh`.

- [ ] **Step 4: Run the tests**

Run: `FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/dev.sh`
Expected: `0 failed`. If "a busy port is reported" fails because `ss` isn't on the host, keep the check. Detect docker's `port is already allocated` in the failed `docker run` instead: in `cmd_up`, run `ci_boot` with its output captured, and on that message die with `port N is already in use`, having removed the half-made container and its fresh volume. Say so in the report.

Then, once: `FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/run.sh`
Expected: `all passed`.

Run: `docker run --rm -v "$PWD":/mnt -w /mnt koalaman/shellcheck:stable -x docker/ci/plugin-dev.sh docker/ci/test/dev.sh docker/ci/test/run.sh`
Expected: clean. Targeted disables are fine where a single-quoted string is deliberately passed into the container.

- [ ] **Step 5: Commit**

```bash
git add docker/ci/plugin-dev.sh docker/ci/dev/example.env docker/ci/test/dev.sh docker/ci/test/run.sh docker/ci/README.md .gitignore
git update-index --chmod=+x docker/ci/plugin-dev.sh docker/ci/test/dev.sh
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "ci: plugin-dev.sh, persistent development environments

The checkout's modules/ folder is mounted whole, so edits are live; which of
its folders are extensions is opt-in (FA_DEV_MODULES, per environment in
docker/ci/dev/<env>.env), applied with link without recreating anything.
Databases persist on a volume; backups and a live site's extension ids load
a copy of that site; db dump/load, mail, shell and exec.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: graphql moves onto the dev mode

**Files (graphql worktree):**
- Create: `tools/init.sh`, `tools/dev-fixtures.sh`
- Move: `docker/fixtures.php` → `tools/fixtures.php` (with its default URL changed)
- Modify: `tools/ci.sh` (config and seed through `tools/init.sh`)
- Delete: `docker/` (whole directory)
- Modify: `README.md` (the development section), `.gitignore` (drop `docker/.env`), `.github/workflows/ci.yml` (drop the comment that says `docker/fa-graphql` stays)

**Interfaces:**
- Consumes (Tasks 1-2): `plugin-dev.sh` (`FA_DEV_*`, `up`, `exec --dir`, `mail`, `db dump`, `destroy --yes`, the `tools/init.sh` convention) and `plugin-test.sh`, from `$FA_CI`, with the image `fa-ci:local-cp-7.4`.
- Produces:
  - `tools/init.sh`: writes `config_graphql.php` if it's absent, then runs `tests/data/seed.sh`. It's the dev convention's init and is also used by `tools/ci.sh`.
  - `tools/dev-fixtures.sh`: `tests/data/dev-fixtures.sql`, then `php tools/fixtures.php`.

- [ ] **Step 1: The scripts**

`tools/init.sh`:

```sh
#!/bin/sh
# Prepares this module in the FrontAccounting CI image after activation: a
# config_graphql.php if there is none (a random secret, insecure login allowed,
# debug on — never for production), and the users and roles the tests and the
# dev fixtures sign in as (tests/data/seed.sh). Run by tools/ci.sh, and by the
# CI package's development environments after they activate this module.
set -eu
: "${FA_ROOT:?run this inside the FrontAccounting CI image (docker/ci)}"
here="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -f "$here/config_graphql.php" ]; then
    secret="$(php -r 'echo bin2hex(random_bytes(24));')"
    printf "<?php\n\n/* Written by tools/init.sh for the CI image. Not for production:\n\tsee config_graphql.example.php. */\n\nreturn array(\n    'secret' => '%s',\n    'allow_insecure_login' => true,\n    'debug' => true,\n);\n" \
        "$secret" > "$here/config_graphql.php"
    echo "wrote config_graphql.php"
fi
sh "$here/tests/data/seed.sh"
```

`tools/dev-fixtures.sh`:

```sh
#!/bin/sh
# Example hosting-billing data for a development environment: the HDOM/HGEN1
# items and prices (tests/data/dev-fixtures.sql), then a reseller customer, its
# recurring orders, an invoice and a payment created through the GraphQL API
# itself (tools/fixtures.php). Idempotent. From the FrontAccounting checkout:
#   docker/ci/plugin-dev.sh --env graphql exec --dir modules/graphql sh tools/dev-fixtures.sh
set -eu
: "${FA_ROOT:?run this inside the FrontAccounting CI image (plugin-dev.sh exec)}"
here="$(cd "$(dirname "$0")/.." && pwd)"
mariadb -h "$FA_DB_HOST" -u "$FA_DB_USER" -p"$FA_DB_PASSWORD" "$FA_DB_NAME" < "$here/tests/data/dev-fixtures.sql"
echo "loaded tests/data/dev-fixtures.sql"
php "$here/tools/fixtures.php" "${FA_URL%/}/modules/graphql/"
```

Run: `git mv docker/fixtures.php tools/fixtures.php`. In `tools/fixtures.php`:
- change the default URL line to `$url = $argv[1] ?? (getenv('FA_GRAPHQL_URL') ?: rtrim((string) (getenv('FA_URL') ?: 'http://localhost'), '/') . '/modules/graphql/');`;
- change its header comment to say it's run by `tools/dev-fixtures.sh` in a development environment (`docker/ci/plugin-dev.sh` in cambell-prince/frontaccounting). Drop the sentence about `.htaccess` and `docker/`.

Check that `.htaccess` stops `tools/` from being served. If it doesn't, add a deny rule for `tools/` the way `docker/` was denied.

In `tools/ci.sh`, replace the block from `echo "==> config and seed"` through `sh tests/data/seed.sh` with:

```sh
echo "==> config and seed"
sh tools/init.sh
```

Run: `chmod +x tools/init.sh tools/dev-fixtures.sh`.

- [ ] **Step 2: CI still passes (regression guard for the `tools/ci.sh` change)**

From the graphql worktree:

```bash
export COMPOSER_CACHE_DIR="$HOME/.cache/composer"
FA_CI_IMAGE=fa-ci:local-cp-7.4 "$FA_CI/plugin-test.sh" --dataset demo \
  --setup 'composer install --no-interaction --no-progress' \
  --with sgw_sales=https://github.com/saygoweb/frontaccounting-module-sgw_sales.git@master \
  . -- sh tools/ci.sh; echo "exit=$?"
```

Expected: `Tests: 966, ... Skipped: 1.`, `OK (66 tests`, `OK (1 test`, `==> all checks passed`, `exit=0`.

- [ ] **Step 3: The dev environment works end to end**

This uses the user's own `modules/` folder (`/home/cambell/src/sgw/frontaccounting/modules`, where `sgw_sales` is checked out with its `vendor/`), with this worktree mounted over its `graphql` folder, a spare port and a throwaway env name. It never touches the user's `docker/ci/dev/*.env` or their running graphql stack.

```bash
TMP_A=$(mktemp -d)
WT=/home/cambell/src/sgw/frontaccounting/.claude/worktrees/graphql-dev
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
export FA_DEV_IMAGE=fa-ci:local-cp-7.4 FA_DEV_PORT="$PORT" FA_DEV_DATASET=demo \
       FA_DEV_MODULES="sgw_sales graphql" \
       FA_DEV_MODULES_ROOT=/home/cambell/src/sgw/frontaccounting/modules \
       FA_DEV_MOUNTS="$WT:/var/www/html/modules/graphql"
"$FA_CI/plugin-dev.sh" --env gqlcheck --config /dev/null up
"$FA_CI/plugin-dev.sh" --env gqlcheck exec --dir modules/graphql sh tools/dev-fixtures.sh
curl -fsS -H 'Content-Type: application/json' \
  --data '{"query":"mutation { login(user: \"apitest\", password: \"password\") { accessToken } }"}' \
  "http://localhost:$PORT/modules/graphql/" | head -c 300; echo
"$FA_CI/plugin-dev.sh" --env gqlcheck db dump "$TMP_A/gql.sql.gz"
"$FA_CI/plugin-dev.sh" --env gqlcheck destroy --yes
rm -rf "$TMP_A"
```

Expected:
- `up` shows `init: graphql (tools/init.sh)` and `seeded: graphql is extension 2`, and ends with the URL.
- The fixtures report the example reseller customer, its orders, the invoice and the payment.
- The `login` mutation returns an `accessToken`. If the schema's login mutation has another shape, check `README.md` for the right one.
- The dump exists, and destroy leaves no `fa-dev-gqlcheck` container or volume.

If `vendor/` is missing in the worktree, Step 2's `--setup` installed it; run Step 2 first. If the worktree's `config_graphql.php` has `allow_insecure_login` false, delete it; it's gitignored and `tools/init.sh` rewrites it.

- [ ] **Step 4: Delete `docker/` and update the docs**

Run: `git rm -r -q docker`, then `git grep -n 'fa-graphql\|docker/'` and update each hit:
- `README.md`: replace the development section (`docker/fa-graphql init/up/test/...`, the `db fixtures` and `composer` notes, the anorm-graphql co-development recipe, and the `docker/` row of the layout table) with:

````markdown
## Development

Develop in a development environment of FrontAccounting's CI package
(`docker/ci/plugin-dev.sh` in the FrontAccounting checkout this module lives
in, as `modules/graphql`). It mounts that checkout's `modules/` folder, so
edits here are live, and keeps FrontAccounting with this module and sgw_sales
on `http://localhost:8100/`, the endpoint saygoweb.com-my's `FA_ENDPOINT`
uses. Its settings are in the FrontAccounting checkout, in
`docker/ci/dev/graphql.env`:

    FA_DEV_MODULES="sgw_sales graphql"
    FA_DEV_PORT=8100
    FA_DEV_DATASET=demo

Then, from the FrontAccounting checkout:

    docker/ci/plugin-dev.sh --env graphql up        # config_graphql.php and the API users via tools/init.sh
    docker/ci/plugin-dev.sh --env graphql exec --dir modules/graphql sh tools/dev-fixtures.sh
    docker/ci/plugin-dev.sh --env graphql exec --dir modules/graphql composer test
    docker/ci/plugin-dev.sh --env graphql mail list
    docker/ci/plugin-dev.sh --env graphql shell

`http://localhost:8100/modules/graphql/` in a browser shows Voyager. Sign in to
FrontAccounting as admin/password or test/test. The API users are apitest,
noapi and apiorders (password `password`).

Anorm's generator runs against the environment's database:

    docker/ci/plugin-dev.sh --env graphql exec --dir modules/graphql 'php vendor/bin/anorm.php --host=localhost --user=fa --password=fa make fa_test <table> -p ...'

To work on anorm-graphql at the same time, add its checkout to
`FA_DEV_MOUNTS` (`/path/to/anorm-graphql:/opt/anorm-graphql`) when you create
the environment, then point composer at it (locally only, never committed):

    docker/ci/plugin-dev.sh --env graphql exec --dir modules/graphql 'composer config repositories.local "{\"type\": \"path\", \"url\": \"/opt/anorm-graphql\", \"options\": {\"symlink\": true}}" && composer update saygoweb/anorm-graphql'

Before committing, run `composer config --unset repositories.local` and
`composer update saygoweb/anorm-graphql`, so `composer.lock` names the
released version again.
````

- `.gitignore`: remove the `docker/.env` line.
- `.github/workflows/ci.yml`: remove the comment line saying `docker/fa-graphql` stays the development stack.
- Anything else naming `docker/fa-graphql` (phpunit configs, tests, `composer.json` script descriptions): point it at the dev environment or `tools/`, or drop the reference.

Run: `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:latest -color .github/workflows/ci.yml`
Expected: nothing, or only the remote-workflow note.

- [ ] **Step 5: Commit**

```bash
git add -A tools docker README.md .gitignore .github/workflows/ci.yml .htaccess
git update-index --chmod=+x tools/init.sh tools/dev-fixtures.sh
git status --short
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "dev: Develop in the FrontAccounting CI package's dev environments

tools/init.sh (config and seed, shared with tools/ci.sh and run by the dev
environments after activation) and tools/dev-fixtures.sh replace
docker/fa-graphql's setup and db fixtures. The package's plugin-dev.sh gives
the persistent environment, with this checkout mounted live, on port 8100
where saygoweb.com-my points. docker/ is gone.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Wave 4 (controller): publish, adopt, move the user's dev data

- [ ] FA fork:
  1. Run `docker/ci/test/run.sh` on the cp 7.4 image.
  2. Push `feature/ci-dev` and open a PR to `master-cp` (`--repo cambell-prince/frontaccounting`).
  3. Wait for CI (four builds with smoke tests, now including dev.sh).
  4. Merge when the user says, then wait for master-cp to republish.
- [ ] graphql:
  1. Push `dev/fa-ci-dev` and open a PR.
  2. Wait for CI (the four matrix jobs at spec §5's counts).
  3. Merge when the user says.
- [ ] The user's graphql dev stack (`fa-graphql-graphql-*`, on port 8100) must go before the new environment can take 8100. **Ask first.** Then:
  1. Dump its database:

     ```
     docker exec fa-graphql-graphql-db-1 sh -c 'mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" fa_graphql' | gzip > ~/fa-graphql-dev.sql.gz
     ```

  2. Remove its containers and volume.
  3. Write the user's `docker/ci/dev/graphql.env` in their FA checkout:
     - `FA_DEV_MODULES="sgw_sales graphql"`
     - `FA_DEV_PORT=8100`
     - `FA_DEV_DATASET=~/fa-graphql-dev.sql.gz`
     - `FA_DEV_EXTENSIONS=` a file giving graphql id 1 and sgw_sales id 2, as the old stack registered them, so the dump's roles still match
  4. Run `docker/ci/plugin-dev.sh --env graphql up`.
  5. Confirm the example reseller and its orders are there and the saygoweb.com-my client reaches it.
