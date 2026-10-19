# FrontAccounting CI Package Implementation Plan (plan 1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use cjp:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task, wave by wave per the Execution Schedule. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish prebuilt FrontAccounting test images, a driver script and a reusable GitHub workflow, so that a plugin's CI is one `uses:` line plus a test command. Prove it by giving sgw_import its first CI.

**Architecture:** `docker/ci/` in the FA fork builds one self-contained image per FA flavour (`cp`, `upstream`) × PHP (7.4, 8.3). Apache, PHP, MariaDB, FA and a seeded `fa_test` database are all in one container. `plugin-test.sh` mounts a plugin (and its `--with` dependencies) under `modules/` and activates each through FA's own Install/Activate form over HTTP. It then runs the plugin's test command as the caller's uid. `ci-image.yml` builds, smoke-tests (with this package's own test suite), pushes and prunes. `plugin-test.yml` is the `workflow_call` entry point for plugins.

**Tech Stack:** bash/sh, Docker buildx, Debian trixie + sury PHP 7.4/8.3, MariaDB, Apache mod_php, PHP CLI helpers, jq, GitHub Actions, GHCR.

**Spec:** `docs/superpowers/specs/2026-09-28-fa-ci-package-design.md`

**Plan 2 (not here):** moving sgw_sales, graphql and api onto the package with test-count parity (spec §4.3-4.5).

## Global Constraints

- Image name: `ghcr.io/cambell-prince/frontaccounting-ci`. Tags: `<flavour>-php<ver>`, `<flavour>-php<ver>-<sha7>`, `pr-<n>-<flavour>-php<ver>`. `<flavour>` ∈ {`cp`, `upstream`}, `<ver>` ∈ {`7.4`, `8.3`}.
- FA root in the image: `/var/www/html`. Database `fa_test`, user `fa`/`fa`, table prefix `0_`. FA login `test`/`test` (role 2, System Administrator).
- Helpers in the image: `/usr/local/lib/fa-ci/`, linked into `/usr/local/bin/`: `fa-ci-wait-ready`, `fa-ci-login`, `fa-ci-register`, `fa-ci-activate`, `fa-ci-grant`. CI-only page: `/var/www/html/fa-ci/grant.php`.
- Env in the image: `FA_ROOT=/var/www/html`, `FA_URL=http://localhost`, `FA_DB_HOST=localhost`, `FA_DB_NAME=fa_test`, `FA_DB_USER=fa`, `FA_DB_PASSWORD=fa`.
- Plugin commands run as the host uid:gid with supplementary group `www-data` (gid 33), `umask 002`, `HOME=/tmp`, via `setpriv` (`docker exec` has no `--group-add`).
- Always use `http://localhost`, never `127.0.0.1`. FA sets `SECURE_ONLY` session cookies, which curl sends over http only to `localhost`.
- Module registration mirrors FA's `write_extensions()`: `var_export`, `'version' => '-'` (passes `check_src_ext_version`), `'type' => 'extension'`, `'active' => false`.
- Package prune API: `/users/cambell-prince/packages/container/frontaccounting-ci/versions`. Keep the moving tags, and the newest 3 `-<sha7>` per flavour.
- Scripts: bash with `set -euo pipefail` on the host, POSIX sh with `set -eu` inside the image. Every script starts with a usage comment.
- Match the imscp package's conventions (`/home/cambell/src/sgw/imscp/docker/ci/`): `log`/`die` helpers, a `trap cleanup EXIT`, `--keep`, `COMPOSER_CACHE_DIR` mounting, the dry-run prune.

## Review Focus

- A plugin checkout path containing spaces. Mounts and `-w` must be quoted, so the run behaves as in a plain path. Test: Task 3, "path with a space".
- A `--with` source whose repo URL or path contains `@` (as `git@github.com:org/repo.git@main` does). The ref is the part after the **last** `@`. Test: Task 3, "`@` inside the repo path".
- `--with` naming the plugin under test, which would mount the same directory twice. It must fail up front with a clear message. Test: Task 3, "--with naming the plugin itself".
- A failing test command must remove its container and print FA's error log, with no containers left behind across the suite. Test: Task 3, "no container is left behind" (runs after the failing cases).
- A package version carrying a tag the prune doesn't know (`latest`, a hand-pushed tag) must never be deleted. Test: Task 4, fixture version 13 tagged `latest`.

## Execution Schedule

| Wave | Tasks | Model | Notes |
|------|-------|-------|-------|
| 1 | Task 1 | opus | The image, the shared `lib.sh`/`test/lib.sh`, `build-image.sh`. Most environmental risk (MariaDB seeded during a build step, sury, setpriv), so the most capable tier. Everything later builds on it. |
| 2 | Task 2, Task 4 | sonnet, sonnet | Parallel. Task 2 touches `image/*`, the Dockerfile, `test/attach.sh` and `test/fixtures/modules/*`; Task 4 touches `prune-images.sh`, `test/prune.sh` and `test/fixtures/prune/*`. Disjoint files, and Task 4 needs no docker daemon. |
| 3 | Task 3 | sonnet | The driver. Consumes Task 1's `lib.sh` and image and Task 2's helpers. |
| CP1 | — | — | base..end of wave 3: code-review medium + spec check (spec §1, §2). May run concurrently with wave 4, which touches none of these files. |
| 4 | Task 5, Task 6 | sonnet, sonnet | Parallel. Task 5 writes `smoke-test.sh`, `test/run.sh` and `ci-image.yml` and uses docker; Task 6 writes `plugin-test.yml` and `README.md` and uses only an actionlint container. Disjoint files. |
| 5 | Task 7 | sonnet | sgw_import adoption, in the sgw_import repo. Needs the local image (Tasks 1-3) and `plugin-test.yml` (Task 6). |
| CP2 | — | — | base..end of wave 5: code-review medium + spec check (full spec). |
| 6 | Controller | — | FA PR → CI green (pr- images smoke-tested) → squash merge → master-cp publish. The user makes the GHCR package public. Then the sgw_import PR → CI green → merge as the user asks. |

All FA-fork work happens in `/home/cambell/src/sgw/frontaccounting/.claude/worktrees/ci-package` on branch `feature/ci-package` (off `origin/master-cp`). Paths below are relative to it unless absolute.

---

### Task 1: The image, build script and shared test helpers

**Files:**
- Create: `docker/ci/lib.sh`
- Create: `docker/ci/build-image.sh`
- Create: `docker/ci/Dockerfile`
- Create: `docker/ci/image/entrypoint.sh`
- Create: `docker/ci/image/seed-db.sh`
- Create: `docker/ci/image/config_db.php`
- Create: `docker/ci/image/php.ini`
- Create: `docker/ci/image/apache-fa-ci.conf`
- Create: `docker/ci/image/fa-mail-catcher`
- Create: `docker/ci/image/fa-ci-wait-ready`
- Create: `docker/ci/image/fa-ci-login`
- Create: `docker/ci/test/lib.sh`
- Test: `docker/ci/test/image.sh`

**Interfaces:**
- Consumes: the fork's `modules/tests/data/fa_test.sql.gz` (fixture: user `test`, md5 password `test`, role 2).
- Produces:
  - `docker/ci/lib.sh` (sourced by bash):
    - `log <msg>` (stderr), `die <msg>`
    - `fa_ci_image <flavour> <php>`: prints the tag
    - `module_name <checkout>`: prints `<name>` from `class hooks_<name>`, returns 1 if none
    - `ci_boot <container> <image> [docker run args...]`: runs detached, then `fa-ci-wait-ready 120`; dies with diagnostics on failure
    - `ci_diagnostics <container>`: tails `tmp/errors.log` and Apache's error.log to stderr
  - `docker/ci/test/lib.sh`:
    - `pass <label>`, `fail <label> [detail]`
    - `expect_status <want> <label> <cmd...>`: sets `$OUT`
    - `expect_contains <label> <needle> <haystack>`, `expect_absent <label> <needle> <haystack>`
    - `finish`: returns non-zero if anything failed
  - `docker/ci/build-image.sh [--cache-gha] <cp|upstream> <php> <tag>...`
  - Image helpers `fa-ci-wait-ready [seconds]` and `fa-ci-login <cookie-jar>`.
  - Dockerfile conventions later tasks rely on:
    - it copies every `image/fa-ci-*` into `/usr/local/lib/fa-ci/` and links them into `/usr/local/bin/`, so new helpers only need adding under `image/`;
    - it creates an empty `/var/www/html/fa-ci/` directory;
    - PHP's `opcache.revalidate_freq=0`.
  - Local test image tag: `fa-ci:local-cp-7.4`.

- [ ] **Step 1: Write the shared shell library**

`docker/ci/lib.sh`:

```bash
# Shared by the docker/ci scripts. Sourced, not run.

log() { printf '\n\033[36m==>\033[0m %s\n' "$*" >&2; }
die() { printf '%s: %s\n' "$(basename "$0")" "$*" >&2; exit 1; }

# fa_ci_image <flavour> <php>: the published image for a FrontAccounting
# flavour (cp or upstream) and PHP version.
fa_ci_image() { printf 'ghcr.io/cambell-prince/frontaccounting-ci:%s-php%s\n' "$1" "$2"; }

# module_name <checkout>: the FrontAccounting module name, from the
# `class hooks_<name>` its hooks.php declares. FA requires the directory under
# modules/ to be that name, whatever the repository is called.
module_name() {
    local name
    name="$(sed -n 's/^[[:space:]]*class[[:space:]]\{1,\}hooks_\([A-Za-z0-9_]\{1,\}\).*/\1/p' \
        "$1/hooks.php" 2>/dev/null | head -n 1)"
    [ -n "$name" ] && printf '%s\n' "$name"
}

# ci_diagnostics <container>: what FrontAccounting and Apache logged, for a
# failed run.
ci_diagnostics() {
    printf '\n--- FrontAccounting tmp/errors.log\n' >&2
    docker exec "$1" sh -c 'tail -n 60 /var/www/html/tmp/errors.log 2>/dev/null' >&2 || true
    printf '\n--- Apache error.log\n' >&2
    docker exec "$1" sh -c 'tail -n 60 /var/log/apache2/error.log 2>/dev/null' >&2 || true
}

# ci_boot <container> <image> [docker run args...]: start the image and wait
# until MariaDB answers and FrontAccounting serves its login page.
ci_boot() {
    local container="$1" image="$2"
    shift 2
    log "booting $image"
    docker run -d --name "$container" "$@" "$image" >/dev/null
    if ! docker exec "$container" fa-ci-wait-ready 120; then
        ci_diagnostics "$container"
        die "$image did not become ready"
    fi
}
```

- [ ] **Step 2: Write the test helpers**

`docker/ci/test/lib.sh`:

