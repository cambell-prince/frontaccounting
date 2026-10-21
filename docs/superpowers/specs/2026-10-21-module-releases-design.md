# Versioned module releases

Status: agreed in conversation on 2026-10-21 (sections 1-3 approved one by one).

## Purpose

Four FrontAccounting extensions are deployed to bms.saygoweb.com: graphql,
mcp, sgw_sales and sgw_import. None of them carries a version that FrontAccounting can
show. Releases, where they exist, were built by hand with an old gulp runner
(`package.json`, `gulpfile.js`) that archived the whole working tree. That is
how database dumps and bank CSVs reached sgw_import's public release assets.
Those assets were cleaned on 2026-10-21.

After this work:

- A release is a pushed `v<semver>` tag. CI builds it and publishes a GitHub
  release with a `.tgz` and a `.zip`, named by the existing convention.
- Every build, whether a release, the bms deploy or a local package, gets its
  version from git. Nobody edits a version by hand.
- Setup → Install/Activate Extensions shows each module's version. It stays
  current after upgrades, both on this fork of FrontAccounting and on stock FA
  2.4.
- Packaging is driven by composer scripts. `package.json`, gulp and npm are
  gone.
- A package contains only tracked files, so private data can't get in.

## Scope

In scope:

- `docker/ci/fa-module` and `.github/workflows/plugin-release.yml` in this
  repository.
- The change to `deploy/build-release.sh`.
- The `admin/inst_module.php` patch.
- In each of the four modules: composer scripts, `release.yml`,
  `.gitattributes`, `.gitignore`, the activate hook, and a README "Releasing"
  section.
- Removing gulp and npm from sgw_sales and sgw_import.

Out of scope:

- Uploading packages to FrontAccounting's own package repository.
- Automatic version bumps from commit messages. Releases are tag-driven.
- Modules other than these four.
- Offering the `inst_module.php` patch upstream. It may happen later, but
  nothing depends on it.

## §1 Version rule and naming

### Tags

- A release is a tag `v<major>.<minor>.<patch>` on the module's deploy branch:
  `main` for graphql and mcp, `master` for sgw_sales and sgw_import.
- New tags always use `v`. For sgw_import's history, bare tags (`1.2.1`) also
  count when working out the version.

First releases:

| Module | First tag | Previous |
|---|---|---|
| graphql | `v1.0.0` | none ("Release 4" in its README was a development phase, not a version) |
| mcp | `v1.0.0` | none (its CHANGELOG already says "Unreleased - 1.0.0") |
| sgw_sales | `v1.6.0` | tags up to `v1.5` |
| sgw_import | `v1.3.0` | `1.2.1` |

### Module version M

`git describe --tags --long --match 'v[0-9]*' --match '[0-9]*'`, with the
leading `v` removed:

| State | M |
|---|---|
| On a tag | `1.4.0` |
| n commits after a tag | `1.4.0-3-gabc1234` |
| Uncommitted changes (local builds only) | `+dirty` added, for example `1.4.0-3-gabc1234+dirty` |
| No tag reachable | `0.0.0-<n>-g<sha7>`, with n being every commit in the history |

A shallow clone can't be described reliably, so `fa-module` refuses one
(`git rev-parse --is-shallow-repository`) and doesn't guess.

### Full version

`<FA_LINE>-<M>`, for example `2.4-1.4.0`.

- `FA_LINE` is a single setting in `docker/ci/fa-module`, currently `2.4`.
  It names the FrontAccounting release line the module is built for. Moving to
  FA 2.5 is a one-line change.
- FrontAccounting's `check_src_ext_version()` compares the leading numeric
  part (`2.4`) with the application's major.minor and refuses to activate a
  lower version. Putting the FA line first keeps activation working.

### `_init/config`

FrontAccounting reads a local extension's name and version from
`modules/<id>/_init/config`, a control file of `Key: value` lines:

```
Package: sgw_import
Name: sgw_import
Version: 2.4-1.3.0
```

