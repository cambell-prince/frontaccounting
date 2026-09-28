# FrontAccounting CI package: design

Status: agreed in conversation on 2026-09-28 (sections 1-4 approved one by one).

## Purpose

Every FrontAccounting plugin (graphql, sgw_sales, api) carries its own
1,000-1,300 line docker stack that clones FA, writes its config and drives
PHPUnit, and every CI run builds FA from scratch. sgw_import has no CI at all.
Following `saygoweb/imscp`'s `docker/ci` package, the FA fork publishes
prebuilt test images, one driver script and a reusable workflow. A plugin's
CI then comes down to one `uses:` line and a test command, and the same run
reproduces locally with one command.

Success looks like this:

- A plugin's CI is `uses: cambell-prince/frontaccounting/.github/workflows/plugin-test.yml@master-cp`
  plus its `test` command.
- `docker/ci/plugin-test.sh <checkout> -- <test command>` reproduces that run locally.
- Migrated plugins keep their current coverage: the same test counts.

## Scope

In scope, and delivered by plan 1 (`docs/superpowers/plans/2026-09-28-fa-ci-package.md`):

- §1 the image, §2 the driver and activation, §3 the workflows, including pruning;
- adopting it in sgw_import (§4.2), which proves it end to end.

Deferred to plan 2: moving sgw_sales, graphql and api onto it (§4.3-4.5),
each to test-count parity.

Out of scope: production deployment (make.phar, done), CI for master-ark, and
writing new tests for sgw_import.

## §1 The image (`docker/ci/Dockerfile`)

- Debian trixie-slim, with PHP from sury (as `docker/Dockerfile`). Build arg
  `PHP_VERSION`: 7.4 or 8.3.
- Apache and mod_php, MariaDB server and client, composer 2, git, curl.
  xdebug is installed but disabled.
- The FA tree is baked in at `/var/www/html`. It arrives through the named
  build context `fa`, which `build-image.sh` prepares:
  - **cp** is `git archive` of the fork's HEAD;
  - **upstream** is a shallow clone of `FrontAccountingERP/FA` master.

  The fixture comes through a second named context, `fixture`, holding the
  fork's `modules/tests/data/fa_test.sql.gz`.
- `config_db.php` names `localhost` and `fa_test` as user `fa`/`fa`, with
  prefix `0_`. The image also ships `config.php` (from `config.default.php`),
  empty extension lists (root and company 0), English in
  `lang/installed_languages.inc`, and `tmp/` and the `company/0/*` directories.
- The database is seeded at build time, so a container starts with data
  ready. It has users `fa`/`fa` and a passwordless `travis` (the fixtures
  expect it). The FA login is `test`/`test` (System Administrator, role 2).
- The FA tree is owned by `www-data`, is group-writable, and has the setgid
  bit on its directories, so commands run as the host uid with
  `--group-add www-data` can write to it.
- Mail: PHP's `sendmail_path` is `fa-mail-catcher`, which keeps each message
  in `/var/mail-catcher/*.eml`.
- The entrypoint starts MariaDB, waits for it, then runs Apache in the foreground.
- Helpers in `/usr/local/lib/fa-ci`, linked into `/usr/local/bin`:
  - `fa-ci-wait-ready`
  - `fa-ci-register <name> <path>`
  - `fa-ci-activate <name>`
  - `fa-ci-grant`

  CI-only page: `/var/www/html/fa-ci/grant.php`.
- Tags:
  - `ghcr.io/cambell-prince/frontaccounting-ci:<flavour>-php<ver>`, with the moving tag and `-<sha7>`;
  - `pr-<n>-<flavour>-php<ver>` for pull requests.

  `<flavour>` is `cp` or `upstream`; `<ver>` is `7.4` or `8.3`. OCI labels
  record the source, the revision, and the FA ref and commit.

## §2 The driver (`docker/ci/plugin-test.sh`) and activation

```
plugin-test.sh [--image IMG | --fa cp|upstream --php 7.4|8.3]
               [--with NAME=REPO@REF | --with NAME=PATH]...
               [--setup CMD] [--no-activate] [--keep]
               [--name NAME] [--mount HOST:CONTAINER]...
               <plugin-checkout> [--] <test command>
```

- **Module name:** from `class hooks_<name>` in the checkout's `hooks.php`;
  `--name` for a checkout without one (api).
- **Mounts:**
  - the plugin at `/var/www/html/modules/<name>`;
  - each `--with` path likewise; a `REPO@REF` is cloned on the host into a
    temp directory first, so SSH keys work;
  - `COMPOSER_CACHE_DIR` when set;
  - each `--mount`.
- **Commands** run as the host uid:gid with `--group-add www-data`,
  `HOME=/tmp`.
