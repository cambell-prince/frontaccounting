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
| `deploy-previous` | fetch the server's `.deploy-manifest`, the record of the last deploy, to `build/release.previous` |
| `db-backup` | dump the server's database to `backup/<db>-<stamp>.sql.gz` over ssh |
| `db-load file=...` | load a dump into the docker test stack (`docker/fa db reset`) |
| `test` | the PHPUnit suite in the docker stack (`docker/fa test`) |
| `clean` | remove `build/` and make.phar's `log/` |

Every variable in `makefile.json` can be overridden on the command line, for
example `make.phar release ref=v2.4.20` or `make.phar deploy-check user=me`. A
site's own branch sets its values in `makefile.json`: `user`, `host` and `path`
(the destination is `user@host:path`, and `path` ends with `/`),
`remote_user`, `components`, `db_ssh` and `db`.

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
- `deploy-check max_deletes=<n>` fails if more than `n` files would be
  deleted. The GitHub deploy uses 25.

`deploy-check` prints every file the server would lose and writes the full
itemised list to `build/release.check`. Read it before `deploy`.

Every release carries its manifest as `.deploy-manifest`, so the server's copy
names the commits it is running.

`install/` and `sql/` are never uploaded. If the server has an `install/`
directory from the original installation, delete it by hand.

## Deploying bms from GitHub

`.github/workflows/deploy-bms.yml` deploys bms.saygoweb.com. It lives on
`master-cp`, the default branch, because GitHub only runs `workflow_run` and
`repository_dispatch` workflows from there. It builds from `master-ark`. It
runs when:

- the CI image workflow succeeds on a push to `master-ark`;
- an extension's `notify-deploy.yml` sends `extension-green` after its CI
  succeeds on its deploy branch;
- someone runs it by hand.

Each run pins FrontAccounting and every extension in `master-ark`'s
`components` to its newest commit that passed CI (`deploy/resolve-refs.sh`).
It then builds the release, lists any `sql/` changes since the server's
`.deploy-manifest` (`deploy/sql-changes.sh`), runs `deploy-check` with a limit
of 25 deletes, and uploads. Runs queue one behind another.

The `bms` environment holds:

| name | kind | value |
| --- | --- | --- |
| `BMS_SSH_KEY` | secret | the deploy key, forced on the server through `rrsync <site directory>` |
| `BMS_KNOWN_HOSTS` | secret | the server's pinned host key |
| `DEPLOY_USER`, `DEPLOY_HOST` | variables | the site user and the server |
| `DEPLOY_PATH` | variable | `/`. rrsync roots it at the site directory, so `bms/htdocs/` would land in `bms/htdocs/bms/htdocs/`. |
| `DEPLOY_LIVE` | variable | `true` lets automatic runs deploy; anything else keeps them dry |

The extensions dispatch with `FA_DEPLOY_DISPATCH`, a saygoweb organisation
secret. It is a fine-grained token with Contents read/write on this
repository only.

By hand:

    gh workflow run deploy-bms.yml -R cambell-prince/frontaccounting                  # dry run
    gh workflow run deploy-bms.yml -R cambell-prince/frontaccounting -f dry_run=false
    gh workflow run deploy-bms.yml -R cambell-prince/frontaccounting -f dry_run=false \
        -f refs="modules/sgw_sales=<sha>"                                             # pin a part

To roll back, revert the bad commit; its CI deploys the revert. To stop
deploys, `gh workflow disable deploy-bms.yml -R cambell-prince/frontaccounting`.
Database changes are never applied by the deploy: the run's summary lists
them. When a component resolves to its last green commit rather than its head,
the summary's "What was resolved" section says so.