- `Package` is the module's folder name (its FA extension id).
- `Name` is `composer.json` `extra.fa-module.name` if set, otherwise the folder
  name.
- The file is generated at build time and never committed. `_init/` is in
  each module's `.gitignore`.

### Package files

- Names: `frontaccounting-<FA_LINE>-<module>.module.<M>.tgz` and `.zip`, for
  example `frontaccounting-2.4-sgw_import.module.1.3.0.tgz`.
- The module's files are at the archive root with no wrapper directory, as in
  the earlier releases.
- Both archives hold the same set of files.

## §2 Components

### In this repository (`master-cp`, merged into `master-ark`)

#### `docker/ci/fa-module`

A POSIX shell script. Each command takes the module directory as an optional
argument, defaulting to the current directory.

- `fa-module version [dir]` prints M on the first line and the full version on
  the second.
- `fa-module config [dir]` writes `<dir>/_init/config`.
- `fa-module package [dir] [out]` builds both archives into `out` (default
  `<dir>/build/dist`) and prints their paths. Steps:
  1. Work out the version. Stop if the tree has uncommitted changes, unless
     `--allow-dirty` is given.
  2. `git archive HEAD` into a temporary staging directory. Only tracked files
     are included, and `export-ignore` paths in `.gitattributes` are dropped.
  3. If there is a `composer.json`, run
     `composer install --no-dev --optimize-autoloader --no-interaction` in the
     staging directory. Stock FA users have no composer, so `vendor/` ships in
     the package. If composer isn't on the host, run it in the `composer:2`
     image, as `build-release.sh` already does.
  4. Write `_init/config` into the staging directory.
  5. Create the `.tgz` (`tar -czf`) and `.zip` (`zip -r -y -q`) from the
     staging root.

Module composer scripts reach the script as `../../docker/ci/fa-module`.
Modules are developed inside a FrontAccounting checkout at `modules/<id>`, so
this path always resolves there.

#### `.github/workflows/plugin-release.yml`

A reusable workflow, next to `plugin-test.yml`.

- **Inputs:** `module` (the folder name) and `deploy-branch`.
- **Steps:**
  1. Check out the module with `fetch-depth: 0` and tags, and check out this
     repository's CI package.
  2. Check the tag is `v<semver>` and that the tagged commit is an ancestor of
     `origin/<deploy-branch>`.
  3. Check no release for the tag exists yet.
  4. Run `fa-module package`.
  5. Run `gh release create <tag> <tgz> <zip> --title "<module> <M>"`. The
     notes are the CHANGELOG section headed with that version if there is
     one, otherwise `--generate-notes`.
- **Permissions:** `contents: write` on the calling repository only.

#### `deploy/build-release.sh`

- Fetch each component with history and tags instead of `--depth 1`, using
  `git fetch --filter=blob:none --tags` (a partial clone, so the history is
  cheap).
- Run `docker/ci/fa-module config` on the checkout before `rm -rf .git`.
- Add the component's full version to its manifest line.
- A component whose config step fails fails the build, so nothing is
  uploaded.

#### `admin/inst_module.php`

When the extensions table shows an installed local extension, one whose
stored entry has `path` `modules/<id>` and that isn't a package from FA's
repository:

- read `modules/<id>/_init/config` with `get_control_file()`;
- if its `Version` differs from the stored `version`, show the new one and
  save it with `update_extensions()`.

This covers upgrades deployed by file sync, which never pass through
`local_extension()`.

### In each module

- **Composer scripts:**
  - `"fa:version": "sh ../../docker/ci/fa-module version"`
  - `"fa:package": "sh ../../docker/ci/fa-module package"`
- **`.github/workflows/release.yml`:** runs on `push: tags: ['v*']`. It runs
  the same CI jobs as `ci.yml` (the `plugin-test.yml` calls), then
  `plugin-release.yml` with `needs:` on all of them, so a red commit never
  releases.