```bash
# Assertions for the docker/ci tests. Sourced, not run.

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
fail() {
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n' "$1"
    [ -z "${2:-}" ] || printf '%s\n' "$2" | tail -n 40 | sed 's/^/        /'
}

# expect_status <want> <label> <command...>: run the command, compare its exit
# status. Its combined output is left in $OUT for the checks that follow.
expect_status() {
    local want="$1" label="$2" got
    shift 2
    set +e
    OUT="$("$@" 2>&1)"
    got=$?
    set -e
    if [ "$got" -eq "$want" ]; then pass "$label"; else fail "$label (exit $got, wanted $want)" "$OUT"; fi
}

# expect_contains <label> <needle> <haystack>
expect_contains() {
    case "$3" in *"$2"*) pass "$1" ;; *) fail "$1 (no '$2')" "$3" ;; esac
}

# expect_absent <label> <needle> <haystack>
expect_absent() {
    case "$3" in *"$2"*) fail "$1 ('$2' is there)" "$3" ;; *) pass "$1" ;; esac
}

finish() {
    printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
    [ "$FAIL" -eq 0 ]
}
```

- [ ] **Step 3: Write the failing image test**

`docker/ci/test/image.sh`:

```bash
#!/usr/bin/env bash
#
# The CI image on its own: it boots ready, FrontAccounting signs in, the
# fixture is loaded, mail is caught, and the FA tree is writable by group
# www-data.
#
#   FA_CI_IMAGE=<image> docker/ci/test/image.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../lib.sh"
. "$here/lib.sh"
: "${FA_CI_IMAGE:?set FA_CI_IMAGE to the image under test}"

c="fa-ci-test-image-$$"
trap 'docker rm -f "$c" >/dev/null 2>&1 || true' EXIT

echo "image: $FA_CI_IMAGE"
start="$(date +%s)"
expect_status 0 "boots and becomes ready" ci_boot "$c" "$FA_CI_IMAGE"
expect_status 0 "ready within 60s" test "$(( $(date +%s) - start ))" -lt 60
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
finish
```

Run: `chmod +x docker/ci/test/image.sh`

- [ ] **Step 4: Run the test to verify it fails**

Run: `FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/image.sh`
Expected: FAIL at "boots and becomes ready" (`Unable to find image 'fa-ci:local-cp-7.4'`, pull access denied), and a non-zero exit.

- [ ] **Step 5: Write the image's files**

`docker/ci/image/entrypoint.sh`:

```sh
#!/bin/sh
# Start MariaDB, wait for it, then hand over to the CMD (Apache in the
# foreground). Everything a plugin's tests need runs in this one container.
set -eu

mkdir -p /run/mysqld /var/run/apache2
chown mysql:mysql /run/mysqld
# A pid file left by an unclean stop makes Apache refuse to start.
rm -f /var/run/apache2/apache2.pid

mariadbd-safe --user=mysql >/dev/null 2>&1 &

i=0
until mariadb-admin --silent ping >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -lt 60 ] || { echo "fa-ci: MariaDB did not start" >&2; exit 1; }
    sleep 1
done

exec "$@"
```

`docker/ci/image/seed-db.sh`:

```sh
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
```

`docker/ci/image/config_db.php`:

```php
<?php
/*
	FrontAccounting CI image (docker/ci). The database is in this container,
	seeded from modules/tests/data/fa_test.sql.gz when the image was built.
*/
$def_coy = 0;
$tb_pref_counter = 1;
$db_connections = array (
  0 =>
  array (
    'name' => 'FA CI',
    'host' => 'localhost',
    'dbuser' => 'fa',
    'dbpassword' => 'fa',
    'dbname' => 'fa_test',
    'tbpref' => '0_',
  ),
);
```

`docker/ci/image/php.ini`:

```ini
; FrontAccounting CI image. Installed for both SAPIs (apache2 and cli).
memory_limit = 256M
max_execution_time = 120
upload_max_filesize = 32M
post_max_size = 32M
date.timezone = UTC
display_errors = On
display_startup_errors = On
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
; Tests rewrite installed_extensions.php and config_db.php between requests.
opcache.revalidate_freq = 0
; Every message mail() sends is kept in /var/mail-catcher instead.
sendmail_path = /usr/local/bin/fa-mail-catcher
```

`docker/ci/image/apache-fa-ci.conf`:

```apache
# FrontAccounting's .htaccess needs AllowOverride; Debian's default vhost turns
# it off for /var/www.
<Directory /var/www/html>
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

<FilesMatch "^(config\.php|config_db\.php|installed_extensions\.php)$">
    Require all denied
</FilesMatch>

ServerName localhost
```

`docker/ci/image/fa-mail-catcher`:

```sh
#!/bin/sh
# PHP's sendmail_path in the CI image: each message mail() sends is kept whole
# as /var/mail-catcher/<stamp>.eml instead of being delivered. PHP's -t -i style
# arguments are ignored.
set -eu
umask 000
dir=/var/mail-catcher
name="$(date +%Y%m%d%H%M%S)-$$-$(od -An -N4 -tx4 /dev/urandom | tr -d ' \n')"
cat > "$dir/.$name.tmp"
mv "$dir/.$name.tmp" "$dir/$name.eml"
```

`docker/ci/image/fa-ci-wait-ready`:

```sh
#!/bin/sh
# fa-ci-wait-ready [seconds]: wait until MariaDB answers and FrontAccounting
# serves its login page (default: 120 seconds).
set -eu
limit="${1:-120}"
waited=0
until mariadb-admin --silent ping >/dev/null 2>&1 \
    && curl -fsS -o /dev/null "${FA_URL:-http://localhost}/index.php"; do
    waited=$((waited + 1))
    [ "$waited" -lt "$limit" ] || { echo "fa-ci-wait-ready: not ready after ${limit}s" >&2; exit 1; }
    sleep 1
done
```

`docker/ci/image/fa-ci-login`:

```sh
#!/bin/sh
# fa-ci-login <cookie-jar>: sign in to FrontAccounting (company 0) as test/test.
# The jar then holds the session for further curl -b requests.
set -eu
jar="$1"
url="${FA_URL:-http://localhost}"
page="$(mktemp)"
trap 'rm -f "$page"' EXIT
curl -fsS -c "$jar" -b "$jar" -o /dev/null "$url/index.php"
curl -fsS -c "$jar" -b "$jar" -o "$page" \
    --data 'user_name_entry_field=test&password=test&company_login_name=0' "$url/index.php"
grep -qi 'logout' "$page" || { echo "fa-ci-login: FrontAccounting refused test/test" >&2; exit 1; }
```

- [ ] **Step 6: Write the Dockerfile**

`docker/ci/Dockerfile`:

```dockerfile
# FrontAccounting CI image: Apache + mod_php + MariaDB + FrontAccounting with a
# seeded fa_test database, in one container, for plugins' tests. Built by
# docker/ci/build-image.sh, which supplies two named build contexts:
#
#   fa       the FrontAccounting tree to install (this fork's HEAD, or upstream)
#   fixture  fa_test.sql.gz, the database it is seeded with
#
# PHP comes from Ondřej Surý's repository on Debian trixie, as in docker/Dockerfile.
FROM debian:trixie-slim

ARG PHP_VERSION=7.4
ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://packages.sury.org/php/apt.gpg -o /etc/apt/keyrings/sury-php.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/sury-php.gpg] https://packages.sury.org/php/ trixie main" \
        > /etc/apt/sources.list.d/sury-php.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        apache2 \
        git \
        mariadb-client \
        mariadb-server \
        unzip \
        libapache2-mod-php${PHP_VERSION} \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-common \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-xdebug \
        ; \
    phpdismod -v "${PHP_VERSION}" xdebug; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY image/php.ini /etc/php/${PHP_VERSION}/apache2/conf.d/zz-fa-ci.ini
COPY image/php.ini /etc/php/${PHP_VERSION}/cli/conf.d/zz-fa-ci.ini
COPY image/apache-fa-ci.conf /etc/apache2/conf-available/fa-ci.conf
RUN a2enmod rewrite && a2enconf fa-ci

COPY image/fa-mail-catcher /usr/local/bin/fa-mail-catcher
RUN chmod 0755 /usr/local/bin/fa-mail-catcher && install -d -m 1777 /var/mail-catcher

COPY image/fa-ci-* /usr/local/lib/fa-ci/
RUN set -eux; \
    chmod 0755 /usr/local/lib/fa-ci/*; \
    for f in /usr/local/lib/fa-ci/*; do ln -s "$f" /usr/local/bin/; done

# The seeded database.
COPY --from=fixture fa_test.sql.gz /usr/local/share/fa-ci/fa_test.sql.gz
COPY image/seed-db.sh /usr/local/lib/fa-ci-build/seed-db.sh
RUN sh /usr/local/lib/fa-ci-build/seed-db.sh

# FrontAccounting, configured for that database. Owned by www-data, group-
# writable and setgid, so commands run as the caller's uid with group
# www-data can change it (tests rewrite config_db.php and the extension lists).
COPY --from=fa . /var/www/html/
COPY image/config_db.php /var/www/html/config_db.php
RUN set -eux; \
    cd /var/www/html; \
    rm -f index.html; \
    cp config.default.php config.php; \
    printf '<?php\n\n$next_extension_id = 1;\n\n$installed_extensions = array (\n);\n' > installed_extensions.php; \
    install -d company/0 company/0/js_cache company/0/pdf_files company/0/backup company/0/images company/0/attachments tmp lang fa-ci; \
    printf '<?php\n\n$installed_extensions = array (\n);\n' > company/0/installed_extensions.php; \
    printf '<?php\n\n$installed_languages = array (\n  0 => array (\n    %s,\n    %s,\n    %s,\n    %s,\n  ),\n);\n\n$dflt_lang = %s;\n' \
        "'code' => 'C'" "'name' => 'English'" "'encoding' => 'iso-8859-1'" "'version' => '1'" "'C'" \
        > lang/installed_languages.inc; \
    chown -R www-data:www-data /var/www/html; \
    chmod -R g+w /var/www/html; \
    find /var/www/html -type d -exec chmod g+s {} +

ENV PHP_VERSION=${PHP_VERSION} \
    FA_ROOT=/var/www/html \
    FA_URL=http://localhost \
    FA_DB_HOST=localhost \
    FA_DB_NAME=fa_test \
    FA_DB_USER=fa \
    FA_DB_PASSWORD=fa

WORKDIR /var/www/html
EXPOSE 80

COPY image/entrypoint.sh /usr/local/bin/fa-ci-entrypoint
RUN chmod 0755 /usr/local/bin/fa-ci-entrypoint
ENTRYPOINT ["fa-ci-entrypoint"]
CMD ["apache2ctl", "-D", "FOREGROUND"]
```

- [ ] **Step 7: Write the build script**

`docker/ci/build-image.sh`:

