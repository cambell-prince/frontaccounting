# FrontAccounting CI Package: Development Environments (plan 3A)

> **For agentic workers:** REQUIRED SUB-SKILL: Use cjp:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task, wave by wave per the Execution Schedule. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the package persistent development environments (`docker/ci/plugin-dev.sh`), so any plugin, or several together with a copy of a live database, can be run and browsed locally. Then retire graphql's own `docker/` stack onto it.

**Architecture:** `plugin-dev.sh` runs the same image as `plugin-test.sh`, but as a named container (`fa-dev-<env>`) with its database on a named volume and Apache on a fixed port. Both scripts share `--with` resolution, run-as-you, and activation through new functions in `lib.sh`. Three small in-image helpers support backups and live extension ids. graphql moves its config-and-seed and dev-fixture steps into `tools/`.

**Tech Stack:** bash/sh, Docker (named volumes, labels), MariaDB, PHP CLI helpers, the existing docker/ci test harness.

**Spec:** `docs/superpowers/specs/2026-09-28-fa-ci-package-design.md` (§6; §1-§5 for context)

## Global Constraints

- Container `fa-dev-<env>`, volume `fa-dev-<env>-db` mounted at `/var/lib/mysql`, Apache published on `127.0.0.1:<port>`, default port 8100.
- `<env>` defaults to the module name of the plugin checkout given to `up`, else of the current directory, else `fa`.
- Clones of `--with NAME=REPO@REF` persist under `${XDG_CACHE_HOME:-$HOME/.cache}/fa-ci/dev/<env>/<name>`.
- Container labels record the environment: `fa-dev.port`, `fa-dev.plugin` (module name or empty), `fa-dev.modules` (space-separated `name[:id]` in activation order), `fa-dev.init` (the `--init` command or empty).
- Datasets: `test` (the image's fa_test), `demo` (FA's demo company), or a host path to `.sql`/`.sql.gz`. A file is loaded as it is, plus the `test`/`test` login on role 2. It loads only when the volume is new.
- Commands inside the environment run as the host uid:gid with group www-data (33), `umask 002`, `HOME=/tmp`, like `plugin-test.sh`.
- `destroy` refuses without `--yes`.
- If creation fails once the container exists, the environment stays for inspection.
- `plugin-test.sh`'s behaviour and its test suite (`docker/ci/test/driver.sh`) must not change, apart from sharing code through `lib.sh`.
- Every repo has `core.fileMode=false`. Record executable modes with `git update-index --chmod=+x <file>` after `git add`.
- Name scratch directories for what they are (`TMP_A=$(mktemp -d)`). Never assign one to `HOME`. Tests set `XDG_CACHE_HOME` to a scratch dir, so a user's real cache is never touched.
- The machine thermally throttles, so run one docker build or suite at a time.
- Commit as `git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit ...` with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

- `up` on an environment that already exists must start it and leave its database alone, even if a `--dataset` is passed. Test: Task 2, "up again keeps the data".
- A port that is already taken must fail with a clear message that names the port, not a raw docker error. Test: Task 2, "a busy port is reported".
- `--extensions` naming a module that isn't provided, or a provided module it doesn't name, must neither fail nor shift the ids of the listed modules. Test: Task 3, "unlisted modules come after, listed ids hold".
- `db load` of a backup must leave the environment's modules active again, because the load replaced their tables. Test: Task 3, "db load re-activates".
- `destroy --yes` must remove the container, the volume and the clone directory, and nothing else. Other environments stay. Test: Task 2, "destroy removes only this environment".

## Execution Schedule

| Wave | Tasks | Model | Notes |
|------|-------|-------|-------|
| 1 | Task 1 | sonnet | Shared `lib.sh` functions (with `plugin-test.sh` switched onto them) and the in-image helpers. Complete code given. |
| 2 | Task 2 | opus | `plugin-dev.sh` core. Judgment around docker lifecycle and failure handling. |
| 3 | Task 3 | sonnet | `plugin-dev.sh` data commands and the README. Same file as Task 2, so a later wave. |
| CP1 | — | — | plan base..end of wave 3: code-review medium + spec check (spec §6, package part). Must finish before wave 4, which builds on the contract. |
| 4 | Task 4 | opus | graphql moves onto the dev mode (graphql repo). |
| CP2 | — | — | plan base..end of wave 4 in both repos: code-review medium + spec check (full §6). |
| 5 | Controller | — | FA PR, CI, merge when the user says, then republish. graphql PR, CI, merge when the user says. Then help the user move their dev data and stop the old stack. |

Worktrees:
- FA fork: `/home/cambell/src/sgw/frontaccounting/.claude/worktrees/ci-dev`, branch `feature/ci-dev` from `origin/master-cp`. This is where this plan lives.
- graphql: `/home/cambell/src/sgw/frontaccounting/.claude/worktrees/graphql-dev`, branch `dev/fa-ci-dev` from `origin/main`. The controller creates it before wave 4.

`$FA_CI` below means `/home/cambell/src/sgw/frontaccounting/.claude/worktrees/ci-dev/docker/ci`. The local test image is `fa-ci:local-cp-7.4`, rebuilt from the FA worktree with `docker/ci/build-image.sh cp 7.4 fa-ci:local-cp-7.4` whenever `docker/ci/image/*` or the Dockerfile changes.

---

### Task 1: Shared functions and in-image helpers

**Files (FA worktree):**
- Modify: `docker/ci/lib.sh` (add `ci_with_resolve`, `ci_as_user`, `ci_activate`)
- Modify: `docker/ci/plugin-test.sh` (use them; behaviour unchanged)
- Modify: `docker/ci/image/fa-ci-register` (`--id N`)
- Modify: `docker/ci/image/fa-ci-dataset` (a file path as the dataset)
- Create: `docker/ci/image/fa-ci-ext-list`
- Test: `docker/ci/test/attach.sh`, `docker/ci/test/image.sh`; `docker/ci/test/driver.sh` unchanged, as the regression guard

**Interfaces:**
- Consumes: the merged package (plan 2): `log`, `die`, `ci_boot`, `ci_diagnostics`, `fa_ci_image`, `module_name` in `lib.sh`, plus the image helpers.
- Produces:
  - `ci_with_resolve <work-dir> <reserved-name> <spec>...` sets the global arrays `CI_WITH_NAMES`, `CI_WITH_PATHS` and `CI_WITH_CLONED`. It reuses an existing clone at `<work-dir>/<name>` if one is there.
  - `ci_as_user <container> <dir> <command>` runs `sh -c` as the caller. It passes `COMPOSER_CACHE_DIR=/tmp/composer-cache` when `CI_COMPOSER_CACHE=yes`.
  - `ci_activate <container> <module[:id]>...` registers each module (with the id when given) and activates it, in order, then runs `fa-ci-grant`.
  - `fa-ci-register [--id N] <name> <path>` prints `registered <name> as extension <id>`. It exits 1 with `extension <N> is <other>` if the id is taken by another module, and with `<name> is extension <M>, not <N>` if the module is already registered under a different id.
  - `fa-ci-dataset <test|demo|/abs/path.sql[.gz]>`: a file is loaded as it is, plus the `test` login.
  - `fa-ci-ext-list <file>` prints `<id> <package>` for each `'type' => 'extension'` entry, in the file's order.

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
Expected: the new checks FAIL: `--id` is taken as the module name, `fa-ci-ext-list` is not found, and the dataset file is refused as an unknown dataset.

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