- **`.gitattributes`:** `export-ignore` for `tests/`, `tools/`, `docs/`,
  `.github/`, `phpunit*.xml`, `phpcs.xml`, `phpstan*.neon`,
  `phpstan-baseline.neon`, `codecov.yml`, `.gitattributes`, `.gitignore`, and
  any module-specific development files. `composer.json` and `composer.lock`
  stay in the package.
- **`.gitignore`:** add `_init/` and `build/dist/`.
- **`hooks.php` `activate_extension()`:** refresh this module's own stored
  version from `_init/config`. It finds its own entry in the company's
  installed extensions and updates `version` if it differs. This covers stock
  FA 2.4, which lacks the `inst_module.php` patch. Each module has the same
  small helper, about 15 lines, and it runs before the module's existing
  activation steps.
- **README:** a "Releasing" section: tag `vX.Y.Z` on the deploy branch and
  push the tag; CI tests, packages and publishes.
- **sgw_sales and sgw_import only:** delete `package.json`,
  `package-lock.json`, `gulpfile.js`, `node_modules/` (if tracked) and
  `upload-exclude*.txt`. The gulp `upload` and database tasks go with them;
  the GitHub deploy replaces `upload`. Remove `node_modules` from the lint
  scripts' prune lists if nothing else needs it.

## §3 Failures, testing and rollout

### Failures

- **`fa-module`** stops with a message and builds nothing when:
  - it's run outside a git repository;
  - the clone is shallow;
  - there are uncommitted changes without `--allow-dirty`;
  - `composer install` fails;
  - `tar` or `zip` is missing.
- **`plugin-release.yml`** refuses to publish when:
  - the tag isn't `v<semver>`;
  - the tagged commit isn't on the deploy branch;
  - CI fails;
  - a release for that tag already exists. It never overwrites; a broken
    release is fixed with a new patch tag.
- **The `inst_module.php` patch and the activate hook** leave the stored
  version unchanged if `_init/config` is missing or unreadable. A module built
  without it shows "Unknown", as today.
- **`build-release.sh`** fails before uploading if `fa-module config` fails for
  any component.

### Testing

- **`fa-module`:** shell tests alongside the existing `deploy/` script tests,
  against a temporary git repository with tags:
  - M on a tag, after a tag, with no tag, with uncommitted changes, with a
    bare tag (`1.2.1`), and in a shallow clone (refused);
  - the `_init/config` contents, including `extra.fa-module.name`;
  - an untracked `backup/x.sql.gz` and an ignored `uploads/x.csv` never
    appear in either archive;
  - `export-ignore` paths are left out;
  - both archives list the same files at the root, and their names follow
    the convention.
- **`build-release.sh`:** the existing tests are extended so that a
  component's `_init/config` exists in the release and the manifest names its
  version.
- **`inst_module.php`:** a test of the version refresh through FA's existing
  test setup if `inst_module.php` can be reached from it. Otherwise a
  manual check in the plugin-dev environment, recorded in the PR.
- **Activate hook:** a unit test in each module that it rewrites only its own
  entry.
- **Release workflow:** each module's first tag is the real test. Check the
  GitHub release's file names, that both archives list the same files, that
  there are no private files, and that `_init/config` has the right version.

### Rollout

1. **This repository:** `fa-module` with its tests, `plugin-release.yml`, the
   `build-release.sh` change and the `inst_module.php` patch, merged into
   `master-cp`. Merging `master-cp` into `master-ark` deploys bms.
   - Check Install/Activate Extensions on bms. Untagged modules show
     `2.4-0.0.0-<n>-g<sha>`, which proves the patch and the deploy path work.
2. **mcp first:** composer scripts, `.gitattributes`, `.gitignore`, the
   activate hook, `release.yml` and the README section. Then push `v1.0.0` and
   check the release.
3. **Then graphql (`v1.0.0`), sgw_sales (`v1.6.0`) and sgw_import (`v1.3.0`),**
   in that order. For sgw_sales and sgw_import this includes removing gulp
   and npm.
4. **After each first release,** a deploy shows the tagged version on bms's
   extensions screen.