```bash
#!/usr/bin/env bash
#
# Build the FrontAccounting CI image for one flavour and PHP version.
#
#   docker/ci/build-image.sh [--cache-gha] <cp|upstream> <php> <tag> [<tag>...]
#
#   cp          FrontAccounting from this checkout's HEAD (git archive, so
#               committed files only; docker/ci itself is read from the
#               working tree)
#   upstream    FrontAccounting from $FA_UPSTREAM_REPO at $FA_UPSTREAM_REF
#               (default FrontAccountingERP/FA master)
#   --cache-gha use GitHub Actions' cache for the layers (CI only)
#
# The database is always seeded from this checkout's
# modules/tests/data/fa_test.sql.gz.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib.sh"
root="$(cd "$here/../.." && pwd)"

gha=no
if [ "${1:-}" = --cache-gha ]; then gha=yes; shift; fi
[ "$#" -ge 3 ] || die "usage: build-image.sh [--cache-gha] <cp|upstream> <php> <tag>..."
flavour="$1"
php="$2"
shift 2

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/fa" "$stage/fixture"

case "$flavour" in
    cp)
        git -C "$root" archive HEAD | tar -x -C "$stage/fa"
        fa_ref="$(git -C "$root" rev-parse --abbrev-ref HEAD)"
        fa_sha="$(git -C "$root" rev-parse HEAD)"
        ;;
    upstream)
        repo="${FA_UPSTREAM_REPO:-https://github.com/FrontAccountingERP/FA.git}"
        fa_ref="${FA_UPSTREAM_REF:-master}"
        git clone --quiet --depth 1 --branch "$fa_ref" "$repo" "$stage/fa"
        fa_sha="$(git -C "$stage/fa" rev-parse HEAD)"
        rm -rf "$stage/fa/.git"
        ;;
    *) die "flavour must be cp or upstream, not '$flavour'" ;;
esac
cp "$root/modules/tests/data/fa_test.sql.gz" "$stage/fixture/"

tags=()
for tag in "$@"; do tags+=(-t "$tag"); done
cache=()
if [ "$gha" = yes ]; then
    cache=(--cache-from "type=gha,scope=fa-ci-$flavour-$php"
           --cache-to "type=gha,mode=max,scope=fa-ci-$flavour-$php")
fi

log "building FrontAccounting $flavour ($fa_ref ${fa_sha:0:7}) on PHP $php: $*"
docker buildx build --load "${cache[@]}" \
    --build-arg PHP_VERSION="$php" \
    --build-context fa="$stage/fa" \
    --build-context fixture="$stage/fixture" \
    --label org.opencontainers.image.source=https://github.com/cambell-prince/frontaccounting \
    --label org.opencontainers.image.revision="$(git -C "$root" rev-parse HEAD)" \
    --label org.opencontainers.image.description="FrontAccounting ($flavour, PHP $php) for plugin CI" \
    --label io.frontaccounting.ref="$fa_ref" \
    --label io.frontaccounting.commit="$fa_sha" \
    -f "$here/Dockerfile" "${tags[@]}" "$here"
```

Run: `chmod +x docker/ci/build-image.sh docker/ci/image/*.sh docker/ci/image/fa-*`

- [ ] **Step 8: Build the image and run the test**

Run: `docker/ci/build-image.sh cp 7.4 fa-ci:local-cp-7.4 && FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/image.sh`
Expected: every line `ok`, then `10 passed, 0 failed`, exit 0.

If "boots and becomes ready" fails, the diagnostics printed by `ci_boot` name the cause. The likely ones:
- `mariadbd-safe` missing: use `mysqld_safe`, which Debian ships as the same program.
- Apache can't find mod_php: check that `libapache2-mod-php${PHP_VERSION}` enabled `php${PHP_VERSION}` with `a2query -m`.

- [ ] **Step 9: Check the other flavour and PHP version build too**

Run: `docker/ci/build-image.sh upstream 8.3 fa-ci:local-upstream-8.3 && FA_CI_IMAGE=fa-ci:local-upstream-8.3 docker/ci/test/image.sh`
Expected: `10 passed, 0 failed`.

- [ ] **Step 10: Lint the shell scripts**

Run: `docker run --rm -v "$PWD":/mnt -w /mnt koalaman/shellcheck:stable -x docker/ci/lib.sh docker/ci/build-image.sh docker/ci/test/lib.sh docker/ci/test/image.sh docker/ci/image/entrypoint.sh docker/ci/image/seed-db.sh docker/ci/image/fa-mail-catcher docker/ci/image/fa-ci-wait-ready docker/ci/image/fa-ci-login`
Expected: no output, exit 0. SC1091, for sourced files it can't follow, may be silenced with `# shellcheck source=...` comments, as imscp's scripts do.

- [ ] **Step 11: Commit**

```bash
git add docker/ci
git commit -m "ci: Add the FrontAccounting CI image

One container per FA flavour (this fork, or upstream) and PHP version:
Apache, PHP, MariaDB and FrontAccounting with fa_test seeded at build time,
the tree group-writable for www-data, mail kept in /var/mail-catcher.
build-image.sh builds it; test/image.sh checks it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Registration, activation and grant helpers

**Files:**
- Create: `docker/ci/image/fa-ci-register`
- Create: `docker/ci/image/fa-ci-activate`
- Create: `docker/ci/image/fa-ci-grant`
- Create: `docker/ci/image/grant.php`
- Modify: `docker/ci/Dockerfile` (one `COPY` line after the `COPY image/config_db.php` line)
- Create: `docker/ci/test/fixtures/modules/ci_alpha/hooks.php`
- Create: `docker/ci/test/fixtures/modules/ci_alpha/sql/update_1.0.sql`
- Create: `docker/ci/test/fixtures/modules/ci_beta/hooks.php`
- Create: `docker/ci/test/fixtures/modules/ci_beta/sql/update_1.0.sql`
- Create: `docker/ci/test/fixtures/modules/ci_broken/hooks.php`
- Create: `docker/ci/test/fixtures/modules/ci_broken/sql/update_1.0.sql`
- Create: `docker/ci/test/fixtures/modules/ci_plain/README`
- Test: `docker/ci/test/attach.sh`

**Interfaces:**
- Consumes (Task 1): `lib.sh` (`ci_boot`), `test/lib.sh`, `fa-ci-login`, the `fa-ci-*` glob in the Dockerfile, `/var/www/html/fa-ci/`, and `fa-ci:local-cp-7.4`.
- Produces (inside the image):
  - `fa-ci-register <name> <path-relative-to-FA-root>`: run as `www-data`. It prints `registered <name> as extension <id>`, or `<name> is already registered as extension <id>`.
  - `fa-ci-activate <name>`: run as root. It prints `activated <name>`, or on failure `fa-ci-activate: FrontAccounting did not activate <name>` with exit 1.
  - `fa-ci-grant`: run as root. It prints `granted <n> areas in <m> sections`.
  - Fixture modules (Task 3 uses them too):
    - `ci_alpha`: creates `0_ci_alpha` holding `alpha-installed`; security area `SA_CI_ALPHA`.
    - `ci_beta`: activation fails unless `0_ci_alpha` exists.
    - `ci_broken`: its update SQL is invalid.
    - `ci_plain`: no `hooks.php`.

- [ ] **Step 1: Write the fixture modules**

`docker/ci/test/fixtures/modules/ci_alpha/hooks.php`:

```php
<?php
/* Test fixture for docker/ci: a module whose activation creates a table, and
   which declares one security area. */
define('SS_CI_ALPHA', 111 << 8);

class hooks_ci_alpha extends hooks
{
	var $module_name = 'ci_alpha';

	function install_access()
	{
		$security_sections[SS_CI_ALPHA] = 'CI alpha';
		$security_areas['SA_CI_ALPHA'] = array(SS_CI_ALPHA | 1, 'CI alpha area');
		return array($security_areas, $security_sections);
	}

	function activate_extension($company, $check_only = true)
	{
		return $this->update_databases($company, array('update_1.0.sql' => array('ci_alpha')), $check_only);
	}
}
```

`docker/ci/test/fixtures/modules/ci_alpha/sql/update_1.0.sql`:

```sql
CREATE TABLE IF NOT EXISTS `0_ci_alpha` (`marker` varchar(32) NOT NULL) ENGINE=InnoDB;
INSERT INTO `0_ci_alpha` (`marker`) VALUES ('alpha-installed');
```

`docker/ci/test/fixtures/modules/ci_beta/hooks.php`:

```php
<?php
/* Test fixture for docker/ci: stands in for a plugin that needs another one.
   Its activation fails unless ci_alpha's table is already there. */
class hooks_ci_beta extends hooks
{
	var $module_name = 'ci_beta';

	function activate_extension($company, $check_only = true)
	{
		global $db_connections;

		if (check_table($db_connections[$company]['tbpref'], 'ci_alpha') != 0)
			return false;
		return $this->update_databases($company, array('update_1.0.sql' => array('ci_beta')), $check_only);
	}
}
```

`docker/ci/test/fixtures/modules/ci_beta/sql/update_1.0.sql`:

```sql
CREATE TABLE IF NOT EXISTS `0_ci_beta` (`id` int(11) NOT NULL) ENGINE=InnoDB;
```

`docker/ci/test/fixtures/modules/ci_broken/hooks.php`:

```php
<?php
/* Test fixture for docker/ci: a module whose update SQL fails, so its
   activation does. */
class hooks_ci_broken extends hooks
{
	var $module_name = 'ci_broken';

	function activate_extension($company, $check_only = true)
	{
		return $this->update_databases($company, array('update_1.0.sql' => array('ci_broken')), $check_only);
	}
}
```

`docker/ci/test/fixtures/modules/ci_broken/sql/update_1.0.sql`:

```sql
CREATE TABLE `0_ci_broken` (this is not valid sql);
```

`docker/ci/test/fixtures/modules/ci_plain/README`:

```
Test fixture for docker/ci: a checkout with no hooks.php, like the api module,
which needs --name.
```

- [ ] **Step 2: Write the failing attach test**

`docker/ci/test/attach.sh`:

```bash
#!/usr/bin/env bash
#
# The image's module helpers against fixture modules: registration,
# activation through FrontAccounting's own form, dependency order, a failing
# activation, and the grant.
#
#   FA_CI_IMAGE=<image> docker/ci/test/attach.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../lib.sh"
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
```

Run: `chmod +x docker/ci/test/attach.sh`

- [ ] **Step 3: Run the test to verify it fails**

Run: `docker/ci/build-image.sh cp 7.4 fa-ci:local-cp-7.4 && FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/attach.sh`
Expected: FAIL from "registers ci_alpha" onwards (`fa-ci-register: executable file not found`), and a non-zero exit.

- [ ] **Step 4: Write the helpers**

`docker/ci/image/fa-ci-register`:

```php
#!/usr/bin/env php
<?php
/*
	fa-ci-register <name> <path>

	Add a module to FrontAccounting's extension lists, inactive, as Setup ->
	Install/Activate Extensions does (write_extensions() in
	admin/db/maintenance_db.inc): the global installed_extensions.php, with
	$next_extension_id moved on, and company 0's copy. <path> is relative to the
	FA root, e.g. modules/graphql. Run it as www-data, which owns those files.
*/
if ($argc !== 3) {
	fwrite(STDERR, "usage: fa-ci-register <name> <path relative to the FA root>\n");
	exit(2);
}
list(, $name, $path) = $argv;
$root = getenv('FA_ROOT') ?: '/var/www/html';

