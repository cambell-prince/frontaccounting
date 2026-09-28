# Building and deploying

Deployment is driven by [`make.phar`](https://github.com/saygoweb/phpmake) from
`makefile.json` at the top of the checkout. Run every target from there.

    make.phar release          # build a clean tree in build/release
    make.phar deploy-check     # dry run: what would change on the server
    make.phar deploy confirm=yes

Other targets:

| target | what it does |
| --- | --- |
| `package` | `build/frontaccounting-<version>.tgz` of the built release, for a fresh install (it keeps `install/`, `sql/` and the `company/` and `tmp/` skeletons that deploy leaves out) |
| `db-backup` | dump the server's database to `backup/<db>-<stamp>.sql.gz` over ssh |
| `db-load file=...` | load a dump into the docker test stack (`docker/fa db reset`) |
| `test` | the PHPUnit suite in the docker stack (`docker/fa test`) |
| `clean` | remove `build/` and make.phar's `log/` |

Every variable in `makefile.json` can be overridden on the command line, for
example `make.phar release ref=v2.4.20` or `make.phar deploy-check dest=...`. A
site's own branch sets its values in `makefile.json`: `dest`, `remote_user`,
`components`, `db_ssh` and `db`.

## What a release is

`release` builds the tree to upload in `build/release`, so the checkout you work
in is never what gets deployed:

- FrontAccounting is `git archive` of `ref` (default `HEAD`). Only committed
  files go in, and nothing from `.gitattributes`' `export-ignore`. Local config,
  editor and agent directories, worktrees and scratch files stay behind.
- Each entry in `components` (`path|repo|ref[|composer]`, space-separated) is a
  fresh `git clone` of an extension or theme at that ref. If it has a
  `composer.json`, its dependencies are installed in the `composer:2` docker
  image, resolved for the server's PHP (`php`, default 7.4.33):
  - `nodev` (the default): install from the lock, without dev packages.
  - `dev`: install from the lock, with dev packages.
  - `legacy`: resolve afresh and accept packages with security advisories.
    Use it only for a component composer 2 otherwise refuses.
- `build/release.manifest` records what went in: each commit and how composer
  ran.

make.phar runs the remaining commands even after one fails, so `release`
writes `build/release.ok` only once everything has succeeded, and
`deploy-check` and `deploy` refuse to run without it.

## What deploy does to the server

It runs rsync with `--delete`, so the server ends up matching the release,
with three exceptions:

- Anything `upload-exclude.txt` names is neither sent nor deleted. That covers
  `config.php`, `config_db.php`, `installed_extensions.php`, `company/`, `tmp/`,
  `lang/installed_languages.inc`, extension settings such as
  `modules/graphql/config_graphql.php`, and uploads. Anchor a new pattern with
  `/` unless you mean every depth; an unanchored `sql/` would also exclude
  every extension's `sql/` directory.
- A top-level entry of `modules/`, `themes/` or `lang/` that exists on the
  server but not in the release is protected. Extensions, themes and languages
  installed on the server survive a deploy that doesn't carry them. Stale
  files inside the ones it does carry are still removed.
- `deploy` needs `confirm=yes`.

`deploy-check` prints every file the server would lose and writes the full
itemised list to `build/release.check`. Read it before `deploy`.

`install/` and `sql/` are never uploaded. If the server has an `install/`
directory from the original installation, delete it by hand.