Change `save_extensions("$root/installed_extensions.php", $global, $id + 1);` to:

```php
save_extensions("$root/installed_extensions.php", $global, max((int) $next, $id + 1));
```

Update the header comment: document `--id N`, which registers under that id (a live site's), refuses an id another module holds, and moves `$next_extension_id` past it.

`docker/ci/image/fa-ci-dataset`: change the usage lines and the `case`:

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
```

```sh
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

Wrap the existing fiscal-year loop and its `f_year` update in `if [ "$extend_years" = yes ]; then ... fi`. Keep the `test` user insert unconditional. Keep the final message, printing `dataset $src loaded`.

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

Run: `chmod +x docker/ci/image/fa-ci-ext-list`.

- [ ] **Step 4: The shared functions in `lib.sh`**

Append to `docker/ci/lib.sh`:

```bash
# ci_with_resolve <work-dir> <reserved-name> <spec>...
#
# Resolves --with specs, NAME=PATH (a local checkout, used as it is) or
# NAME=REPO@REF (cloned into <work-dir>/<name>; the ref is the part after the
# last @; an existing clone there is reused). Sets the global arrays
# CI_WITH_NAMES, CI_WITH_PATHS (absolute) and CI_WITH_CLONED (the names that
# were cloned). Dies on a malformed spec or one naming <reserved-name>.
ci_with_resolve() {
    local work="$1" reserved="$2" spec dep src repo ref path
    shift 2
    CI_WITH_NAMES=()
    CI_WITH_PATHS=()
    CI_WITH_CLONED=()
    for spec in "$@"; do
        dep="${spec%%=*}"
        src="${spec#*=}"
        [ -n "$dep" ] && [ "$dep" != "$spec" ] && [ -n "$src" ] \
            || die "--with takes NAME=REPO@REF or NAME=PATH, not '$spec'"
        [ "$dep" != "$reserved" ] || die "--with $dep: $dep is the plugin under test"
        if [ -d "$src" ]; then
            path="$(cd "$src" && pwd)"
        else
            repo="${src%@*}"
            ref="${src##*@}"
            [ "$repo" != "$src" ] && [ -n "$ref" ] || die "--with $spec: not a directory, and no @REF"
            path="$work/$dep"
            if [ -d "$path/.git" ]; then
                log "using the existing clone of $dep in $path"
            else
                log "cloning $dep: $repo @ $ref"
                git clone --quiet --depth 1 --branch "$ref" "$repo" "$path"
            fi
            CI_WITH_CLONED+=("$dep")
        fi
        CI_WITH_NAMES+=("$dep")
        CI_WITH_PATHS+=("$path")
    done
}

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
- Replace the block from `run_args=(-v "$CHECKOUT:$FA/modules/$NAME")` through the `done` that ends the `--with` loop with:

```bash
ci_with_resolve "$WORK" "$NAME" "${WITH[@]+"${WITH[@]}"}"
run_args=(-v "$CHECKOUT:$FA/modules/$NAME")
for i in "${!CI_WITH_NAMES[@]}"; do
    run_args+=(-v "${CI_WITH_PATHS[$i]}:$FA/modules/${CI_WITH_NAMES[$i]}")
done
```

- Replace the `exec_env=(-e HOME=/tmp)` block (through its closing `fi`) with:

```bash
if [ -n "${COMPOSER_CACHE_DIR:-}" ]; then
    mkdir -p "$COMPOSER_CACHE_DIR"
    run_args+=(-v "$COMPOSER_CACHE_DIR:/tmp/composer-cache")
    CI_COMPOSER_CACHE=yes
fi
```

- Delete the local `as_user()` function. Replace each `as_user "<dir>" "<cmd>"` call with `ci_as_user "$CONTAINER" "<dir>" "<cmd>"`.
- Replace the loop `for dep in "${cloned[@]+"${cloned[@]}"}"; do` with `for dep in "${CI_WITH_CLONED[@]+"${CI_WITH_CLONED[@]}"}"; do`.
- Replace the activation block (`if [ "$ACTIVATE" = yes ]; then ... fi`) with:

```bash
if [ "$ACTIVATE" = yes ]; then
    ci_activate "$CONTAINER" "${CI_WITH_NAMES[@]+"${CI_WITH_NAMES[@]}"}" "$NAME"
fi
```

Remove the now-unused `deps` and `cloned` arrays.

- [ ] **Step 6: Run the tests**

Run, one at a time: `docker/ci/build-image.sh cp 7.4 fa-ci:local-cp-7.4 && FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/run.sh`
Expected: every section `0 failed`, `all passed`. driver.sh passing unchanged is the proof that the refactor kept `plugin-test.sh`'s behaviour.

Run: `docker run --rm -v "$PWD":/mnt -w /mnt koalaman/shellcheck:stable -x docker/ci/lib.sh docker/ci/plugin-test.sh docker/ci/image/fa-ci-ext-list docker/ci/image/fa-ci-dataset docker/ci/test/*.sh && php -l docker/ci/image/fa-ci-register`
Expected: clean, `No syntax errors detected`.

- [ ] **Step 7: Commit**

```bash
git add docker/ci
git update-index --chmod=+x docker/ci/image/fa-ci-ext-list
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "ci: Shared driver functions; ids and dump files for the helpers

lib.sh gains ci_with_resolve, ci_as_user and ci_activate, which
plugin-test.sh now uses and plugin-dev.sh will. fa-ci-register takes --id
(a live site's extension id), fa-ci-dataset loads a dump file as it is, and
fa-ci-ext-list reads the ids out of an installed_extensions.php.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `plugin-dev.sh` core: environments that persist

**Files (FA worktree):**
- Create: `docker/ci/plugin-dev.sh`
- Test: `docker/ci/test/dev.sh`
- Modify: `docker/ci/test/run.sh` (run dev.sh after driver.sh)

**Interfaces:**
- Consumes (Task 1): `ci_with_resolve`, `ci_as_user`, `ci_activate`, `ci_boot`, `ci_diagnostics`, `fa_ci_image`, `module_name`, `log`, `die`, and the in-image `fa-ci-dataset` (`test|demo`).
- Produces:

```
plugin-dev.sh [--env NAME] up [options] [<plugin-checkout>]
    options: --port N --image IMG --fa cp|upstream --php 7.4|8.3 --dataset test|demo
             --with NAME=REPO@REF|NAME=PATH (repeatable) --theme NAME=PATH (repeatable)
             --mount HOST:CONTAINER (repeatable) --setup CMD --init CMD --name NAME
plugin-dev.sh [--env NAME] down | destroy --yes | status | url | shell | exec <cmd> | logs [app|errors]
```

  Task 3 adds `--dataset <file>`, `--extensions`, `activate`, `db` and `mail`, extending the dispatcher here. Globals Task 3 relies on:
  - `ENV`, `CONTAINER` (`fa-dev-$ENV`), `VOLUME` (`fa-dev-$ENV-db`), `WORK` (the clone dir), `FA=/var/www/html`;
  - `label <key>` (reads `fa-dev.<key>` from the container);
  - `plugin_dir` (prints the plugin's directory in the container, or `$FA`);
  - `require_env` (dies if the container doesn't exist).

- [ ] **Step 1: Write the failing test**

`docker/ci/test/dev.sh`:

```bash
#!/usr/bin/env bash
#
# plugin-dev.sh end to end against the fixture modules: environments that
# persist, on their own port and volume, and go away completely on destroy.
#
#   FA_CI_IMAGE=<image> docker/ci/test/dev.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$here/../lib.sh"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"
: "${FA_CI_IMAGE:?set FA_CI_IMAGE to the image under test}"
export FA_CI_IMAGE

d="$here/../plugin-dev.sh"
fx="$here/fixtures/modules"
TMP_A="$(mktemp -d)"
export XDG_CACHE_HOME="$TMP_A/cache"
env_a="citest$$a"
env_b="citest$$b"
free_port() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
port_a="$(free_port)"
port_b="$(free_port)"
cleanup() {
    for e in "$env_a" "$env_b"; do
        docker rm -f "fa-dev-$e" >/dev/null 2>&1 || true
        docker volume rm "fa-dev-$e-db" >/dev/null 2>&1 || true
    done
    rm -rf "$TMP_A"
}
trap cleanup EXIT

sqlq() { "$d" --env "$env_a" exec "mariadb -h localhost -u fa -pfa -N fa_test -e \"$1\""; }

expect_status 0 "up creates an environment with a module and a dependency" \
    "$d" --env "$env_a" up --port "$port_a" --with "ci_alpha=$fx/ci_alpha" "$fx/ci_beta"
expect_contains "and prints its URL" "http://localhost:$port_a/" "$OUT"
expect_status 0 "FrontAccounting answers on the port" curl -fsS -o /dev/null "http://localhost:$port_a/index.php"
expect_status 0 "both modules are active" \
    "$d" --env "$env_a" exec 'php -r "include \"/var/www/html/company/0/installed_extensions.php\"; foreach (\$installed_extensions as \$e) echo \$e[\"package\"], \"=\", \$e[\"active\"] ? \"on\" : \"off\", \"\n\";"'
expect_contains "ci_alpha on" "ci_alpha=on" "$OUT"
expect_contains "ci_beta on" "ci_beta=on" "$OUT"
expect_status 0 "status says it is running" "$d" --env "$env_a" status
expect_contains "running" "running" "$OUT"
expect_status 0 "url prints the URL" "$d" --env "$env_a" url
expect_contains "the port" "http://localhost:$port_a/" "$OUT"
expect_status 0 "exec runs as the caller in the plugin directory" "$d" --env "$env_a" exec 'echo "uid=$(id -u) dir=$(pwd)"'
expect_contains "as the caller" "uid=$(id -u)" "$OUT"
expect_contains "in modules/ci_beta" "dir=/var/www/html/modules/ci_beta" "$OUT"

expect_status 0 "a row written to the database" sqlq "INSERT INTO 0_ci_alpha (marker) VALUES (CONCAT('kept', '-across-restarts'))"
expect_status 0 "down stops it" "$d" --env "$env_a" down
expect_status 0 "up again keeps the data (and ignores a dataset)" "$d" --env "$env_a" up --dataset demo
expect_contains "saying the options only apply at creation" "only apply when" "$OUT"
expect_status 0 "the row is still there" sqlq "SELECT marker FROM 0_ci_alpha"
expect_contains "kept" "kept-across-restarts" "$OUT"

expect_status 1 "a busy port is reported" "$d" --env "$env_b" up --port "$port_a" "$fx/ci_alpha"
expect_contains "naming the port" "port $port_a" "$OUT"
docker rm -f "fa-dev-$env_b" >/dev/null 2>&1 || true
docker volume rm "fa-dev-$env_b-db" >/dev/null 2>&1 || true

expect_status 0 "a second environment on its own port" "$d" --env "$env_b" up --port "$port_b" "$fx/ci_alpha"
expect_status 1 "destroy wants --yes" "$d" --env "$env_a" destroy
expect_contains "saying so" "--yes" "$OUT"
expect_status 0 "destroy --yes" "$d" --env "$env_a" destroy --yes
expect_status 0 "destroy removes only this environment" sh -c \
    "! docker inspect fa-dev-$env_a >/dev/null 2>&1 && ! docker volume inspect fa-dev-$env_a-db >/dev/null 2>&1 && docker inspect fa-dev-$env_b >/dev/null 2>&1 && test ! -e '$XDG_CACHE_HOME/fa-ci/dev/$env_a'"
expect_status 1 "an unknown command is refused" "$d" --env "$env_b" frobnicate
expect_status 0 "destroy the second" "$d" --env "$env_b" destroy --yes
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
#   docker/ci/plugin-dev.sh [--env NAME] up [options] [<plugin-checkout>]
#   docker/ci/plugin-dev.sh [--env NAME] down | destroy --yes | status | url
#   docker/ci/plugin-dev.sh [--env NAME] shell | exec <command> | logs [app|errors]
#
# An environment is a container, fa-dev-<env>, with its database on the volume
# fa-dev-<env>-db and Apache on 127.0.0.1:<port>. `up` creates it, or starts
# it again: options only apply when it is created (destroy to change them).
# <env> defaults to the module name of the plugin checkout (or of the current
# directory), else "fa".
#
# up options:
#   --port N               Apache's port on this machine (default 8100)
#   --image IMG | --fa cp|upstream --php 7.4|8.3   as plugin-test.sh
#   --dataset test|demo    the database it starts from (default: test)
#   --with NAME=REPO@REF   another module, cloned into the environment's cache
#   --with NAME=PATH       ... or a local checkout, mounted live
#   --theme NAME=PATH      a theme checkout, mounted at themes/NAME
#   --mount HOST:CONTAINER another bind mount
#   --setup CMD            run in the plugin directory before activation
#   --init CMD             run in the plugin directory after activation
#   --name NAME            the module name, for a checkout without hooks.php
#
# Commands run as your uid:gid, with group www-data added. Sign in as
# test/test (and admin/password on the demo dataset).

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

FA=/var/www/html
ENV=''
if [ "${1:-}" = --env ]; then ENV="$2"; shift 2; fi
[ "$#" -ge 1 ] || die "usage: plugin-dev.sh [--env NAME] up|down|destroy|status|url|shell|exec|logs ..."
CMD="$1"
shift

usage_up() { die "usage: plugin-dev.sh [--env NAME] up [--port N] [--image IMG|--fa F --php V] [--dataset D] [--with NAME=SRC]... [--theme NAME=PATH]... [--mount H:C]... [--setup CMD] [--init CMD] [--name NAME] [<plugin-checkout>]"; }

# The environment's name, and everything named after it.
set_env() {
    [ -n "$ENV" ] || ENV="$(module_name "${1:-$PWD}" || echo fa)"
    case "$ENV" in ''|*[!A-Za-z0-9_.-]*) die "--env takes letters, digits, '.', '_' and '-'" ;; esac
    CONTAINER="fa-dev-$ENV"
    VOLUME="fa-dev-$ENV-db"
    WORK="${XDG_CACHE_HOME:-$HOME/.cache}/fa-ci/dev/$ENV"
}

exists() { docker inspect "$CONTAINER" >/dev/null 2>&1; }
running() { [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = true ]; }
require_env() { exists || die "no environment '$ENV' ($CONTAINER); create it with: plugin-dev.sh --env $ENV up ..."; }
label() { docker inspect -f "{{index .Config.Labels \"fa-dev.$1\"}}" "$CONTAINER"; }
plugin_dir() { local p; p="$(label plugin)"; if [ -n "$p" ]; then echo "$FA/modules/$p"; else echo "$FA"; fi; }
url() { echo "http://localhost:$(label port)/"; }

report() {
    log "$ENV is up: $(url)"
    printf '  sign in as test/test%s\n' "$([ "$(label dataset)" = demo ] && echo ' or admin/password')" >&2
    printf '  modules: %s\n' "$(label modules)" >&2
    url
}

cmd_up() {
    local port=8100 image="${FA_CI_IMAGE:-}" flavour=cp php=7.4 dataset=test setup='' init='' name='' checkout=''
    local with=() themes=() mounts=() given=no
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --port) port="$2"; given=yes; shift 2 ;;
            --image) image="$2"; given=yes; shift 2 ;;
            --fa) flavour="$2"; given=yes; shift 2 ;;
            --php) php="$2"; given=yes; shift 2 ;;
            --dataset) dataset="$2"; given=yes; shift 2 ;;
            --with) with+=("$2"); given=yes; shift 2 ;;
            --theme) themes+=("$2"); given=yes; shift 2 ;;
            --mount) mounts+=("$2"); given=yes; shift 2 ;;
            --setup) setup="$2"; given=yes; shift 2 ;;
            --init) init="$2"; given=yes; shift 2 ;;
            --name) name="$2"; given=yes; shift 2 ;;
            -*) usage_up ;;
            *) [ -z "$checkout" ] || usage_up; [ -d "$1" ] || die "$1 is not a directory"; checkout="$(cd "$1" && pwd)"; given=yes; shift ;;
        esac
    done
    set_env "${checkout:-}"

    if exists; then
        [ "$given" = no ] || log "$CONTAINER exists: options only apply when it is created (destroy --yes to recreate)"
        running || { log "starting $CONTAINER"; docker start "$CONTAINER" >/dev/null; }
        docker exec "$CONTAINER" fa-ci-wait-ready 120 || { ci_diagnostics "$CONTAINER"; die "$CONTAINER did not become ready"; }
        report
        return
    fi

    case "$port" in ''|*[!0-9]*) die "--port takes a number" ;; esac
    case "$dataset" in test|demo) ;; *) die "--dataset is test or demo, not '$dataset'" ;; esac
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$port\$"; then
        die "port $port is already in use on this machine; pick another with --port"
    fi
    [ -n "$image" ] || image="$(fa_ci_image "$flavour" "$php")"
    if [ -n "$checkout" ] && [ -z "$name" ]; then
        name="$(module_name "$checkout")" || die "$checkout has no hooks.php declaring class hooks_<name>; pass --name"
    fi

    mkdir -p "$WORK"
    ci_with_resolve "$WORK" "${name:-}" "${with[@]+"${with[@]}"}"
    local run_args=(-p "127.0.0.1:$port:80" -v "$VOLUME:/var/lib/mysql")
    [ -z "$checkout" ] || run_args+=(-v "$checkout:$FA/modules/$name")
    local i spec tname tpath
    for i in "${!CI_WITH_NAMES[@]}"; do
        run_args+=(-v "${CI_WITH_PATHS[$i]}:$FA/modules/${CI_WITH_NAMES[$i]}")
    done
    for spec in "${themes[@]+"${themes[@]}"}"; do
        tname="${spec%%=*}"
        tpath="${spec#*=}"
        [ -n "$tname" ] && [ "$tname" != "$spec" ] && [ -d "$tpath" ] || die "--theme takes NAME=PATH to a theme checkout, not '$spec'"
        run_args+=(-v "$(cd "$tpath" && pwd):$FA/themes/$tname")
    done
    for spec in "${mounts[@]+"${mounts[@]}"}"; do run_args+=(-v "$spec"); done
    if [ -n "${COMPOSER_CACHE_DIR:-}" ]; then
        mkdir -p "$COMPOSER_CACHE_DIR"
        run_args+=(-v "$COMPOSER_CACHE_DIR:/tmp/composer-cache")
        CI_COMPOSER_CACHE=yes
    fi
    local modules=("${CI_WITH_NAMES[@]+"${CI_WITH_NAMES[@]}"}")
    [ -z "$name" ] || modules+=("$name")
    run_args+=(--label "fa-dev.port=$port" --label "fa-dev.plugin=$name" --label "fa-dev.dataset=$dataset"
               --label "fa-dev.modules=${modules[*]-}" --label "fa-dev.init=$init")

    local fresh=yes
    if docker volume inspect "$VOLUME" >/dev/null 2>&1; then
        fresh=no
        log "keeping the database already in $VOLUME"
    fi

    # From here on a failure keeps the environment for inspection.
    trap 'rc=$?; [ "$rc" -eq 0 ] || { [ "${CI_DIAGNOSED:-}" = yes ] || ci_diagnostics "$CONTAINER"; log "$CONTAINER kept for inspection: plugin-dev.sh --env $ENV shell | logs | destroy --yes"; }' EXIT
    ci_boot "$CONTAINER" "$image" "${run_args[@]}"
    if [ "$fresh" = yes ] && [ "$dataset" != test ]; then
        log "dataset: $dataset"
        docker exec "$CONTAINER" fa-ci-dataset "$dataset"
    fi
    local dep
    for dep in "${CI_WITH_CLONED[@]+"${CI_WITH_CLONED[@]}"}"; do
        log "composer install --no-dev: $dep"
        ci_as_user "$CONTAINER" "$FA/modules/$dep" '[ ! -f composer.json ] || composer install --no-dev --no-interaction --no-progress'
    done
    if [ -n "$setup" ]; then
        log "setup: $setup"
        ci_as_user "$CONTAINER" "$(plugin_dir)" "$setup"
    fi
    [ "${#modules[@]}" -eq 0 ] || ci_activate "$CONTAINER" "${modules[@]}"
    if [ -n "$init" ]; then
        log "init: $init"
        ci_as_user "$CONTAINER" "$(plugin_dir)" "$init"
    fi
    trap - EXIT
    report
}

main() {
    case "$CMD" in
        up) cmd_up "$@" ;;
        down) set_env; require_env; docker stop "$CONTAINER" >/dev/null; log "$CONTAINER stopped; its data stays" ;;
        destroy)
            set_env
            [ "${1:-}" = --yes ] || die "destroy removes $CONTAINER, its database ($VOLUME) and $WORK; run it with --yes"
            docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
            docker volume rm "$VOLUME" >/dev/null 2>&1 || true
            rm -rf "$WORK"
            log "$ENV destroyed" ;;
        status)
            set_env; require_env
            printf '%s: %s at %s\nmodules: %s\n' "$ENV" "$(running && echo running || echo stopped)" "$(url)" "$(label modules)" ;;
        url) set_env; require_env; url ;;
        shell)
            set_env; require_env
            docker exec -it -w "$(plugin_dir)" -e HOME=/tmp "$CONTAINER" \
                setpriv --reuid="$(id -u)" --regid="$(id -g)" --groups=33 bash ;;
        exec)
            set_env; require_env
            [ "$#" -ge 1 ] || die "usage: plugin-dev.sh [--env NAME] exec <command>"
            ci_as_user "$CONTAINER" "$(plugin_dir)" "$*" ;;
        logs)
            set_env; require_env
            case "${1:-errors}" in
                errors) docker exec "$CONTAINER" sh -c 'tail -n 100 /var/www/html/tmp/errors.log 2>/dev/null || echo "(no errors logged)"' ;;
                app) docker exec "$CONTAINER" sh -c 'tail -n 100 /var/log/apache2/error.log' ;;
                *) die "usage: plugin-dev.sh [--env NAME] logs [app|errors]" ;;
            esac ;;
        *) printf 'plugin-dev.sh: unknown command %s\n' "$CMD" >&2; exit 1 ;;
    esac
}
main "$@"
```

Run: `chmod +x docker/ci/plugin-dev.sh`.

- [ ] **Step 4: Run the test**

Run: `FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/dev.sh`
Expected: `0 failed`. If "a busy port is reported" fails because `ss` isn't on the host, keep the check and fall back to docker's own error. Detect `port is already allocated` in `docker run`'s output inside `ci_boot`'s failure path, and die with the same "port N is already in use" message. Say so in the report.

- [ ] **Step 5: Lint**

Run: `docker run --rm -v "$PWD":/mnt -w /mnt koalaman/shellcheck:stable -x docker/ci/plugin-dev.sh docker/ci/test/dev.sh docker/ci/test/run.sh`
Expected: clean. Targeted disables are fine where a single-quoted string is deliberately passed into the container.

- [ ] **Step 6: Commit**

```bash
git add docker/ci/plugin-dev.sh docker/ci/test/dev.sh docker/ci/test/run.sh
git update-index --chmod=+x docker/ci/plugin-dev.sh docker/ci/test/dev.sh
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "ci: plugin-dev.sh, persistent development environments

A named container with its database on a volume and Apache on a fixed port,
built from the CI image with the same --with/--setup as plugin-test.sh plus
themes and an --init step. up starts an existing environment again; destroy
--yes removes it, its volume and its clones.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `plugin-dev.sh` data: backups, live extension ids, db, mail

**Files (FA worktree):**
- Modify: `docker/ci/plugin-dev.sh`
- Modify: `docker/ci/README.md` (a "Development environments" section)
- Test: `docker/ci/test/dev.sh` (appended cases)

**Interfaces:**
- Consumes (Task 2): `cmd_up`, `set_env`, `require_env`, `label`, `plugin_dir`, `ENV`, `CONTAINER`, `VOLUME`, `WORK`, `FA`. (Task 1): `ci_activate`, `ci_as_user`, and the in-image `fa-ci-dataset <path>` and `fa-ci-ext-list`.
- Produces:
  - `up --dataset <host path>`;
  - `up --extensions <installed_extensions.php>`;
  - `activate`;
  - `db dump [file]`, `db load <file>`, `db shell`;
  - `mail list|show <file>|clear`.

- [ ] **Step 1: Write the failing tests**

Append to `docker/ci/test/dev.sh`, before `finish`:

```bash
env_c="citest$$c"
port_c="$(free_port)"
cat > "$TMP_A/live-extensions.php" <<'PHP'
<?php
$next_extension_id = 12;
$installed_extensions = array (
  7 => array ('package' => 'ci_beta', 'name' => 'ci_beta', 'version' => '-', 'available' => '', 'type' => 'extension', 'path' => 'modules/ci_beta', 'active' => true),
  5 => array ('package' => 'ci_alpha', 'name' => 'ci_alpha', 'version' => '-', 'available' => '', 'type' => 'extension', 'path' => 'modules/ci_alpha', 'active' => true),
  9 => array ('package' => 'not_here', 'name' => 'not_here', 'version' => '-', 'available' => '', 'type' => 'extension', 'path' => 'modules/not_here', 'active' => true),
);
PHP
cleanup_c() { docker rm -f "fa-dev-$env_c" >/dev/null 2>&1 || true; docker volume rm "fa-dev-$env_c-db" >/dev/null 2>&1 || true; }
trap 'cleanup_c; cleanup' EXIT

expect_status 0 "--extensions registers modules under a live site's ids" \
    "$d" --env "$env_c" up --port "$port_c" --extensions "$TMP_A/live-extensions.php" \
    --with "ci_alpha=$fx/ci_alpha" --with "ci_plain=$fx/ci_plain" "$fx/ci_beta"
expect_status 0 "unlisted modules come after, listed ids hold" "$d" --env "$env_c" exec \
    'for m in ci_alpha ci_beta ci_plain; do printf "%s=%s " "$m" "$(fa-ci-ext-id "$m")"; done'
expect_contains "ci_alpha keeps 5" "ci_alpha=5" "$OUT"
expect_contains "ci_beta keeps 7" "ci_beta=7" "$OUT"
expect_contains "ci_plain comes after the highest" "ci_plain=12" "$OUT"
expect_status 0 "the modules are recorded with their ids" "$d" --env "$env_c" status
expect_contains "ids in the label" "ci_alpha:5" "$OUT"

expect_status 0 "a row to find in the dump" "$d" --env "$env_c" exec \
    "mariadb -h localhost -u fa -pfa fa_test -e \"INSERT INTO 0_ci_alpha (marker) VALUES (CONCAT('in', '-the-dump'))\""
expect_status 0 "db dump writes a gzipped file" "$d" --env "$env_c" db dump "$TMP_A/dump.sql.gz"
expect_status 0 "that is a real dump" sh -c "gunzip -c '$TMP_A/dump.sql.gz' | grep -q 'in-the-dump'"
expect_status 0 "a row the load must remove" "$d" --env "$env_c" exec \
    "mariadb -h localhost -u fa -pfa fa_test -e \"INSERT INTO 0_ci_alpha (marker) VALUES (CONCAT('after', '-the-dump'))\""
expect_status 0 "db load" "$d" --env "$env_c" db load "$TMP_A/dump.sql.gz"
expect_status 0 "restores the dump" "$d" --env "$env_c" exec \
    "mariadb -h localhost -u fa -pfa -N fa_test -e 'SELECT marker FROM 0_ci_alpha'"
expect_contains "the dumped row" "in-the-dump" "$OUT"
expect_absent "not the later one" "after-the-dump" "$OUT"
expect_status 0 "db load re-activates" "$d" --env "$env_c" exec \
    'php -r "include \"/var/www/html/company/0/installed_extensions.php\"; foreach (\$installed_extensions as \$id => \$e) echo \$e[\"package\"], \"@\", \$id, \"=\", \$e[\"active\"] ? \"on\" : \"off\", \"\n\";"'
expect_contains "ci_alpha on at 5" "ci_alpha@5=on" "$OUT"

expect_status 0 "a mail is caught" "$d" --env "$env_c" exec \
    'php -r "mail(\"a@example.com\", \"dev mail \" . \"subject\", \"body\");"'
expect_status 0 "mail list shows it" "$d" --env "$env_c" mail list
expect_contains "an .eml" ".eml" "$OUT"
eml="$(printf '%s\n' "$OUT" | grep '\.eml$' | head -n 1)"
expect_status 0 "mail show prints it" "$d" --env "$env_c" mail show "$eml"
expect_contains "the subject" "dev mail subject" "$OUT"
expect_status 0 "mail clear" "$d" --env "$env_c" mail clear
expect_status 0 "leaves none" "$d" --env "$env_c" mail list
expect_contains "none" "(no mail)" "$OUT"
expect_status 0 "destroy it" "$d" --env "$env_c" destroy --yes

env_e="citest$$e"
port_e="$(free_port)"
expect_status 0 "--dataset <file> creates an environment from a backup" \
    "$d" --env "$env_e" up --port "$port_e" --dataset "$TMP_A/dump.sql.gz" --with "ci_alpha=$fx/ci_alpha"
expect_status 0 "with the backup's data" "$d" --env "$env_e" exec \
    "mariadb -h localhost -u fa -pfa -N fa_test -e 'SELECT marker FROM 0_ci_alpha'"
expect_contains "the dumped row" "in-the-dump" "$OUT"
expect_status 0 "destroy it" "$d" --env "$env_e" destroy --yes
expect_status 2 "a missing dataset file is refused before anything starts" \
    "$d" --env "$env_e" up --dataset "$TMP_A/nope.sql" --with "ci_alpha=$fx/ci_alpha"
expect_status 0 "and nothing was created" sh -c "! docker inspect fa-dev-$env_e >/dev/null 2>&1"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/dev.sh`
Expected: the Task 2 cases pass. The new cases FAIL from "--extensions registers modules…" (`usage:` on the unknown option).

- [ ] **Step 3: Implement**

In `docker/ci/plugin-dev.sh`:

1. Header: add to the up options

```bash
#   --dataset <file>       ... or a .sql/.sql.gz on this machine (a backup), loaded as it is
#   --extensions <file>    an installed_extensions.php (a live site's): its modules keep
#                          the extension ids it gives them, so a copy of that site's
#                          database keeps its users' access
```

and to the command synopsis:

```bash
#   docker/ci/plugin-dev.sh [--env NAME] activate | mail [list|show <file>|clear]
#   docker/ci/plugin-dev.sh [--env NAME] db dump [file] | db load <file> | db shell
```

2. In `cmd_up`'s option loop, add `--extensions) extensions="$2"; given=yes; shift 2 ;;` and declare `local extensions=''`.
3. Replace the dataset check with:

```bash
    local dataset_file=''
    case "$dataset" in
        test|demo) ;;
        *)
            [ -f "$dataset" ] || { printf 'plugin-dev.sh: no such dataset file: %s\n' "$dataset" >&2; exit 2; }
            dataset_file="$(cd "$(dirname "$dataset")" && pwd)/$(basename "$dataset")" ;;
    esac
    [ -z "$extensions" ] || [ -f "$extensions" ] || { printf 'plugin-dev.sh: no such file: %s\n' "$extensions" >&2; exit 2; }
```

4. After `ci_boot` and before the dataset step, order the modules by the extension list when one is given. Replace the lines building `modules` and the `fa-dev.modules` label with this, placed after `ci_boot`. The label then has to be written after boot, so drop `fa-dev.modules` from `run_args` and keep it in a file inside the container: `/var/lib/fa-dev/modules`.

```bash
    local modules=("${CI_WITH_NAMES[@]+"${CI_WITH_NAMES[@]}"}")
    [ -z "$name" ] || modules+=("$name")
    if [ -n "$extensions" ]; then
        docker cp "$extensions" "$CONTAINER:/tmp/fa-dev-extensions.php"
        # Ids from the site's list; activation keeps the --with order, because
        # modules depend on each other (sgw_sales on graphql's tables, say).
        local ordered=() listed id m
        listed="$(docker exec "$CONTAINER" fa-ci-ext-list /tmp/fa-dev-extensions.php)"
        for m in "${modules[@]}"; do
            id="$(printf '%s\n' "$listed" | awk -v m="$m" '$2 == m {print $1; exit}')"
            if [ -n "$id" ]; then ordered+=("$m:$id"); else ordered+=("$m"); fi
        done
        # Unlisted modules get ids after every id the site has used.
        local next
        next="$(docker exec "$CONTAINER" php -r '$next_extension_id = 1; $installed_extensions = array(); include "/tmp/fa-dev-extensions.php"; echo max((int) $next_extension_id, count($installed_extensions) ? max(array_keys($installed_extensions)) + 1 : 1);')"
        docker exec -u www-data "$CONTAINER" php -r '$f = $argv[1]; $s = file_get_contents($f); file_put_contents($f, preg_replace("/next_extension_id = \\d+/", "next_extension_id = " . $argv[2], $s));' "$FA/installed_extensions.php" "$next"
        modules=("${ordered[@]}")
    fi
    docker exec "$CONTAINER" sh -c "mkdir -p /var/lib/fa-dev && printf '%s\n' '${modules[*]-}' > /var/lib/fa-dev/modules"
```

5. Change the dataset step to load a file too:

```bash
    if [ "$fresh" = yes ] && [ -n "$dataset_file" ]; then
        log "dataset: $dataset_file"
        docker cp "$dataset_file" "$CONTAINER:/tmp/fa-dev-dataset.${dataset_file##*.}"
        docker exec "$CONTAINER" fa-ci-dataset "/tmp/fa-dev-dataset.${dataset_file##*.}"
    elif [ "$fresh" = yes ] && [ "$dataset" != test ]; then
        log "dataset: $dataset"
        docker exec "$CONTAINER" fa-ci-dataset "$dataset"
    fi
```

A `.sql.gz` copies as `fa-dev-dataset.gz`, which `fa-ci-dataset` gunzips because it ends in `.gz`. A `.sql` copies as `fa-dev-dataset.sql`.

6. Replace `label modules` wherever it's read (`report`, `status`) with a function:

```bash
modules() { docker exec "$CONTAINER" cat /var/lib/fa-dev/modules 2>/dev/null || true; }
```

`/var/lib/fa-dev` is in the container's filesystem, so it persists with the container and goes with `destroy`.

7. New commands in `main`:

```bash
        activate)
            set_env; require_env
            # shellcheck disable=SC2046 # the recorded list is space-separated names
            ci_activate "$CONTAINER" $(modules)
            if [ -n "$(label init)" ]; then log "init: $(label init)"; ci_as_user "$CONTAINER" "$(plugin_dir)" "$(label init)"; fi ;;
        db)
            set_env; require_env
            case "${1:-}" in
                dump)
                    local out="${2:-fa-dev-$ENV-$(date +%Y%m%d-%H%M%S).sql.gz}"
                    docker exec "$CONTAINER" sh -c 'mariadb-dump --single-transaction --routines fa_test | gzip -c' > "$out"
                    gzip -t "$out"
                    log "dumped to $out" ;;
                load)
                    [ -f "${2:-}" ] || { printf 'plugin-dev.sh: no such file: %s\n' "${2:-}" >&2; exit 2; }
                    local src="$2"
                    docker cp "$src" "$CONTAINER:/tmp/fa-dev-dataset.${src##*.}"
                    docker exec "$CONTAINER" fa-ci-dataset "/tmp/fa-dev-dataset.${src##*.}"
                    "$0" --env "$ENV" activate ;;
                shell) docker exec -it "$CONTAINER" mariadb fa_test ;;
                *) die "usage: plugin-dev.sh [--env NAME] db dump [file] | db load <file> | db shell" ;;
            esac ;;
        mail)
            set_env; require_env
            case "${1:-list}" in
                list) docker exec "$CONTAINER" sh -c 'cd /var/mail-catcher && ls -1t -- *.eml 2>/dev/null || echo "(no mail)"' ;;
                show) [ -n "${2:-}" ] || die "usage: plugin-dev.sh [--env NAME] mail show <file>"
                      docker exec "$CONTAINER" cat "/var/mail-catcher/$(basename "$2")" ;;
                clear) docker exec "$CONTAINER" sh -c 'rm -f /var/mail-catcher/*.eml' ;;
                *) die "usage: plugin-dev.sh [--env NAME] mail [list|show <file>|clear]" ;;
            esac ;;
```

Also add these commands to the top-level usage message.

8. Add to `docker/ci/README.md` a section after "Locally":

````markdown
## Development environments

`plugin-dev.sh` keeps an environment running between sessions: the same image,
with its database on a volume and FrontAccounting on a fixed port.

    ../frontaccounting/docker/ci/plugin-dev.sh up --dataset demo \
      --with sgw_sales=../sgw_sales --init 'sh tools/init.sh' .
    ../frontaccounting/docker/ci/plugin-dev.sh status      # from the plugin's directory
    ../frontaccounting/docker/ci/plugin-dev.sh shell
    ../frontaccounting/docker/ci/plugin-dev.sh mail list
    ../frontaccounting/docker/ci/plugin-dev.sh down        # stop; the data stays
    ../frontaccounting/docker/ci/plugin-dev.sh destroy --yes

`up` creates the environment the first time and starts it after that. Its
options only apply when it is created. The environment is named after the
plugin's module (`--env` to choose), and its URL is `http://localhost:8100/`
unless you pass `--port`. `--with NAME=PATH` modules and `--theme NAME=PATH`
themes are mounted live.

A copy of a real site: pass its backup as `--dataset site.sql.gz` and its
`installed_extensions.php` as `--extensions`. The modules then keep the
extension ids the site's security roles were built with. Sign in as your own
users, or as `test`/`test`. Mail is caught (`mail list`), never sent.

`db dump [file]` writes the database out. `db load <file>` replaces it and
activates the modules again. `activate` re-runs activation after you fix
something that stopped it.
````

- [ ] **Step 4: Run the tests**

Run: `FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/dev.sh`
Expected: `0 failed`.

Then, once: `FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/run.sh`
Expected: `all passed`.

Run: `docker run --rm -v "$PWD":/mnt -w /mnt koalaman/shellcheck:stable -x docker/ci/plugin-dev.sh docker/ci/test/dev.sh`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add docker/ci/plugin-dev.sh docker/ci/test/dev.sh docker/ci/README.md
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "ci: Backups, live extension ids, db and mail for dev environments

--dataset takes a backup file, loaded as it is; --extensions registers the
modules under a live site's extension ids so its users keep their access.
db dump/load/shell, mail list/show/clear, and activate to retry activation.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: graphql moves onto the dev mode

**Files (graphql worktree):**
- Create: `tools/init.sh`, `tools/dev-fixtures.sh`
- Move: `docker/fixtures.php` → `tools/fixtures.php` (with its default URL changed)
- Modify: `tools/ci.sh` (config and seed through `tools/init.sh`)
- Delete: `docker/` (whole directory)
- Modify: `README.md` (the development section), `.gitignore` (drop `docker/.env`), `.github/workflows/ci.yml` (drop the comment that says `docker/fa-graphql` stays)

**Interfaces:**
- Consumes (Tasks 1-3): `plugin-dev.sh` (`up --dataset demo --with --init --port`, `exec`, `mail`, `db dump`, `destroy --yes`) and `plugin-test.sh`, from `$FA_CI`, with the image `fa-ci:local-cp-7.4`.
- Produces:
  - `tools/init.sh`: writes `config_graphql.php` if it's absent, then runs `tests/data/seed.sh`. Used by `tools/ci.sh` and as the dev environment's `--init`.
  - `tools/dev-fixtures.sh`: `tests/data/dev-fixtures.sql`, then `php tools/fixtures.php`.

- [ ] **Step 1: The scripts**

`tools/init.sh`:

```sh
#!/bin/sh
# Prepares this module in the FrontAccounting CI image, after activation: a
# config_graphql.php if there is none (a random secret, insecure login allowed,
# debug on — never for production), and the users and roles the tests and the
# dev fixtures sign in as (tests/data/seed.sh). Used by tools/ci.sh and as the
# development environment's --init.
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
# itself (tools/fixtures.php). Idempotent. Run inside the environment:
#   ../frontaccounting/docker/ci/plugin-dev.sh exec sh tools/dev-fixtures.sh
set -eu
: "${FA_ROOT:?run this inside the FrontAccounting CI image (plugin-dev.sh exec)}"
here="$(cd "$(dirname "$0")/.." && pwd)"
mariadb -h "$FA_DB_HOST" -u "$FA_DB_USER" -p"$FA_DB_PASSWORD" "$FA_DB_NAME" < "$here/tests/data/dev-fixtures.sql"
echo "loaded tests/data/dev-fixtures.sql"
php "$here/tools/fixtures.php" "${FA_URL%/}/modules/graphql/"
```

Run: `git mv docker/fixtures.php tools/fixtures.php`. In `tools/fixtures.php`:
- change the default URL line to `$url = $argv[1] ?? (getenv('FA_GRAPHQL_URL') ?: rtrim((string) (getenv('FA_URL') ?: 'http://localhost'), '/') . '/modules/graphql/');`;
- update its header comment: "Run by tools/dev-fixtures.sh inside a development environment (docker/ci/plugin-dev.sh in cambell-prince/frontaccounting)". Drop the sentence about `.htaccess` and `docker/`. `tools/` is not served either: `.htaccess` routes everything through `index.php`. Check that `.htaccess` really denies `tools/`. If it doesn't, add a `tools/` deny rule to `.htaccess` the same way `docker/` was denied.

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

```bash
TMP_A=$(mktemp -d)
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
FA_CI_IMAGE=fa-ci:local-cp-7.4 "$FA_CI/plugin-dev.sh" --env gqlcheck up --port "$PORT" --dataset demo \
  --setup 'composer install --no-interaction --no-progress' \
  --with sgw_sales=https://github.com/saygoweb/frontaccounting-module-sgw_sales.git@master \
  --init 'sh tools/init.sh' .
"$FA_CI/plugin-dev.sh" --env gqlcheck exec sh tools/dev-fixtures.sh
curl -fsS -H 'Content-Type: application/json' \
  --data '{"query":"mutation { login(user: \"apitest\", password: \"password\") { accessToken } }"}' \
  "http://localhost:$PORT/modules/graphql/" | head -c 300; echo
"$FA_CI/plugin-dev.sh" --env gqlcheck db dump "$TMP_A/gql.sql.gz"
"$FA_CI/plugin-dev.sh" --env gqlcheck destroy --yes
rm -rf "$TMP_A"
```

Expected:
- `up` ends by printing the URL.
- The fixtures report the example reseller customer, its orders, the invoice and the payment.
- The `login` mutation returns an `accessToken`. If the schema's login mutation has another shape, check `README.md` for the right one and use it.
- The dump exists, and destroy leaves no `fa-dev-gqlcheck` container or volume.

If `config_graphql.php` in this worktree already has `allow_insecure_login` set to false, the login fails. It's written only when absent, so delete it first (it's gitignored).

- [ ] **Step 4: Delete `docker/` and update the docs**

Run: `git rm -r -q docker`, then `git grep -n 'fa-graphql\|docker/'` and update each hit:
- `README.md`: replace the development section (`docker/fa-graphql init/up/test/...`, the `db fixtures` and `composer` notes, the anorm-graphql co-development recipe, and the `docker/` row of the layout table) with:

````markdown
## Development

A development environment (FrontAccounting's CI package, `docker/ci/plugin-dev.sh`
in cambell-prince/frontaccounting, checked out beside this repository) keeps
FrontAccounting with this module and sgw_sales running on
`http://localhost:8100/`, the endpoint saygoweb.com-my's `FA_ENDPOINT` uses:

    ../frontaccounting/docker/ci/plugin-dev.sh up --dataset demo \
      --setup 'composer install --no-interaction --no-progress' \
      --with sgw_sales=../sgw_sales --init 'sh tools/init.sh' .
    ../frontaccounting/docker/ci/plugin-dev.sh exec sh tools/dev-fixtures.sh   # example reseller data
    ../frontaccounting/docker/ci/plugin-dev.sh exec composer test              # the suite, in the environment
    ../frontaccounting/docker/ci/plugin-dev.sh mail list                       # mail it caught
    ../frontaccounting/docker/ci/plugin-dev.sh shell

`http://localhost:8100/modules/graphql/` in a browser shows Voyager. Sign in to
FrontAccounting as admin/password or test/test. The API users are apitest,
noapi and apiorders (password `password`).

Anorm's generator runs against the environment's database:

    ../frontaccounting/docker/ci/plugin-dev.sh exec 'php vendor/bin/anorm.php --host=localhost --user=fa --password=fa make fa_test <table> -p ...'

To work on anorm-graphql at the same time, mount its checkout and point
composer at it (locally only, never committed):

    ../frontaccounting/docker/ci/plugin-dev.sh up ... --mount "$(cd ../anorm-graphql && pwd):/opt/anorm-graphql" .
    ../frontaccounting/docker/ci/plugin-dev.sh exec 'composer config repositories.local "{\"type\": \"path\", \"url\": \"/opt/anorm-graphql\", \"options\": {\"symlink\": true}}" && composer update saygoweb/anorm-graphql'

Before committing, run `composer config --unset repositories.local` and
`composer update saygoweb/anorm-graphql`, so `composer.lock` names the
released version again.
````

- `.gitignore`: remove the `docker/.env` line.
- `.github/workflows/ci.yml`: remove the comment line saying `docker/fa-graphql` stays the development stack.
- Anything else that names `docker/fa-graphql` (`phpunit` configs, tests, `composer.json` script descriptions): point it at the dev mode or `tools/`, or drop the reference.

Run: `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:latest -color .github/workflows/ci.yml`
Expected: nothing, or only the note that the remote reusable workflow can't be fetched.

- [ ] **Step 5: Commit**

```bash
git add -A tools docker README.md .gitignore .github/workflows/ci.yml .htaccess
git update-index --chmod=+x tools/init.sh tools/dev-fixtures.sh
git status --short
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "dev: Develop in the FrontAccounting CI package's dev environments

tools/init.sh (config and seed, shared with tools/ci.sh) and
tools/dev-fixtures.sh replace docker/fa-graphql's setup and db fixtures; the
package's plugin-dev.sh gives the persistent environment on port 8100 that
saygoweb.com-my points at. docker/ is gone.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Wave 5 (controller): publish, adopt, move the user's dev data

- [ ] FA fork:
  1. Run `docker/ci/test/run.sh` on the cp 7.4 image.
  2. Push `feature/ci-dev` and open a PR to `master-cp` (`--repo cambell-prince/frontaccounting`).
  3. Wait for CI (four builds with smoke tests, now including dev.sh).
  4. Merge when the user says, then wait for master-cp to republish.
- [ ] graphql:
  1. Push `dev/fa-ci-dev` and open a PR.
  2. Wait for CI (the four matrix jobs at spec §5's counts).
  3. Merge when the user says.
- [ ] The user's current graphql dev stack (`fa-graphql-graphql-*`, on port 8100) must go before the new environment can take 8100. Ask first. Then:
  1. dump its database (`docker exec fa-graphql-graphql-db-1 sh -c 'mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" fa_graphql' | gzip > ~/fa-graphql-dev.sql.gz`, credentials as that stack set them);
  2. remove its containers and volume;
  3. `up` the new environment from the graphql checkout with `--dataset ~/fa-graphql-dev.sql.gz`, and the same modules, so the user keeps their dev data.

  graphql's old stack registered graphql as extension 1 and sgw_sales as 2. Pass an `--extensions` file with those ids so the dump's roles still match.