function load_extensions($file)
{
	$installed_extensions = array();
	$next_extension_id = null;
	if (is_file($file))
		include $file;
	return array($installed_extensions, $next_extension_id);
}

function save_extensions($file, $extensions, $next = null)
{
	$php = "<?php\n\n";
	if ($next !== null)
		$php .= "\$next_extension_id = $next; // unique id for next installed extension\n\n";
	$php .= '$installed_extensions = ' . var_export($extensions, true) . ";\n";
	if (file_put_contents($file, $php) === false) {
		fwrite(STDERR, "fa-ci-register: cannot write $file\n");
		exit(1);
	}
}

list($global, $next) = load_extensions("$root/installed_extensions.php");
foreach ($global as $id => $ext) {
	if ($ext['package'] === $name) {
		echo "$name is already registered as extension $id\n";
		exit(0);
	}
}

$id = $next ?: (count($global) ? max(array_keys($global)) + 1 : 1);
$entry = array(
	'package' => $name,
	'name' => $name,
	'version' => '-',
	'available' => '',
	'type' => 'extension',
	'path' => $path,
	'active' => false,
);
$global[$id] = $entry;
save_extensions("$root/installed_extensions.php", $global, $id + 1);

list($company) = load_extensions("$root/company/0/installed_extensions.php");
$company[$id] = $entry;
save_extensions("$root/company/0/installed_extensions.php", $company);

echo "registered $name as extension $id\n";
```

`docker/ci/image/fa-ci-activate`:

```sh
#!/bin/sh
# fa-ci-activate <name>: activate a registered module for company 0 through
# FrontAccounting's own Setup -> Install/Activate Extensions form, so its
# activate_extension() and update_*.sql run exactly as they do on a real
# install. The form deactivates any module it is sent unticked, so every
# module already active is sent ticked too. Fails unless FrontAccounting then
# lists the module as active.
set -eu
[ "$#" -eq 1 ] || { echo "usage: fa-ci-activate <name>" >&2; exit 2; }
name="$1"
root="${FA_ROOT:-/var/www/html}"
url="${FA_URL:-http://localhost}"
list="$root/company/0/installed_extensions.php"
jar="$(mktemp)"
page="$(mktemp)"
trap 'rm -f "$jar" "$page"' EXIT

# The extension ids to send ticked: everything active now, plus $name.
ids="$(php -r '
    $installed_extensions = array();
    include $argv[1];
    $found = false;
    foreach ($installed_extensions as $id => $e) {
        if ($e["package"] === $argv[2]) { $found = true; echo $id, "\n"; }
        elseif (!empty($e["active"])) echo $id, "\n";
    }
    exit($found ? 0 : 1);' "$list" "$name")" \
    || { echo "fa-ci-activate: $name is not registered (fa-ci-register first)" >&2; exit 1; }

fa-ci-login "$jar"
set -- --data-urlencode extset=0 --data-urlencode Refresh=Update
for id in $ids; do set -- "$@" --data-urlencode "Active$id=1"; done
curl -fsS -c "$jar" -b "$jar" -o "$page" "$@" "$url/admin/inst_module.php"

if ! php -r '
    $installed_extensions = array();
    include $argv[1];
    foreach ($installed_extensions as $e)
        if ($e["package"] === $argv[2] && !empty($e["active"])) exit(0);
    exit(1);' "$list" "$name"; then
    echo "fa-ci-activate: FrontAccounting did not activate $name" >&2
    sed 's/<[^>]*>/ /g' "$page" | tr -s ' \n' ' ' \
        | grep -o -i -E '[^.>]*(error|failed|cannot|incompatible)[^.<]*' | head -n 5 >&2 || true
    exit 1
fi
echo "activated $name"
```

`docker/ci/image/fa-ci-grant`:

```sh
#!/bin/sh
# fa-ci-grant: give the System Administrator role (id 2), which the test user
# holds, every security section and area FrontAccounting knows, extension ones
# included, through /fa-ci/grant.php. Run it after activating modules, so their
# pages are open to the tests.
set -eu
url="${FA_URL:-http://localhost}"
jar="$(mktemp)"
out="$(mktemp)"
trap 'rm -f "$jar" "$out"' EXIT
fa-ci-login "$jar"
curl -fsS -b "$jar" -o "$out" "$url/fa-ci/grant.php"
grep '^granted ' "$out" || {
    echo "fa-ci-grant: unexpected response from fa-ci/grant.php:" >&2
    head -c 2000 "$out" >&2
    exit 1
}
```

`docker/ci/image/grant.php`:

```php
<?php
/*
	CI image only (docker/ci), not part of FrontAccounting. Gives the System
	Administrator role (id 2) every security section and area known in this
	request, extension ones included. Extension codes depend on each module's
	extension id and are only worked out during a request
	(add_access_extensions()), which is why this runs as a page.
*/
$page_security = 'SA_SECROLES';
$path_to_root = '..';
include_once($path_to_root . '/includes/session.inc');
include_once($path_to_root . '/admin/db/security_db.inc');

add_access_extensions();

$role = get_security_role(2);
$sections = array_keys($security_sections);
$areas = array();
foreach ($security_areas as $area)
	$areas[] = $area[0];
update_security_role(2, $role['role'], $role['description'], $sections, $areas);

header('Content-Type: text/plain');
echo 'granted ', count($areas), ' areas in ', count($sections), " sections\n";
```

In `docker/ci/Dockerfile`, after the line `COPY image/config_db.php /var/www/html/config_db.php`, add:

```dockerfile
COPY image/grant.php /var/www/html/fa-ci/grant.php
```

Run: `chmod +x docker/ci/image/fa-ci-register docker/ci/image/fa-ci-activate docker/ci/image/fa-ci-grant`

- [ ] **Step 5: Rebuild and run the test**

Run: `docker/ci/build-image.sh cp 7.4 fa-ci:local-cp-7.4 && FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/attach.sh`
Expected: `19 passed, 0 failed`.

If "activates ci_alpha" fails with `FrontAccounting did not activate`, open the saved form response. Run the same curl by hand in `docker exec -it <container> bash` and look for FA's message. "The security settings on your account do not permit…" means the fixture's role 2 lacks `SA_CREATEMODULES`. Then run `fa-ci-grant` before activation in both this test and Task 3's driver, and say so in the commit.

- [ ] **Step 6: Re-run the image test (the Dockerfile changed)**

Run: `FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/image.sh`
Expected: `10 passed, 0 failed`.

- [ ] **Step 7: Lint**

Run: `docker run --rm -v "$PWD":/mnt -w /mnt koalaman/shellcheck:stable -x docker/ci/image/fa-ci-activate docker/ci/image/fa-ci-grant docker/ci/test/attach.sh && php -l docker/ci/image/fa-ci-register && php -l docker/ci/image/grant.php`
Expected: shellcheck prints nothing; php prints `No syntax errors detected` twice.

- [ ] **Step 8: Commit**

```bash
git add docker/ci
git commit -m "ci: Register, activate and grant modules in the CI image

fa-ci-register writes FA's extension lists as write_extensions() does.
fa-ci-activate submits Setup -> Install/Activate Extensions as the test
user, so each module's activate_extension() and update SQL really run, and
fails unless FA then lists it active. fa-ci-grant opens every area,
extension ones included, to the admin role.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The driver, `plugin-test.sh`

**Files:**
- Create: `docker/ci/plugin-test.sh`
- Test: `docker/ci/test/driver.sh`

**Interfaces:**
- Consumes (Task 1): `lib.sh` (`log`, `die`, `fa_ci_image`, `module_name`, `ci_boot`, `ci_diagnostics`), `test/lib.sh`, and the image. (Task 2): `fa-ci-register`, `fa-ci-activate`, `fa-ci-grant`, and the fixture modules.
- Produces the command line Tasks 5, 6 and 7 call:

```
docker/ci/plugin-test.sh [--image IMG | --fa cp|upstream --php 7.4|8.3]
                         [--with NAME=REPO@REF | --with NAME=PATH]...
                         [--setup CMD] [--no-activate] [--keep]
                         [--name NAME] [--mount HOST:CONTAINER]...
                         <plugin-checkout> [--] <test command>
```

  Environment: `FA_CI_IMAGE` (the default image) and `COMPOSER_CACHE_DIR` (mounted as `/tmp/composer-cache`). The exit status is the test command's.

- [ ] **Step 1: Write the failing driver test**

`docker/ci/test/driver.sh`:

```bash
#!/usr/bin/env bash
#
# plugin-test.sh end to end against the fixture modules: where and as whom
# commands run, activation order, --with (path and git), failures and clean-up.
#
#   FA_CI_IMAGE=<image> docker/ci/test/driver.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../lib.sh"
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
expect_status 0 "COMPOSER_CACHE_DIR is mounted for composer" \
    env COMPOSER_CACHE_DIR="$tmp/composer-cache" "$d" --no-activate "$fx/ci_alpha" -- \
    'test "$COMPOSER_CACHE_DIR" = /tmp/composer-cache && touch /tmp/composer-cache/seen'
expect_status 0 "and writes land in the host directory" test -f "$tmp/composer-cache/seen"
expect_status 0 "no container is left behind" sh -c "! docker ps -a --format '{{.Names}}' | grep -q '^fa-ci-ci_'"
finish
```

Run: `chmod +x docker/ci/test/driver.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/driver.sh`
Expected: FAIL on every case that runs the driver (`plugin-test.sh: No such file or directory`), and a non-zero exit.

- [ ] **Step 3: Write the driver**

`docker/ci/plugin-test.sh`:

