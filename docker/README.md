# Docker test stack

A throwaway FrontAccounting install — Apache + mod_php + MariaDB — serving this
checkout, for trying a change or running the test suite without touching your
own machine's PHP or database.

    docker/fa init      # pick host ports that are free here
    docker/fa up        # build, boot, configure, seed
    docker/fa test      # run the PHPUnit suite

`up` prints the URL. With the default dataset, sign in as **test / test**.

`docker/fa help` lists every command.

## What it does to your checkout

The checkout is bind-mounted at `/var/www/html`, so an edit is live on the next
request; there is no build or sync step.

`up` writes the four files FrontAccounting needs but does not ship, because they
hold per-installation settings and are gitignored:

| file | contents |
| --- | --- |
| `config_db.php` | generated — points at the `db` service |
| `config.php` | copied from `config.default.php` if absent |
| `installed_extensions.php` | an empty extension list if absent |
| `lang/installed_languages.inc` | English only, if absent |

**It will not overwrite files you already have.** If you are already set up —
against `.devcontainer`, say — `up` leaves your configuration alone and uses it,
which also means it will be talking to whatever database that file names rather
than the one in this stack. `docker/fa config --force` replaces them, keeping a
timestamped `.bak` of each.

It also creates `tmp/` and the `company/0/` subdirectories, which `.gitignore`
keeps out of a fresh clone but FrontAccounting writes to at runtime.

Apache runs as `www-data` remapped to your uid/gid, so generated PDFs, cached JS
and uploads stay owned by you on the host. `test`, `composer`, `shell` and
`exec` run as that same user for the same reason — `docker compose exec`
otherwise runs as root, and one `composer install` would leave the whole of
`modules/tests/vendor` owned by root:root in your checkout. `docker/fa perms`
puts ownership right if it ever drifts anyway.

## Datasets

`docker/fa db load <what>` and `db reset <what>`:

| what | source | login |
| --- | --- | --- |
| `test` (default) | `modules/tests/data/fa_test.sql.gz` | test / test |
| `demo-fixture` | `modules/tests/data/fa_demo.sql.gz` | test / test |
| `new` | `sql/en_US-new.sql` | admin / password |
| `demo` | `sql/en_US-demo.sql` | admin / password |
| a path | any `.sql` or `.sql.gz` | — |

`test` is the same fixture the gulpfile's `env-db` task uses, so the PHPUnit
suite runs against a freshly seeded stack. `docker/fa db dump` writes a gzipped
dump back out.

Unlike `gulp env-test`, none of this copies fixture files over your `config.php`
or `config_db.php`.

**The database has to be called `fa_test`** for the PHPUnit suite to run at all.
`TestEnvironment::isGoodToGo()` skips every test against any other name, so that
a suite which creates and deletes transactions can never be pointed at a real
company. That is why `DB_NAME` defaults to `fa_test`; change it and `docker/fa
test` reports seven skips rather than seven passes.

If you already have a `config_db.php` from another setup, `up` keeps it and
warns that it names a different database. `docker/fa config --force` regenerates
it — worth checking what you have first if it holds more than one company.

## Settings

`docker/.env` — gitignored, written by `docker/fa init`. `docker/.env.example`
lists everything that can go in it: ports, PHP and MariaDB versions, database
name and credentials, the seed dataset, xdebug.

The stack is named after the checkout directory, so a worktree gets its own
containers and its own database volume rather than colliding with the main
checkout.

## Base image and PHP version

Debian **trixie** (13), with PHP from [Ondřej Surý's
repository](https://deb.sury.org/) rather than the official `php` images.

Those images only ship 7.4 on Debian bullseye, whose LTS ended on 2026-08-31 —
`deb.debian.org` still serves the `bullseye-security` index but no longer the
packages it points at, so a build off that base has to be pointed at
`archive.debian.org` and is frozen there. There is no 7.4 image on trixie and
there will not be; PHP 7.4 itself went end-of-life in 2022. Building on trixie
and taking PHP from sury keeps the OS supported and patched while
FrontAccounting stays on the version it is written against.

`PHP_VERSION` defaults to **7.4** and accepts anything sury publishes for trixie
(7.4, 8.0 … 8.4). FrontAccounting 2.4.x is written against PHP 5.4-7.x, so 7.4
is the newest it is known to run on; `PHP_VERSION=8.3 docker/fa up --build`
works if you want to see what breaks, but expect deprecation noise and real
failures in core.

Debian's PHP packaging differs from the official images in two ways that matter
here: there is a separate `conf.d` per SAPI, so `php.ini` is installed into both
the `apache2` and `cli` trees (the test suite runs under the latter), and
extensions are toggled with `phpenmod`/`phpdismod` rather than by moving ini
files about.

## Debugging

xdebug is compiled in but **not loaded** unless you ask for it. That is not just
tidiness: FrontAccounting guards its xdebug calls with
`function_exists('xdebug_call_file')` (`includes/db/connect_db_mysqli.inc`, in
the `$go_debug` branch that runs on *every* query). Under xdebug 3 that guard is
wrong — the function exists whenever the extension is loaded but throws unless
`xdebug.mode` includes `develop`, so an extension sitting at `mode=off` breaks
every request and every test. The entrypoint therefore disables the extension
outright when `XDEBUG_MODE` is `off`.

To use it, set `XDEBUG_MODE=debug` in `docker/.env` and run **`docker/fa up`** —
not `restart`, which keeps the existing container and its old environment. Then
listen on port 9003; it starts on trigger, so set an `XDEBUG_TRIGGER` cookie or
query parameter. `XDEBUG_MODE=coverage` is what `docker/fa test --coverage-html
tmp/coverage` needs.

`docker/fa` folds `develop` into whatever mode you ask for, so `debug` becomes
`develop,debug`. That is the same trap from the other side: with the extension
loaded but the mode lacking `develop`, `xdebug_call_file()` exists and throws,
and the suite goes back to erroring 7/7.

`docker/fa logs errors` follows FrontAccounting's own `tmp/errors.log`;
`docker/fa logs app` follows Apache's.

## Not included

The Protractor end-to-end suite. It is pinned to node 10 and selenium 3 (see
`modules/tests/README.md`) and wants a browser and a webdriver alongside; the
gulp tasks still drive it on the host. Only the PHPUnit side runs here.

## Relationship to `.devcontainer`

`.devcontainer` is for editing inside VS Code: it mounts the checkout, installs
the PHP tooling and leaves you to start a server by hand. This stack is for
running the application and its tests from the terminal, on any machine with
docker, without VS Code. They can coexist; they do not share containers, and
each will generate its own `config_db.php` if you let it.