- **Order of a run:**
  1. boot and `fa-ci-wait-ready`;
  2. `composer install --no-dev` in each cloned `--with` that has a
     composer.json (a local `--with NAME=PATH` is used as it is, so a
     developer's checkout keeps its dev dependencies);
  3. `--setup` in the plugin directory;
  4. activation, the `--with` modules first in the order given, then the
     plugin: `fa-ci-register`, then `fa-ci-activate`, then `fa-ci-grant`;
  5. the test command in the plugin directory.
- **Registration** writes both `installed_extensions.php` files the way FA's
  `write_extensions()` does (`var_export`, version `'-'`, inactive).
- **Activation** logs in over HTTP as `test` and submits FA's own Setup →
  Install/Activate Extensions form (`Refresh`), so the module's
  `activate_extension()` and its `update_*.sql` run exactly as in production.
  It succeeds only if the company list then shows the module active. **An
  activation failure fails the run.**
- **Grant** requests `fa-ci/grant.php`, which runs inside FA's request
  context: `add_access_extensions()`, then gives role 2 every section and
  area.
- **Exit and diagnostics:**
  - the exit status is the test command's;
  - on failure it prints the tails of FA's `tmp/errors.log` and Apache's error log;
  - `--keep` leaves the container up with Apache on a printed localhost port;
    otherwise the container is removed.

## §3 Workflows (`.github/workflows/`)

- **`ci-image.yml`:**
  - Triggers: pushes to master-cp (app code, `docker/ci/**`, the workflow);
    same-repo PRs, including `closed`; a weekly cron; dispatch with a
    `dry-run` input.
  - Build: a matrix of `{cp, upstream} × {7.4, 8.3}`, with `fail-fast: false`
    and the buildx GHA cache.
  - Then `smoke-test.sh`, and a push only when it passes.
  - A `prune` job after the builds; a `drop-pr-image` job when a PR closes.
- **`plugin-test.yml`** (`workflow_call`):
  - Inputs: `test` (required), `setup`, `with` (one `NAME=REPO@REF` per line),
    `fa` (default `cp`), `php` (default `7.4`), `image`, `fa-ref` (default
    `master-cp`), `activate` (default true), `name`.
  - Optional secret `clone-token`.
  - Steps: check out the plugin; sparse-checkout `docker/ci` from the fork;
    composer cache; pull; run the driver.
  - The caller owns the matrix.
- **Pruning (`docker/ci/prune-images.sh`):**
  - Keep every version with a tag it doesn't recognise (the moving tags).
  - Per image series (`<flavour>-php<ver>`), keep the newest 3 `-<sha7>` tags.
  - Delete untagged versions, and `pr-<n>-*` whose PR is closed.
  - `--pr <n>` deletes one PR's images.
  - It's a dry run on pull requests. The package belongs to the user
    account, so the API path is `/users/cambell-prince/packages/container/frontaccounting-ci/versions`.
- **Visibility:** the package is made public, a one-time manual step on
  GitHub, so saygoweb repos pull without credentials.

## §4 Migration

Each plugin moves in its own PR. The old stack is deleted only once the new
workflow is green at the same test count. Each plugin gets a `tools/ci.sh`
that runs inside the container.

1. The FA fork: this package.
2. **sgw_import** (no CI today): a lint, then activation `--with
   graphql=…@main --with sgw_sales=…@master`. That is the production set, and
   a standing regression test for the Anorm 3 fatal fixed in #14. It has no
   PHPUnit suite yet.
3. sgw_sales (plan 2): its suite, plus a second job running
   `phpunit-graphql.xml` `--with graphql`. Parity is 66 and 66.
4. graphql (plan 2): the mail catcher is in the image, its second-company
   tests use the group-writable tree, and `ANORM_GRAPHQL_PATH` becomes
   `--mount`. Parity is 966, plus the default-company test.
5. api (plan 2): `--name api --no-activate`.

## §5 Plan 2 additions (2026-09-28)

Moving sgw_sales, graphql and api onto the package
(`docs/superpowers/plans/2026-09-28-fa-ci-package-plan-2.md`) showed needs the
three have in common. They go in the package, not in each plugin's scripts.

- **Datasets.**
  - `plugin-test.sh --dataset test|demo` (default `test`), and the reusable
    workflow's `dataset` input.
  - `demo` replaces `fa_test` with FrontAccounting's own `sql/en_US-demo.sql`,
    adds the `test`/`test` login the package's helpers use (role 2), and appends
    fiscal years until today is inside one.
  - The dataset is loaded **before** activation, so each module's `update_*.sql`
    still runs through FA.
  - In-image helper: `fa-ci-dataset <test|demo>`.
- **Grants.**
  - `fa-ci-grant` gives the `test` user a role of its own, `FA CI`, holding
    every section and area. It leaves role 2 as the dataset has it, because
    plugins' own fixtures copy role 2 and assert what it lacks.
  - `fa-ci-grant --role <id> --module <name>` adds one module's sections and
    areas to a role. They are worked out in FA's request, as the full grant is.
- **`fa-ci-ext-id <module>`** prints the extension id FA gave a module. The id
  depends on activation order, so anything that encodes an extension's area
  codes has to derive them from it.
- **Parity with the plugins' old stacks:**
  - `FA_DB_PREFIX=0_` in the image's environment.
  - Apache runs with `umask 002`, so files it creates (e.g. `tmp/faillog.php`)
    stay writable by the test uid's `www-data` group.
  - `display_errors` off, notices out of `error_reporting`, `memory_limit` 512M.
  - `/var/mail-catcher` is 0777 without the sticky bit.
  - The Authorization header is passed through to PHP.
- **graphql keeps `docker/`** as its development stack, which serves the
  saygoweb.com-my client's development with dev fixtures, Voyager and the mail
  listing. Only its CI and test runs move to the package. This uses §4's "a
  plugin may keep a thin dev wrapper". sgw_sales' and api's stacks only ever
  ran tests, so they are deleted as §4 says.
- **Parity targets** (tests run / skipped):

  | suite | cp | upstream |
  | --- | --- | --- |
  | graphql `phpunit.xml` | 966 / 1 | 966 / 2 |
  | sgw_sales' GraphQL suite, from graphql | 66 / 0 | 66 / 0 |
  | graphql default-company | 1 / 0 | 1 / 0 |
  | sgw_sales `phpunit.xml` | 66 / 1 | — |
  | sgw_sales `phpunit-graphql.xml` | 66 / 0 | 66 / 0 |
  | api | 31 / 0 | 31 / 0 |

  The extra upstream skip in graphql is `CompatDriftTest`, which needs a fork
  file. api was only proven on upstream before; `cp` is added.