```bash
#!/usr/bin/env bash
#
# Run one FrontAccounting plugin's tests in the CI image.
#
#   docker/ci/plugin-test.sh [options] <plugin-checkout> [--] <test command>
#
# The checkout is mounted at /var/www/html/modules/<name>, where <name> comes
# from `class hooks_<name>` in its hooks.php. Then:
#   1. each cloned --with module gets `composer install --no-dev`
#   2. --setup runs in the plugin directory
#   3. the --with modules (in the order given), then the plugin, are
#      registered and activated through FrontAccounting's own
#      Install/Activate Extensions form, and the admin role is granted their
#      areas. An activation failure fails the run.
#   4. the test command runs in the plugin directory
# Commands run with sh -c as your uid:gid, with group www-data added,
# umask 002 and HOME=/tmp. The exit status is the test command's.
#
# Options:
#   --image IMG            the CI image (default: $FA_CI_IMAGE, else the one
#                          --fa and --php name)
#   --fa cp|upstream       FrontAccounting flavour (default: cp)
#   --php 7.4|8.3          PHP version (default: 7.4)
#   --with NAME=REPO@REF   another module the plugin needs, cloned at REF
#                          (the part after the last @); repeatable
#   --with NAME=PATH       ... or a local checkout of it, used as it is
#   --setup CMD            run before activation, e.g. composer install
#   --no-activate          mount only: no registration, activation or grant
#   --name NAME            the module name, for a checkout without hooks.php
#   --mount HOST:CONTAINER another bind mount; repeatable
#   --keep                 leave the container running, with Apache on a
#                          printed localhost port (sign in as test/test)
#
# COMPOSER_CACHE_DIR, when set, is mounted as composer's cache.
# .github/workflows/plugin-test.yml runs exactly this, so a failing CI job
# can be reproduced locally with the same arguments.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

IMAGE="${FA_CI_IMAGE:-}"
FLAVOUR=cp
PHP=7.4
SETUP=''
ACTIVATE=yes
NAME=''
KEEP=no
WITH=()
MOUNTS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --image) IMAGE="$2"; shift 2 ;;
        --fa) FLAVOUR="$2"; shift 2 ;;
        --php) PHP="$2"; shift 2 ;;
        --with) WITH+=("$2"); shift 2 ;;
        --setup) SETUP="$2"; shift 2 ;;
        --no-activate) ACTIVATE=no; shift ;;
        --name) NAME="$2"; shift 2 ;;
        --mount) MOUNTS+=("$2"); shift 2 ;;
        --keep) KEEP=yes; shift ;;
        --) shift; break ;;
        -*) die "unknown option: $1" ;;
        *) break ;;
    esac
done

[ "$#" -ge 2 ] || die "usage: plugin-test.sh [options] <plugin-checkout> [--] <test command>"
[ -d "$1" ] || die "$1 is not a directory"
CHECKOUT="$(cd "$1" && pwd)"
shift
[ "${1:-}" = -- ] && shift
TEST="$*"
[ -n "$TEST" ] || die "no test command"

[ -n "$IMAGE" ] || IMAGE="$(fa_ci_image "$FLAVOUR" "$PHP")"
[ -n "$NAME" ] || NAME="$(module_name "$CHECKOUT")" \
    || die "$CHECKOUT has no hooks.php declaring class hooks_<name>; pass --name"

FA=/var/www/html
CONTAINER="fa-ci-$NAME-$$"
WORK="$(mktemp -d)"

run_args=(-v "$CHECKOUT:$FA/modules/$NAME")
deps=()
cloned=()
for spec in "${WITH[@]+"${WITH[@]}"}"; do
    dep="${spec%%=*}"
    src="${spec#*=}"
    [ -n "$dep" ] && [ "$dep" != "$spec" ] && [ -n "$src" ] \
        || die "--with takes NAME=REPO@REF or NAME=PATH, not '$spec'"
    [ "$dep" != "$NAME" ] || die "--with $dep: $dep is the plugin under test"
    if [ -d "$src" ]; then
        path="$(cd "$src" && pwd)"
    else
        repo="${src%@*}"
        ref="${src##*@}"
        [ "$repo" != "$src" ] && [ -n "$ref" ] || die "--with $spec: not a directory, and no @REF"
        log "cloning $dep: $repo @ $ref"
        git clone --quiet --depth 1 --branch "$ref" "$repo" "$WORK/$dep"
        path="$WORK/$dep"
        cloned+=("$dep")
    fi
    run_args+=(-v "$path:$FA/modules/$dep")
    deps+=("$dep")
done
for m in "${MOUNTS[@]+"${MOUNTS[@]}"}"; do run_args+=(-v "$m"); done

exec_env=(-e HOME=/tmp)
if [ -n "${COMPOSER_CACHE_DIR:-}" ]; then
    mkdir -p "$COMPOSER_CACHE_DIR"
    run_args+=(-v "$COMPOSER_CACHE_DIR:/tmp/composer-cache")
    exec_env+=(-e COMPOSER_CACHE_DIR=/tmp/composer-cache)
fi
[ "$KEEP" = no ] || run_args+=(-p 127.0.0.1::80)

cleanup() {
    local rc=$?
    [ "$rc" -eq 0 ] || ci_diagnostics "$CONTAINER"
    if [ "$KEEP" = yes ] && docker inspect "$CONTAINER" >/dev/null 2>&1; then
        log "leaving $CONTAINER running: http://$(docker port "$CONTAINER" 80 | head -n 1)/ (test/test);" \
            "docker exec -it $CONTAINER bash; docker rm -f $CONTAINER when done"
    else
        docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK"
    exit "$rc"
}
trap cleanup EXIT

ci_boot "$CONTAINER" "$IMAGE" "${run_args[@]}"

# as_user <dir> <command>: sh -c <command> in <dir> as the caller, group www-data added.
as_user() {
    docker exec -w "$1" "${exec_env[@]}" "$CONTAINER" \
        setpriv --reuid="$(id -u)" --regid="$(id -g)" --groups=33 \
        sh -c "umask 002; $2"
}

for dep in "${cloned[@]+"${cloned[@]}"}"; do
    log "composer install --no-dev: $dep"
    as_user "$FA/modules/$dep" '[ ! -f composer.json ] || composer install --no-dev --no-interaction --no-progress'
done

if [ -n "$SETUP" ]; then
    log "setup: $SETUP"
    as_user "$FA/modules/$NAME" "$SETUP"
fi

if [ "$ACTIVATE" = yes ]; then
    for module in "${deps[@]+"${deps[@]}"}" "$NAME"; do
        log "activating $module"
        docker exec -u www-data "$CONTAINER" fa-ci-register "$module" "modules/$module"
        docker exec "$CONTAINER" fa-ci-activate "$module"
    done
    docker exec "$CONTAINER" fa-ci-grant
fi

log "test: $TEST"
as_user "$FA/modules/$NAME" "$TEST"
```

Run: `chmod +x docker/ci/plugin-test.sh`

- [ ] **Step 4: Run the test to verify it passes**

Run: `FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/test/driver.sh`
Expected: `24 passed, 0 failed`.

- [ ] **Step 5: Try --keep by hand**

Run: `FA_CI_IMAGE=fa-ci:local-cp-7.4 docker/ci/plugin-test.sh --keep docker/ci/test/fixtures/modules/ci_alpha -- true`
Expected: it ends with `leaving fa-ci-ci_alpha-<pid> running: http://127.0.0.1:<port>/`, and `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:<port>/index.php` prints `200`. Then run `docker rm -f fa-ci-ci_alpha-<pid>`.

- [ ] **Step 6: Lint**

Run: `docker run --rm -v "$PWD":/mnt -w /mnt koalaman/shellcheck:stable -x docker/ci/plugin-test.sh docker/ci/test/driver.sh`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add docker/ci/plugin-test.sh docker/ci/test/driver.sh
git commit -m "ci: Add plugin-test.sh, the driver plugins run their tests with

Mounts the plugin (and --with modules, cloned or local) under modules/,
activates them through FA in dependency order, then runs --setup and the
test command as the caller's uid with group www-data. The same script runs
locally and in the reusable workflow.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Pruning old images

**Files:**
- Create: `docker/ci/prune-images.sh`
- Create: `docker/ci/test/fixtures/prune/versions.json`
- Test: `docker/ci/test/prune.sh`

**Interfaces:**
- Consumes (Task 1): `docker/ci/test/lib.sh`.
- Produces:

```
docker/ci/prune-images.sh [--dry-run] [--keep N]      # prune
docker/ci/prune-images.sh [--dry-run] --pr NUMBER     # drop one PR's images
```

  Output lines: `would delete <id> <tags>: <why>` or `deleted <id> <tags>: <why>`, then `<n> version(s) would be deleted (dry run)`, `<n> version(s) deleted`, or `nothing to delete from ...`. Environment: `GH_TOKEN`. Test hooks `PRUNE_VERSIONS_FILE` and `PRUNE_OPEN_PRS`. Overrides `PRUNE_OWNER_PATH` (default `users/cambell-prince`), `PRUNE_PACKAGE` (default `frontaccounting-ci`) and `PRUNE_REPO` (default `cambell-prince/frontaccounting`).

- [ ] **Step 1: Write the fixture**

`docker/ci/test/fixtures/prune/versions.json`, in the shape `gh api .../versions` returns:

```json
[
  {"id": 1,  "created_at": "2026-09-05T00:00:00Z", "metadata": {"container": {"tags": ["cp-php7.4", "cp-php7.4-aaaaaaa"]}}},
  {"id": 2,  "created_at": "2026-09-04T00:00:00Z", "metadata": {"container": {"tags": ["cp-php7.4-bbbbbbb"]}}},
  {"id": 3,  "created_at": "2026-09-03T00:00:00Z", "metadata": {"container": {"tags": ["cp-php7.4-ccccccc"]}}},
  {"id": 4,  "created_at": "2026-09-02T00:00:00Z", "metadata": {"container": {"tags": ["cp-php7.4-ddddddd"]}}},
  {"id": 5,  "created_at": "2026-09-01T00:00:00Z", "metadata": {"container": {"tags": ["cp-php7.4-eeeeeee"]}}},
  {"id": 6,  "created_at": "2026-09-05T00:00:00Z", "metadata": {"container": {"tags": ["upstream-php8.3", "upstream-php8.3-aaaaaaa"]}}},
  {"id": 7,  "created_at": "2026-09-01T00:00:00Z", "metadata": {"container": {"tags": ["upstream-php8.3-fffffff"]}}},
  {"id": 8,  "created_at": "2026-09-01T00:00:00Z", "metadata": {"container": {"tags": []}}},
  {"id": 9,  "created_at": "2026-09-03T00:00:00Z", "metadata": {"container": {"tags": ["pr-17-cp-php7.4"]}}},
  {"id": 10, "created_at": "2026-09-02T00:00:00Z", "metadata": {"container": {"tags": ["pr-18-cp-php7.4"]}}},
  {"id": 11, "created_at": "2026-09-02T00:00:00Z", "metadata": {"container": {"tags": ["pr-18-upstream-php8.3"]}}},
  {"id": 12, "created_at": "2026-08-31T00:00:00Z", "metadata": {"container": {"tags": ["cp-php7.4-ggggggg"]}}},
  {"id": 13, "created_at": "2026-08-01T00:00:00Z", "metadata": {"container": {"tags": ["latest"]}}}
]
```

Expected decisions:
- Delete 5 and 12: older than cp-php7.4's newest three unprotected sha versions, which are 2, 3 and 4.
- Delete 8: untagged.
- Delete 10 and 11: PR 18 is closed.
- Keep 1 and 6 (moving tags), 2, 3 and 4, 7 (upstream-php8.3's only unprotected sha), 9 (PR 17 is open), and 13 (a tag the prune doesn't know).

- [ ] **Step 2: Write the failing test**

`docker/ci/test/prune.sh`:

