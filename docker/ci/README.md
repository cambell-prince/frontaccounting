# FrontAccounting CI package

Prebuilt FrontAccounting test images, and the script and reusable workflow a
plugin's tests run with, modelled on `saygoweb/imscp`'s `docker/ci`.

| piece | what it is |
| --- | --- |
| `ghcr.io/cambell-prince/frontaccounting-ci:<flavour>-php<ver>` | Apache, PHP, MariaDB and FrontAccounting with `fa_test` seeded, in one container. `<flavour>` is `cp` (this fork, master-cp) or `upstream` (FrontAccountingERP/FA master); `<ver>` is `7.4` or `8.3`. Each build is also tagged `-<sha7>`, to pin: that tag is pushed once and never replaced (weekly rebuilds refresh only the moving `<flavour>-php<ver>` tag), and for `upstream` images the sha is this fork's commit, not upstream FrontAccounting's (the `io.frontaccounting.commit` label records that). |
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
- `dataset`: `test` (the image's `fa_test`, the default) or `demo`
  (FrontAccounting's demo company, with fiscal years reaching today).
- `image`: overrides `fa` and `php`, e.g. a pinned `-<sha>` tag.
- `fa-ref`: which revision of these scripts drives the run.
- `activate: false` and `name`: for a checkout that isn't an FA extension.
- Secret `clone-token`: for private `with` repos.

## Locally

From the plugin's checkout, with this repository checked out beside it:

    ../frontaccounting/docker/ci/plugin-test.sh --setup 'composer install' . -- sh tools/ci.sh

The same options as the workflow: `--fa`, `--php`, `--dataset`, `--image`,
`--with NAME=REPO@REF` or `--with NAME=../path` (a local checkout, used as
it is), `--setup`, `--no-activate`, `--name`, and `--mount HOST:CONTAINER`.
`--keep` leaves the container running, with FrontAccounting on a printed
localhost port (sign in as `test`/`test`).

## What a run does

1. Mounts the plugin at `/var/www/html/modules/<name>`. `<name>` comes from
   `class hooks_<name>` in its `hooks.php`, which is how FrontAccounting finds
   it. Each `--with` module is mounted beside it.
2. With `--dataset demo`, replaces the database with FrontAccounting's demo
   company and adds the `test`/`test` login.
3. Runs `composer install --no-dev` in each cloned `--with` module, then `--setup`.
4. Registers and activates the `--with` modules in order, then the plugin,
   through FrontAccounting's own Setup → Install/Activate Extensions. So each
   module's `activate_extension()` and `update_*.sql` run as on a real install,
   and **a failed activation fails the run**. Then gives the `test` user a
   role of its own, `FA CI`, holding every area; role 2 stays as the dataset
   has it.
5. Runs the test command in the plugin's directory.

Commands run as your uid:gid with group `www-data` added, so they can write
to the FA tree (`config_db.php`, `company/`, `tmp/`), and files they leave in
your checkout stay yours. The environment has:
- `FA_ROOT=/var/www/html` and `FA_URL=http://localhost`;
- `FA_DB_HOST`, `FA_DB_NAME`, `FA_DB_USER` and `FA_DB_PASSWORD` (`localhost`,
  `fa_test`, `fa`, `fa`), and `FA_DB_PREFIX=0_`.

Helpers for a plugin's own setup: `fa-ci-ext-id <module>` prints a module's
extension id, which follows activation order, so derive security codes from
it: section `(id << 16) | (100 << 8)`, first area `section | 100`.
`fa-ci-grant --role <id> --module <name>` adds a module's sections and areas
to a role, e.g. role 2 for a dataset user your tests sign in as.

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