```bash
#!/usr/bin/env bash
#
# prune-images.sh's decision, on the fixture versions and no network.
#
#   docker/ci/test/prune.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib.sh"

p="$here/../prune-images.sh"
f="$here/fixtures/prune/versions.json"

expect_status 0 "dry run" env PRUNE_VERSIONS_FILE="$f" PRUNE_OPEN_PRS='17 19' "$p" --dry-run
for id in 5 8 10 11 12; do expect_contains "deletes version $id" "would delete $id " "$OUT"; done
for id in 1 2 3 4 6 7 9 13; do expect_absent "keeps version $id" "would delete $id " "$OUT"; done
expect_contains "says why for the old sha" "older than the newest 3 cp-php7.4-<sha>" "$OUT"
expect_contains "counts them" "5 version(s) would be deleted (dry run)" "$OUT"

expect_status 0 "--keep 1" env PRUNE_VERSIONS_FILE="$f" PRUNE_OPEN_PRS='17' "$p" --dry-run --keep 1
for id in 3 4; do expect_contains "--keep 1 also deletes version $id" "would delete $id " "$OUT"; done
expect_absent "--keep 1 keeps version 2" "would delete 2 " "$OUT"

expect_status 0 "--pr 17 drops that PR's images only" env PRUNE_VERSIONS_FILE="$f" "$p" --dry-run --pr 17
expect_contains "PR 17's image" "would delete 9 " "$OUT"
expect_absent "not PR 18's" "would delete 10 " "$OUT"

expect_status 0 "nothing to do" env PRUNE_VERSIONS_FILE="$f" "$p" --dry-run --pr 99
expect_contains "and says so" "nothing to delete" "$OUT"

expect_status 1 "--keep needs a number" "$p" --keep x
expect_status 1 "--pr needs a number" "$p" --pr x
expect_status 1 "unknown arguments are refused" "$p" --bogus
finish
```

Run: `chmod +x docker/ci/test/prune.sh`

- [ ] **Step 3: Run the test to verify it fails**

Run: `docker/ci/test/prune.sh`
Expected: every case FAILs (`prune-images.sh: No such file or directory`), non-zero exit.

- [ ] **Step 4: Write the prune script**

`docker/ci/prune-images.sh`:

```bash
#!/usr/bin/env bash
#
# Delete the CI images nothing needs any more from
# ghcr.io/cambell-prince/frontaccounting-ci.
#
#   docker/ci/prune-images.sh [--dry-run] [--keep <n>]    prune
#   docker/ci/prune-images.sh [--dry-run] --pr <number>   drop one PR's images
#
# Prune keeps:
#
#   * every version with a tag it does not recognise: the moving
#     <flavour>-php<ver> tags plugins pull, above all;
#   * per flavour, the newest <n> (default 3) <flavour>-php<ver>-<sha>
#     versions, so a plugin can pin a known-good image;
#   * pr-<number>-* versions whose pull request is still open;
#
# and deletes the rest: older <sha> versions, closed pull requests' images, and
# untagged versions (left behind whenever a tag moves on).
#
# --pr <number> deletes that pull request's images only, open or not; CI runs
# it when the pull request closes.
#
# Needs GH_TOKEN with packages read/delete on the package and pull request read
# on the repository; in CI that is the workflow's GITHUB_TOKEN, since this
# repository publishes the package. PRUNE_VERSIONS_FILE and PRUNE_OPEN_PRS
# stand in for the two API reads (docker/ci/test/prune.sh).

set -euo pipefail

OWNER_PATH="${PRUNE_OWNER_PATH:-users/cambell-prince}"
PACKAGE="${PRUNE_PACKAGE:-frontaccounting-ci}"
REPO="${PRUNE_REPO:-cambell-prince/frontaccounting}"
KEEP=3
PR=''
DRY_RUN=no

die() { printf 'prune-images: %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=yes; shift ;;
        --keep) KEEP="${2:-}"; shift 2 ;;
        --pr) PR="${2:-}"; shift 2 ;;
        *) die "unknown argument: $1" ;;
    esac
done
case "$KEEP" in ''|*[!0-9]*) die "--keep takes a number" ;; esac
case "$PR" in *[!0-9]*) die "--pr takes a pull request number" ;; esac

VERSIONS_API="/$OWNER_PATH/packages/container/$PACKAGE/versions"

# Every version as {id, created_at, tags}. --paginate emits one array per page.
versions() {
    if [ -n "${PRUNE_VERSIONS_FILE:-}" ]; then
        cat "$PRUNE_VERSIONS_FILE"
    else
        gh api --paginate "$VERSIONS_API?per_page=100"
    fi | jq -s '[.[][] | {id, created_at, tags: .metadata.container.tags}]'
}

open_prs() {
    if [ -n "${PRUNE_OPEN_PRS+set}" ]; then
        # shellcheck disable=SC2086
        printf '%s\n' $PRUNE_OPEN_PRS
    else
        gh api --paginate "/repos/$REPO/pulls?state=open&per_page=100" --jq '.[].number'
    fi | jq -Rs '[split("\n")[] | select(length > 0) | tonumber]'
}

JQ_TAGS='
    def sha_tag: test("^(cp|upstream)-php[0-9.]+-[0-9a-f]{7,40}$");
    def pr_tag: test("^pr-[0-9]+-(cp|upstream)-php[0-9.]+$");
    def pr_number: capture("^pr-(?<n>[0-9]+)-").n | tonumber;
    # A tag it does not recognise (the moving ones above all) protects a version.
    def protected: any(.tags[]; (sha_tag or pr_tag) | not);
    def flavour: [.tags[] | select(sha_tag) | sub("-[0-9a-f]+$"; "")][0];
'

if [ -n "$PR" ]; then
    doomed="$(versions | jq --argjson pr "$PR" "$JQ_TAGS"'
        [ .[] | select((.tags | length) > 0
                       and all(.tags[]; pr_tag)
                       and any(.tags[]; pr_number == $pr))
              | {id, tags, why: "its pull request has closed"} ]')"
else
    doomed="$(versions | jq --argjson keep "$KEEP" --argjson open "$(open_prs)" "$JQ_TAGS"'
        (map(select((.tags | length) > 0 and (protected | not) and any(.tags[]; sha_tag)))
         | group_by(flavour)
         | map(sort_by(.created_at) | reverse | .[$keep:])
         | add // []
         | map(.id)) as $old
        | [ .[]
            | if (.tags | length) == 0 then
                  {id, tags, why: "untagged"}
              elif protected then
                  empty
              elif (.id | IN($old[])) then
                  {id, tags, why: "older than the newest \($keep) \(flavour)-<sha>"}
              elif all(.tags[]; pr_tag) and all(.tags[]; pr_number | IN($open[]) | not) then
                  {id, tags, why: "its pull request has closed"}
              else
                  empty
              end ]')"
fi

count="$(jq length <<< "$doomed")"
if [ "$count" -eq 0 ]; then
    echo "nothing to delete from ghcr.io/${OWNER_PATH#*/}/$PACKAGE"
    exit 0
fi

jq -r '.[] | "\(.id)\t\(if (.tags | length) == 0 then "(untagged)" else (.tags | join(",")) end)\t\(.why)"' \
    <<< "$doomed" |
while IFS=$'\t' read -r id tags why; do
    if [ "$DRY_RUN" = yes ]; then
        printf 'would delete %s %s: %s\n' "$id" "$tags" "$why"
    else
        gh api --silent -X DELETE "$VERSIONS_API/$id"
        printf 'deleted %s %s: %s\n' "$id" "$tags" "$why"
    fi
done

if [ "$DRY_RUN" = yes ]; then
    echo "$count version(s) would be deleted (dry run)"
else
    echo "$count version(s) deleted"
fi
```

Run: `chmod +x docker/ci/prune-images.sh`

- [ ] **Step 5: Run the test to verify it passes**

Run: `docker/ci/test/prune.sh`
Expected: `28 passed, 0 failed`.

- [ ] **Step 6: Lint**

Run: `docker run --rm -v "$PWD":/mnt -w /mnt koalaman/shellcheck:stable docker/ci/prune-images.sh docker/ci/test/prune.sh`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add docker/ci/prune-images.sh docker/ci/test/prune.sh docker/ci/test/fixtures/prune
git commit -m "ci: Prune old CI images

Keeps each flavour's moving tag and its newest three -<sha> versions, and
open PRs' images; deletes the rest and untagged versions. --pr drops one
pull request's images. Dry run by default in PRs, as in saygoweb/imscp.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Smoke test and the `ci-image.yml` workflow

**Files:**
- Create: `docker/ci/test/run.sh`
- Create: `docker/ci/smoke-test.sh`
- Create: `.github/workflows/ci-image.yml`

**Interfaces:**
- Consumes: `test/image.sh` (Task 1), `test/attach.sh` (Task 2), `test/driver.sh` (Task 3), `test/prune.sh` (Task 4), `build-image.sh [--cache-gha] <flavour> <php> <tag>...` (Task 1), and `prune-images.sh [--dry-run] | --pr N` (Task 4).
- Produces:
  - `docker/ci/test/run.sh [image]`: the whole suite; the prune test always runs, the image tests need an image.
  - `docker/ci/smoke-test.sh <image>`
  - The published tags (Global Constraints).

- [ ] **Step 1: Write the suite runner and smoke test**

`docker/ci/test/run.sh`:

```bash
#!/usr/bin/env bash
#
# The docker/ci test suite.
#
#   docker/ci/test/run.sh [<image>]
#
# prune.sh needs no image and always runs. With an image (the argument, else
# $FA_CI_IMAGE) image.sh, attach.sh and driver.sh run against it.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

image="${1:-${FA_CI_IMAGE:-}}"
failed=()
run() {
    printf '\n## %s\n' "$1"
    "$here/$1" || failed+=("$1")
}

run prune.sh
if [ -n "$image" ]; then
    export FA_CI_IMAGE="$image"
    run image.sh
    run attach.sh
    run driver.sh
else
    printf '\n(no image given: skipped image.sh, attach.sh, driver.sh)\n'
fi

if [ "${#failed[@]}" -gt 0 ]; then
    printf '\nFAILED: %s\n' "${failed[*]}"
    exit 1
fi
printf '\nall passed\n'
```

`docker/ci/smoke-test.sh`:

```bash
#!/usr/bin/env bash
#
# Check a built CI image before it is pushed, with the docker/ci test suite:
# it boots ready, FrontAccounting signs in, modules activate through FA's own
# form, and plugin-test.sh drives a run end to end.
#
#   docker/ci/smoke-test.sh <image>

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$#" -eq 1 ] || { echo "usage: smoke-test.sh <image>" >&2; exit 2; }
exec "$here/test/run.sh" "$1"
```

Run: `chmod +x docker/ci/test/run.sh docker/ci/smoke-test.sh`

- [ ] **Step 2: Run the smoke test on the local image**

Run: `docker/ci/smoke-test.sh fa-ci:local-cp-7.4`
Expected: four sections, each ending `0 failed`, then `all passed`.

- [ ] **Step 3: Check the smoke test catches a broken image**

Run: `docker build -t fa-ci:broken - <<< $'FROM fa-ci:local-cp-7.4\nRUN rm /var/www/html/config_db.php' && docker/ci/smoke-test.sh fa-ci:broken; echo "exit=$?"`
Expected: failures in image.sh (FA can't sign in without its config), a closing `FAILED:` line that lists `image.sh` (attach.sh and driver.sh fail too), and `exit=1`. Then `docker rmi fa-ci:broken`.

- [ ] **Step 4: Write the workflow**

`.github/workflows/ci-image.yml`:

```yaml
name: CI image

# Builds, smoke-tests and publishes ghcr.io/cambell-prince/frontaccounting-ci,
# the images plugins test against through .github/workflows/plugin-test.yml,
# then prunes versions nothing needs. See docker/ci/README.md.

on:
  push:
    branches:
      - master-cp
    paths: &image-paths
      - '*.php'
      - access/**
      - admin/**
      - applications/**
      - dimensions/**
      - fixed_assets/**
      - gl/**
      - includes/**
      - inventory/**
      - js/**
      - lang/**
      - manufacturing/**
      - modules/tests/data/**
      - purchasing/**
      - reporting/**
      - sales/**
      - sql/**
      - taxes/**
      - themes/**
      - docker/ci/**
      - .github/workflows/ci-image.yml
  pull_request:
    types: [opened, synchronize, reopened, closed]
    paths: *image-paths
  schedule:
    # Weekly, for Debian and sury updates and upstream FrontAccounting's master.
    - cron: '23 3 * * 1'
  workflow_dispatch:
    inputs:
      dry-run:
        description: Only report what the prune would delete
        type: boolean
        default: false

permissions:
  contents: read
  packages: write
  pull-requests: read

concurrency:
  group: ci-image-${{ github.event.pull_request.number && format('pr-{0}', github.event.pull_request.number) || github.ref }}
  cancel-in-progress: true

env:
  IMAGE: ghcr.io/cambell-prince/frontaccounting-ci

jobs:
  build:
    # Pull requests from forks cannot push to this repository's package.
    if: >-
      github.event_name != 'pull_request'
      || (github.event.pull_request.head.repo.full_name == github.repository
          && github.event.action != 'closed')
    name: ${{ matrix.fa }} / PHP ${{ matrix.php }}
    runs-on: ubuntu-24.04
    timeout-minutes: 45
    strategy:
      fail-fast: false
      matrix:
        fa: [cp, upstream]
        php: ['7.4', '8.3']
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      # Exposes the cache service's URL and token to build-image.sh's
      # `--cache-to type=gha`, which a plain run step does not otherwise see.
      - uses: crazy-max/ghaction-github-runtime@v3
      - name: Choose tags
        id: tags
        run: |
          flavour="${{ matrix.fa }}-php${{ matrix.php }}"
          if [ "${{ github.event_name }}" = pull_request ]; then
              echo "tags=$IMAGE:pr-${{ github.event.pull_request.number }}-$flavour" >> "$GITHUB_OUTPUT"
          else
              echo "tags=$IMAGE:$flavour $IMAGE:$flavour-${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"
          fi
      - name: Build
        run: docker/ci/build-image.sh --cache-gha ${{ matrix.fa }} ${{ matrix.php }} ${{ steps.tags.outputs.tags }}
      - name: Smoke test
        run: |
          set -- ${{ steps.tags.outputs.tags }}
          docker/ci/smoke-test.sh "$1"
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Push
        run: |
          for tag in ${{ steps.tags.outputs.tags }}; do
              docker push "$tag"
          done

  prune:
    needs: build
    if: ${{ !cancelled() && needs.build.result != 'skipped' }}
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
        with:
          sparse-checkout: docker/ci
      - name: Prune old images
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          DRY_RUN: ${{ github.event_name == 'pull_request' || inputs.dry-run == true }}
        run: |
          args=()
          [ "$DRY_RUN" = true ] && args+=(--dry-run)
          docker/ci/prune-images.sh "${args[@]}"

  drop-pr-image:
    if: >-
      github.event_name == 'pull_request'
      && github.event.action == 'closed'
      && github.event.pull_request.head.repo.full_name == github.repository
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
        with:
          sparse-checkout: docker/ci
      - name: Delete this pull request's images
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: docker/ci/prune-images.sh --pr ${{ github.event.pull_request.number }}
```

- [ ] **Step 5: Check the action versions exist, then lint the workflow**

Run: `for a in actions/checkout docker/setup-buildx-action crazy-max/ghaction-github-runtime docker/login-action; do printf '%s ' $a; gh api repos/$a/releases/latest --jq .tag_name; done`
Expected: each prints a tag. If a newer major than the one pinned above exists (e.g. `v5` for `actions/checkout`), update the `uses:` line to that major.

Run: `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:latest -color .github/workflows/ci-image.yml`
Expected: no output, exit 0. If actionlint rejects the YAML anchor (`&image-paths`), replace `*image-paths` with a copy of the list.

- [ ] **Step 6: Lint the scripts**

Run: `docker run --rm -v "$PWD":/mnt -w /mnt koalaman/shellcheck:stable docker/ci/test/run.sh docker/ci/smoke-test.sh`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add docker/ci/test/run.sh docker/ci/smoke-test.sh .github/workflows/ci-image.yml
git commit -m "ci: Build, smoke-test and publish the CI images

ci-image.yml builds {cp, upstream} x {7.4, 8.3} with the buildx GHA cache,
runs the docker/ci suite against each as its smoke test, pushes to GHCR,
then prunes; a closed PR's images are dropped. Weekly, for OS and upstream
FA updates.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The reusable `plugin-test.yml` workflow and the README

**Files:**
- Create: `.github/workflows/plugin-test.yml`
- Create: `docker/ci/README.md`

**Interfaces:**
- Consumes: the `plugin-test.sh` command line (Task 3), `fa_ci_image` naming (Task 1), and the published tags (Task 5).
- Produces the `workflow_call` contract plugins use:
  - inputs: `test` (required), `setup`, `with` (multi-line `NAME=REPO@REF`), `fa` (default `cp`), `php` (default `7.4`), `image` (default: derived from `fa`/`php`), `fa-ref` (default `master-cp`), `activate` (default `true`), `name`;
  - secret: `clone-token`.

- [ ] **Step 1: Write the workflow**

`.github/workflows/plugin-test.yml`:

```yaml
name: Plugin test

# Reusable workflow: run a FrontAccounting plugin's tests in the CI image
# (docker/ci), exactly as docker/ci/plugin-test.sh does locally. A plugin's
# workflow calls it:
#
#   jobs:
#     test:
#       strategy:
#         matrix: {fa: [cp, upstream], php: ['7.4', '8.3']}
#       uses: cambell-prince/frontaccounting/.github/workflows/plugin-test.yml@master-cp
#       with:
#         fa: ${{ matrix.fa }}
#         php: ${{ matrix.php }}
#         setup: composer install --no-interaction --no-progress
#         test: sh tools/ci.sh

on:
  workflow_call:
    inputs:
      test:
        description: Test command, run with sh -c in the plugin's directory in the container
        type: string
        required: true
      setup:
        description: Command run before the plugin is activated (e.g. composer install)
        type: string
        default: ''
      with:
        description: Other modules to activate first, one NAME=REPO@REF per line
        type: string
        default: ''
      fa:
        description: FrontAccounting flavour, cp (cambell-prince/frontaccounting master-cp) or upstream
        type: string
        default: cp
      php:
        description: PHP version, 7.4 or 8.3
        type: string
        default: '7.4'
      image:
        description: The CI image to boot, overriding fa and php (e.g. a pinned -<sha> tag)
        type: string
        default: ''
      fa-ref:
        description: The cambell-prince/frontaccounting ref whose docker/ci scripts drive the run
        type: string
        default: master-cp
      activate:
        description: Register and activate the plugin through FrontAccounting before testing
        type: boolean
        default: true
      name:
        description: The module name, for a checkout without hooks.php
        type: string
        default: ''
    secrets:
      clone-token:
        description: Token for cloning private repositories named in `with`
        required: false

permissions:
  contents: read
  packages: read

jobs:
  test:
    name: FA ${{ inputs.fa }} / PHP ${{ inputs.php }}
    runs-on: ubuntu-24.04
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
        with:
          path: plugin
      - uses: actions/checkout@v4
        with:
          repository: cambell-prince/frontaccounting
          ref: ${{ inputs.fa-ref }}
          path: fa-ci
          sparse-checkout: docker/ci
      - name: Composer cache
        uses: actions/cache@v4
        with:
          path: ${{ runner.temp }}/composer-cache
          key: composer-${{ inputs.php }}-${{ hashFiles('plugin/composer.lock', 'plugin/composer.json') }}
          restore-keys: composer-${{ inputs.php }}-
      - name: Git access for `with`
        env:
          CLONE_TOKEN: ${{ secrets.clone-token }}
        run: |
          # SSH-style URLs work here too: there is no SSH key, so use https.
          git config --global url."https://github.com/".insteadOf "git@github.com:"
          if [ -n "$CLONE_TOKEN" ]; then
              git config --global url."https://x-access-token:${CLONE_TOKEN}@github.com/".insteadOf "https://github.com/"
          fi
      - name: Test
        env:
          COMPOSER_CACHE_DIR: ${{ runner.temp }}/composer-cache
          FA_CI_IMAGE: ${{ inputs.image }}
          FA: ${{ inputs.fa }}
          PHP: ${{ inputs.php }}
          SETUP: ${{ inputs.setup }}
          WITH: ${{ inputs.with }}
          ACTIVATE: ${{ inputs.activate }}
          NAME: ${{ inputs.name }}
          TEST: ${{ inputs.test }}
        run: |
          args=(--fa "$FA" --php "$PHP")
          [ -n "$SETUP" ] && args+=(--setup "$SETUP")
          [ -n "$NAME" ] && args+=(--name "$NAME")
          [ "$ACTIVATE" = true ] || args+=(--no-activate)
          while IFS= read -r line; do
              line="${line#"${line%%[![:space:]]*}"}"
              [ -n "$line" ] && args+=(--with "$line")
          done <<< "$WITH"
          fa-ci/docker/ci/plugin-test.sh "${args[@]}" plugin -- "$TEST"
```

The driver reads `FA_CI_IMAGE` and ignores it when empty (it falls back to `--fa`/`--php`), so `image: ''` means "derive the tag".

- [ ] **Step 2: Lint the workflow**

Run: `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:latest -color .github/workflows/plugin-test.yml`
Expected: no output, exit 0.

- [ ] **Step 3: Write the README**

`docker/ci/README.md`:

````markdown
# FrontAccounting CI package

Prebuilt FrontAccounting test images, and the script and reusable workflow a
plugin's tests run with, modelled on `saygoweb/imscp`'s `docker/ci`.

| piece | what it is |
| --- | --- |
| `ghcr.io/cambell-prince/frontaccounting-ci:<flavour>-php<ver>` | Apache, PHP, MariaDB and FrontAccounting with `fa_test` seeded, in one container. `<flavour>` is `cp` (this fork, master-cp) or `upstream` (FrontAccountingERP/FA master); `<ver>` is `7.4` or `8.3`. Each build is also tagged `-<sha7>`, to pin. |
| `plugin-test.sh` | runs a plugin's tests in that image, locally or in CI |
| `.github/workflows/plugin-test.yml` | the same, as a reusable workflow |
| `.github/workflows/ci-image.yml` | builds, smoke-tests, publishes and prunes the images |

## In a plugin's CI

```yaml
name: CI
on:
  push:
  pull_request:
jobs:
  test:
    strategy:
      fail-fast: false
      matrix: {fa: [cp, upstream], php: ['7.4', '8.3']}
    uses: cambell-prince/frontaccounting/.github/workflows/plugin-test.yml@master-cp
    with:
      fa: ${{ matrix.fa }}
      php: ${{ matrix.php }}
      setup: composer install --no-interaction --no-progress
      with: |
        sgw_sales=https://github.com/saygoweb/frontaccounting-module-sgw_sales.git@master
      test: sh tools/ci.sh
```

Inputs:
- `test` (required) and `setup`: commands.
- `with`: other modules, one `NAME=REPO@REF` per line.
- `fa`, `php`: which image to use.
- `image`: overrides `fa` and `php`, e.g. a pinned `-<sha>` tag.
- `fa-ref`: which revision of these scripts drives the run.
- `activate: false` and `name`: for a checkout that isn't an FA extension.
- Secret `clone-token`: for private `with` repos.

## Locally

From the plugin's checkout, with this repository checked out beside it:

    ../frontaccounting/docker/ci/plugin-test.sh --setup 'composer install' . -- sh tools/ci.sh

The same options as the workflow: `--fa`, `--php`, `--image`,
`--with NAME=REPO@REF` or `--with NAME=../path` (a local checkout, used as
it is), `--setup`, `--no-activate`, `--name`, and `--mount HOST:CONTAINER`.
`--keep` leaves the container running, with FrontAccounting on a printed
localhost port (sign in as `test`/`test`).

## What a run does

1. Mounts the plugin at `/var/www/html/modules/<name>`. `<name>` comes from
   `class hooks_<name>` in its `hooks.php`, which is how FrontAccounting finds
   it. Each `--with` module is mounted beside it.
2. Runs `composer install --no-dev` in each cloned `--with` module, then `--setup`.
3. Registers and activates the `--with` modules in order, then the plugin,
   through FrontAccounting's own Setup → Install/Activate Extensions. So each
   module's `activate_extension()` and `update_*.sql` run as on a real install,
   and **a failed activation fails the run**. Then gives the admin role every
   area.
4. Runs the test command in the plugin's directory.

Commands run as your uid:gid with group `www-data` added, so they can write
to the FA tree (`config_db.php`, `company/`, `tmp/`), and files they leave in
your checkout stay yours. The environment has:
- `FA_ROOT=/var/www/html` and `FA_URL=http://localhost`;
- `FA_DB_HOST`, `FA_DB_NAME`, `FA_DB_USER` and `FA_DB_PASSWORD` (`localhost`,
  `fa_test`, `fa`, `fa`).

`fa-ci-login <cookie-jar>` signs in over HTTP. Mail from PHP's `mail()` is
kept in `/var/mail-catcher/*.eml`. On failure the run prints the tails of FA's
`tmp/errors.log` and Apache's error log.

## Working on the package

    docker/ci/build-image.sh cp 7.4 fa-ci:local-cp-7.4
    docker/ci/test/run.sh fa-ci:local-cp-7.4

`cp` images take FrontAccounting from HEAD (committed files); the `docker/ci`
files themselves come from the working tree. `test/run.sh` with no image runs
only the prune test.

The GHCR package is public, so plugins pull without credentials. Old
versions are pruned after each publish. Each flavour's moving tag and newest
three `-<sha>` versions are kept, along with open pull requests' images. Run
`docker/ci/prune-images.sh --dry-run` with `GH_TOKEN` to see what would go.
````

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/plugin-test.yml docker/ci/README.md
git commit -m "ci: Add the reusable plugin-test workflow and docs

plugins call plugin-test.yml with a test command, and a matrix of fa and php
if they want one; it runs docker/ci/plugin-test.sh from the chosen fa-ref
exactly as a local run does.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: sgw_import adopts the package (its first CI)

Work in a worktree of the sgw_import repository:

```bash
cd /home/cambell/src/sgw/frontaccounting/modules/sgw_import
git fetch origin
git worktree add -b ci/fa-ci-package /home/cambell/src/sgw/frontaccounting/.claude/worktrees/sgw_import-ci origin/master
cd /home/cambell/src/sgw/frontaccounting/.claude/worktrees/sgw_import-ci
```

Paths below are relative to that worktree. `$FA_CI` means `/home/cambell/src/sgw/frontaccounting/.claude/worktrees/ci-package/docker/ci`.

**Files:**
- Create: `tools/ci.sh`
- Create: `.github/workflows/ci.yml`
- Modify: `README.md` (add a "Tests" section at the end)

**Interfaces:**
- Consumes: the `plugin-test.sh` command line (Task 3), the local image `fa-ci:local-cp-7.4` (Tasks 1-3), the `plugin-test.yml` inputs (Task 6), and the in-image `fa-ci-login` and `FA_URL` (Task 1).
- Produces: sgw_import's CI; `tools/ci.sh`, run in the container.

- [ ] **Step 1: Write the check**

`tools/ci.sh`:

```sh
#!/bin/sh
# sgw_import's checks. Runs inside the FrontAccounting CI image, in this
# module's directory, after the module and the ones it is deployed with
# (graphql, sgw_sales) have been activated. See docker/ci/README.md in
# cambell-prince/frontaccounting.
set -eu

echo "==> php -l"
find . -path ./vendor -prune -o -path ./node_modules -prune -o -name '*.php' -print |
while IFS= read -r f; do
    php -l "$f" >/dev/null || { php -l "$f"; exit 1; }
done

# Every extension's hooks share one PHP process, so with graphql active all of
# them get its Anorm 3. A class sgw_import cannot load there is a fatal error
# part-way through the page (as before #14), so check the page renders to the
# end: its upload form.
echo "==> Import Bank Files renders with graphql and sgw_sales active"
jar="$(mktemp)"
page="$(mktemp)"
fa-ci-login "$jar"
curl -fsS -b "$jar" -o "$page" "$FA_URL/modules/sgw_import/import_files.php"
if ! grep -qi 'upload' "$page"; then
    echo "import_files.php stopped before its upload form. FrontAccounting's log:" >&2
    tail -n 20 "$FA_ROOT/tmp/errors.log" >&2 2>/dev/null || true
    exit 1
fi
echo "ok"
```

- [ ] **Step 2: See it catch the Anorm 3 fatal on the pre-#14 code**

`tools/ci.sh` is a new, untracked file, so checking out old code leaves it in place.

Run:

```bash
git checkout -q 2f1560d -- includes composer.json
FA_CI_IMAGE=fa-ci:local-cp-7.4 "$FA_CI/plugin-test.sh" \
  --setup 'composer install --no-interaction --no-progress' \
  --with graphql=https://github.com/saygoweb/frontaccounting-module-graphql.git@main \
  --with sgw_sales=https://github.com/saygoweb/frontaccounting-module-sgw_sales.git@master \
  . -- sh tools/ci.sh; echo "exit=$?"
```

Expected: `import_files.php stopped before its upload form`, the log lines show `Cannot make non static method Anorm\Model::delete() static`, and `exit=1`.

Then put the current code back: `git checkout -q HEAD -- includes composer.json && rm -rf vendor composer.lock && git status --short` (only `tools/` should be listed).

- [ ] **Step 3: Run it on the current code**

Run:

```bash
FA_CI_IMAGE=fa-ci:local-cp-7.4 "$FA_CI/plugin-test.sh" \
  --setup 'composer install --no-interaction --no-progress' \
  --with graphql=https://github.com/saygoweb/frontaccounting-module-graphql.git@main \
  --with sgw_sales=https://github.com/saygoweb/frontaccounting-module-sgw_sales.git@master \
  . -- sh tools/ci.sh; echo "exit=$?"
```

Expected: `activated graphql`, `activated sgw_sales`, `activated sgw_import`, `==> php -l`, `ok`, and `exit=0`.

- [ ] **Step 4: Write the workflow**

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches:
      - master
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
      setup: composer install --no-interaction --no-progress
      # Activated with the modules it is deployed with: they share one PHP
      # process, and so one Anorm (see tools/ci.sh).
      with: |
        graphql=https://github.com/saygoweb/frontaccounting-module-graphql.git@main
        sgw_sales=https://github.com/saygoweb/frontaccounting-module-sgw_sales.git@master
      test: sh tools/ci.sh
```

Run: `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:latest -color .github/workflows/ci.yml`
Expected: no output. actionlint can't fetch the remote reusable workflow's inputs offline and may warn about that. Only that warning is acceptable.

- [ ] **Step 5: Document it**

Append to `README.md`:

```markdown
## Tests

CI runs `tools/ci.sh` in the FrontAccounting CI image
([cambell-prince/frontaccounting `docker/ci`](https://github.com/cambell-prince/frontaccounting/tree/master-cp/docker/ci)),
with graphql and sgw_sales activated alongside, as they are deployed. To
run it locally, with that repository checked out beside this one:

    ../frontaccounting/docker/ci/plugin-test.sh \
      --setup 'composer install --no-interaction --no-progress' \
      --with graphql=https://github.com/saygoweb/frontaccounting-module-graphql.git@main \
      --with sgw_sales=https://github.com/saygoweb/frontaccounting-module-sgw_sales.git@master \
      . -- sh tools/ci.sh
```

- [ ] **Step 6: Commit (don't push; the controller pushes once the images are published)**

```bash
chmod +x tools/ci.sh
git add tools/ci.sh .github/workflows/ci.yml README.md
git commit -m "ci: Test in the FrontAccounting CI image

Lints, then activates sgw_import through FrontAccounting alongside graphql
and sgw_sales, as deployed, and checks Import Bank Files renders in full:
a standing check for the Anorm 3 clash fixed in #14.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Wave 6 (controller): publish and adopt

- [ ] Run the full local suite on both flavours: `docker/ci/build-image.sh upstream 7.4 fa-ci:local-upstream-7.4 && docker/ci/test/run.sh fa-ci:local-upstream-7.4`, plus `docker/ci/test/run.sh fa-ci:local-cp-7.4`. Both must end with `all passed`.
- [ ] Push `feature/ci-package` and open a PR against `master-cp` with `--repo cambell-prince/frontaccounting` (the fork's parent is upstream FA). Wait for the four `build` jobs (smoke-tested `pr-<n>-*` images) and the `prune` dry run to go green.
- [ ] Squash merge. The master-cp push publishes `cp-php7.4`, `cp-php8.3`, `upstream-php7.4` and `upstream-php8.3`.
- [ ] **User step:** GitHub → the `frontaccounting-ci` package → Package settings → Change visibility → Public. Also check that "Manage Actions access" lists `cambell-prince/frontaccounting` with the Admin role, so prune can delete versions.
- [ ] Verify an anonymous pull works: `docker logout ghcr.io; docker pull ghcr.io/cambell-prince/frontaccounting-ci:cp-php7.4`.
- [ ] Push sgw_import's `ci/fa-ci-package` and open its PR. All four matrix jobs must be green. If upstream or PHP 8.3 fails because of sgw_import's own code rather than the package, report it to the user. Don't hide it by shrinking the matrix without their say.
- [ ] Merge as the user asks.
