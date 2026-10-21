# Versioned Module Releases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use cjp:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task, wave by wave per the Execution Schedule. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every FrontAccounting module build gets a version from git. Tagged
builds become GitHub releases (`.tgz` and `.zip`), and the version shows on
FrontAccounting's Install/Activate Extensions screen.

**Architecture:**
- **One shell script, `docker/ci/fa-module`, in the FrontAccounting repo.** It
  works out a module's version, writes `_init/config`, and builds the archives.
  Module composer scripts, the new reusable `plugin-release.yml` and
  `deploy/build-release.sh` all call it.
- **The screen keeps the version current in two ways.** A small core patch to
  `admin/inst_module.php` covers this fork; a per-module activate hook covers
  stock FA 2.4.

**Tech Stack:** POSIX sh, git, tar/zip, composer 2, GitHub Actions, PHP
7.4–8.3 (FrontAccounting 2.4.20).

**Spec:** `docs/superpowers/specs/2026-10-21-module-releases-design.md`. Read it
before starting any task.

## Global Constraints

- **`FA_LINE=2.4`:** the full version is `2.4-<M>`.
- **Package names:** `frontaccounting-2.4-<module>.module.<M>.tgz` and `.zip`.
  Files go at the archive root, with no wrapper directory.
- **Tags:** `v<major>.<minor>.<patch>`. Bare old tags (`1.2.1`) and two-part
  old tags (`v1.5`) still count when working out a version.
- **M:**
  - `X.Y.Z` on a tag;
  - `X.Y.Z-<n>-g<sha7>` after a tag;
  - `+dirty` appended for uncommitted tracked changes;
  - `0.0.0-<n>-g<sha7>` with no tag.
- **Shallow clones are refused.**
- **`_init/config`:** `Package: <id>`, `Name: <name>`, `Version: 2.4-<M>`, then a
  blank line. FA's `get_control_file()` ends a section on a blank line.
  - `Name` is `composer.json` `extra.fa-module.name`, otherwise the folder name.
  - The file is never committed; `_init/` goes in each module's `.gitignore`.
- **Package contents:** tracked files only (`git archive`), less `export-ignore`
  paths, plus `vendor/` from `composer install --no-dev --optimize-autoloader`
  resolved for `FA_PHP=7.4.33`.
- **Deploy branches:** `main` for graphql and mcp, `master` for sgw_sales and
  sgw_import.
- **First tags:** graphql `v1.0.0`, mcp `v1.0.0`, sgw_sales `v1.6.0`,
  sgw_import `v1.3.0`.
- **Releases never overwrite** an existing release for the same tag.
- **Public repos:** no real customer, business or bank data in code, tests,
  commits, PRs or release assets.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  **PR bodies** end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
  `gh pr create` always passes `-R <owner/repo>`.
- **Auto-deploy is live:**
  - a green push to `master-ark`, or to any module's deploy branch, deploys
    bms;
  - only merge when fully green;
  - never run deploys by hand.
- **Thermal:**
  - at most one docker gate run per worker, and at most 2 workers at a time;
  - cap phpunit parallelism;
  - check `sensors | egrep "Package|RPM"` before long runs, and pause above
    about 95°C.

## Review Focus

1. **A module checkout under a different folder name** (CI checks out to
   `$GITHUB_WORKSPACE/<path>`). `Package:` and the archive name must use the
   module id, not whatever folder it happens to be in. `fa-module` takes the
   id from the directory's basename, so `plugin-release.yml` must check out to
   a folder named exactly `<module>`. A test in Task 1 pins basename-derived
   naming.
2. **`--allow-dirty` packages must contain the uncommitted tracked change**,
   not HEAD, or a local test package silently lies. Task 1 uses
   `git stash create` and tests it.
3. **`get_control_file()` misreading the last line.** Without a trailing blank
   line, the last key (`Version`) may be dropped. Task 1 tests the file ends
   with a blank line, and Task 3 reads a generated file back with
   `get_control_file()`.
4. **Two-part and bare legacy tags** (`v1.5` in sgw_sales, `1.2.1` in
   sgw_import) must give a version, not an error. Task 1 tests both.
5. **The screen and hook patches with a missing or garbled `_init/config`**
   must leave the stored version alone and raise no error. Tasks 3 and 5–8
   test it.

## Execution Schedule

| Wave | Tasks | Model | Notes |
|------|-------|-------|-------|
| 1 | Task 1, Task 3 | sonnet, sonnet | Parallel: Task 1 is `docker/ci/fa-module` plus `deploy/test/fa-module.sh`; Task 3 is `admin/inst_module.php` plus its test. Disjoint files, no shared resource (Task 3's FA test may use one docker dev env). |
| 2 | Task 2, Task 4 | sonnet, sonnet | Parallel: Task 2 is `deploy/build-release.sh` and its test; Task 4 is `.github/workflows/plugin-release.yml` and the `deploy-test.yml` paths. Both consume `fa-module` from Task 1. |
| CP1 | — | — | base..end of wave 2: code-review medium plus spec check (spec §1, §2 "In this repository", §3). Must finish before the FA PR merges. |
| 2b | Controller | — | FA PR (master-cp): spec, plan, Tasks 1–4. CI green, squash-merge. Then merge `master-cp` into `master-ark` and push, which deploys. Check bms's extensions screen shows `2.4-0.0.0-…` versions once modules have `_init/config` from the deploy. |
| 3 | Task 5 (mcp) | sonnet | Alone: the first module proves `plugin-release.yml` end to end (spec rollout step 2). Includes PR, merge, tag `v1.0.0`, and checking the release. |
| 4 | Task 6 (graphql), Task 7 (sgw_sales) | sonnet, sonnet | Parallel: different repos; one docker gate each. |
| 5 | Task 8 (sgw_import) | sonnet | |
| CP2 | — | — | All four module PRs plus the FA PR: code-review medium plus spec check (full spec); check the four GitHub releases. |
| 6 | Controller | — | Report: release URLs, bms extensions screen versions. |

---

### Task 1: `docker/ci/fa-module`

**Files:**
- Create: `docker/ci/fa-module` (mode 755; `core.fileMode` is off in this
  repo, so set it with `git update-index --chmod=+x docker/ci/fa-module`)
- Create: `deploy/test/fa-module.sh`
- Modify: `docker/ci/README.md` (a short "fa-module" section: the commands and
  where they're used)

**Interfaces:**
- Produces:
  - `sh docker/ci/fa-module version [dir]` prints M on line 1 and
    `2.4-<M>` on line 2.
  - `sh docker/ci/fa-module config [dir]` writes `<dir>/_init/config`.
  - `sh docker/ci/fa-module package [--allow-dirty] [dir] [out]` writes
    `<out>/frontaccounting-2.4-<id>.module.<M>.tgz` and `.zip`, prints both
    absolute paths one per line, and exits 0. `out` defaults to
    `<dir>/build/dist`.
  - Any failure exits 1 with `fa-module: <message>` on stderr.
  - `<id>` is the basename of the module directory.

- [ ] **Step 1: Write the failing tests** in `deploy/test/fa-module.sh`:

```bash
#!/usr/bin/env bash
#
# docker/ci/fa-module against local fixture repositories: the version rule,
# _init/config, and packages that hold only tracked, non-export-ignored files.
# No network. composer is skipped: the fixture module has no composer.json,
# except in the one test that checks composer.json survives packaging.
#
#   deploy/test/fa-module.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=../../docker/ci/test/lib.sh
. "$here/../../docker/ci/test/lib.sh"
root="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fam() { sh "$root/docker/ci/fa-module" "$@"; }

mkmod() { # mkmod <dir>: a module repository with one commit
    git init -q -b main "$1"
    git -C "$1" config user.email test@example.com
    git -C "$1" config user.name test
    echo '<?php' > "$1/hooks.php"
    mkdir -p "$1/tests"; echo t > "$1/tests/a.txt"
    printf 'tests export-ignore\n.gitattributes export-ignore\n' > "$1/.gitattributes"
    printf '_init/\nbuild/\nbackup/\n' > "$1/.gitignore"
    git -C "$1" add -A; git -C "$1" commit -qm first
}

m="$work/demo_mod"; mkmod "$m"
sha() { git -C "$m" rev-parse --short=7 HEAD; }

expect_status 0 "no tag: version works" fam version "$m"
expect_contains "no tag: 0.0.0-<count>-g<sha>" "0.0.0-1-g$(sha)" "$OUT"
expect_contains "full version has the FA line" "2.4-0.0.0-1-g$(sha)" "$OUT"

git -C "$m" tag v1.4.0
expect_status 0 "on a tag" fam version "$m"
expect_contains "on a tag: plain version" "$(printf '1.4.0\n2.4-1.4.0')" "$OUT"

echo x >> "$m/hooks.php"; git -C "$m" commit -qam second
echo y >> "$m/hooks.php"; git -C "$m" commit -qam third
expect_status 0 "after a tag" fam version "$m"
expect_contains "after a tag: tag-n-gsha" "1.4.0-2-g$(sha)" "$OUT"

echo z >> "$m/hooks.php"
expect_status 0 "dirty" fam version "$m"
expect_contains "dirty: +dirty" "1.4.0-2-g$(sha)+dirty" "$OUT"
git -C "$m" checkout -q hooks.php
echo u > "$m/untracked.txt"
expect_status 0 "untracked files are not dirt" fam version "$m"
expect_absent "no +dirty for untracked" "+dirty" "$OUT"
rm "$m/untracked.txt"

b="$work/legacy_bare"; mkmod "$b"; git -C "$b" tag 1.2.1
expect_status 0 "bare legacy tag" fam version "$b"
expect_contains "bare tag counts" "2.4-1.2.1" "$OUT"
t="$work/legacy_two"; mkmod "$t"; git -C "$t" tag v1.5
expect_status 0 "two-part legacy tag" fam version "$t"
expect_contains "two-part tag counts" "2.4-1.5" "$OUT"

git clone -q --depth 1 "file://$m" "$work/shallow"
expect_status 1 "shallow clone refused" fam version "$work/shallow"
expect_contains "says why" "shallow" "$OUT"
expect_status 1 "not a repo refused" fam version "$work"

git -C "$m" tag v1.5.0
expect_status 0 "config" fam config "$m"
cfg="$(cat "$m/_init/config"; echo END)"
expect_contains "config: package" "Package: demo_mod" "$cfg"
expect_contains "config: name defaults to id" "Name: demo_mod" "$cfg"
expect_contains "config: version" "Version: 2.4-1.5.0" "$cfg"
expect_contains "config ends with a blank line" "$(printf '2.4-1.5.0\n\nEND')" "$cfg"

n="$work/named_mod"; mkmod "$n"
printf '{"name":"x/y","extra":{"fa-module":{"name":"Nice Name"}}}\n' > "$n/composer.json"
git -C "$n" add composer.json; git -C "$n" commit -qm composer
expect_status 0 "config with extra.fa-module.name" fam config "$n"
expect_contains "config: name from composer.json" "Name: Nice Name" "$(cat "$n/_init/config")"

mkdir -p "$m/backup" "$m/uploads"
echo secret > "$m/backup/x.sql.gz"; echo secret > "$m/uploads/x.csv"
out="$work/dist"
expect_status 0 "package" fam package "$m" "$out"
tgz="$out/frontaccounting-2.4-demo_mod.module.1.5.0.tgz"
zip="$out/frontaccounting-2.4-demo_mod.module.1.5.0.zip"
expect_contains "prints the tgz path" "$tgz" "$OUT"
expect_contains "prints the zip path" "$zip" "$OUT"
tl="$(tar -tzf "$tgz" | sed 's,/$,,' | sort)"
zl="$(unzip -Z1 "$zip" | sed 's,/$,,' | sort)"
expect_status 0 "both archives list the same files" test "$tl" = "$zl"
expect_contains "hooks.php at the root" "hooks.php" "$tl"
expect_contains "_init/config included" "_init/config" "$tl"
expect_absent "no wrapper dir or ./" "./" "$tl"
expect_absent "untracked backup/ never packaged" "backup" "$tl"
expect_absent "ignored uploads/ never packaged" "uploads" "$tl"
expect_absent "export-ignore tests/ left out" "tests" "$tl"
expect_contains "packaged config has the version" "Version: 2.4-1.5.0" "$(tar -xOzf "$tgz" _init/config)"

echo dirty >> "$m/hooks.php"
expect_status 1 "dirty package refused" fam package "$m" "$out"
expect_contains "says how" "--allow-dirty" "$OUT"
expect_status 0 "--allow-dirty packages" fam package --allow-dirty "$m" "$out"
dtgz="$out/frontaccounting-2.4-demo_mod.module.1.5.0+dirty.tgz"
expect_contains "--allow-dirty packs the working tree" "dirty" "$(tar -xOzf "$dtgz" hooks.php)"
git -C "$m" checkout -q hooks.php

finish
```

- [ ] **Step 2: Run the tests to check they fail**

Run: `bash deploy/test/fa-module.sh`
Expected: FAIL. Every `fam` call fails because `docker/ci/fa-module` doesn't
exist.

- [ ] **Step 3: Write `docker/ci/fa-module`**

```sh
#!/bin/sh
#
# fa-module: a FrontAccounting module's version, _init/config and release
# packages, from its git history
# (docs/superpowers/specs/2026-10-21-module-releases-design.md).
#
#   fa-module version [dir]                       M, then <FA_LINE>-<M>
#   fa-module config [dir]                        write <dir>/_init/config
#   fa-module package [--allow-dirty] [dir] [out] the .tgz and .zip in out
#                                                 (default <dir>/build/dist)
#
# <dir> defaults to the current directory; its basename is the module's id.

set -eu

FA_LINE=2.4      # the FrontAccounting release line modules are built for
FA_PHP=7.4.33    # the PHP a package's vendor/ is resolved for

die() { echo "fa-module: $*" >&2; exit 1; }

# module_version <dir>: M (spec §1)
module_version() {
    d=$1
    git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || die "$d is not a git repository"
    [ "$(git -C "$d" rev-parse --is-shallow-repository)" = false ] \
        || die "$d is a shallow clone: fetch its history and tags (git fetch --unshallow --tags)"
    if desc="$(git -C "$d" describe --tags --long --abbrev=7 --match 'v[0-9]*' --match '[0-9]*' 2>/dev/null)"; then
        sha=${desc##*-}; rest=${desc%-*}; n=${rest##*-}; tag=${rest%-*}; tag=${tag#v}
        case $tag in ''|*[!0-9.]*) die "tag '$tag' is not a version" ;; esac
        if [ "$n" = 0 ]; then m=$tag; else m="$tag-$n-$sha"; fi
    else
        m="0.0.0-$(git -C "$d" rev-list --count HEAD)-g$(git -C "$d" rev-parse --short=7 HEAD)"
    fi
    [ -z "$(git -C "$d" status --porcelain --untracked-files=no)" ] || m="$m+dirty"
    echo "$m"
}

# module_name <dir> <id>: composer.json extra.fa-module.name, else <id>
module_name() {
    name=''
    if [ -f "$1/composer.json" ] && command -v php >/dev/null 2>&1; then
        name="$(php -r '$j = json_decode(file_get_contents($argv[1]), true);
            echo isset($j["extra"]["fa-module"]["name"]) ? $j["extra"]["fa-module"]["name"] : "";' "$1/composer.json")"
    fi
    echo "${name:-$2}"
}

# write_config <module dir> <target dir> <M>
write_config() {
    id=$(basename "$1")
    mkdir -p "$2/_init"
    printf 'Package: %s\nName: %s\nVersion: %s-%s\n\n' "$id" "$(module_name "$1" "$id")" "$FA_LINE" "$3" > "$2/_init/config"
}

composer_install() { # composer_install <dir>
    cp "$1/composer.json" "$1/.composer.json.orig"
    if command -v composer >/dev/null 2>&1; then
        (cd "$1" && composer config platform.php "$FA_PHP" \
            && composer install --no-dev --optimize-autoloader --no-interaction --no-progress)
    else
        docker run --rm -u "$(id -u):$(id -g)" -v "$1":/app -w /app composer:2 sh -c \
            "composer config platform.php '$FA_PHP' && composer install --no-dev --optimize-autoloader --no-interaction --no-progress"
    fi || { mv "$1/.composer.json.orig" "$1/composer.json"; die "composer install failed"; }
    mv "$1/.composer.json.orig" "$1/composer.json"
}

package() {
    allow_dirty=false
    if [ "${1:-}" = --allow-dirty ]; then allow_dirty=true; shift; fi
    d="$(cd "${1:-.}" && pwd)"
    out="${2:-$d/build/dist}"
    for tool in git tar zip; do command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"; done
    m="$(module_version "$d")"
    tree=HEAD
    case $m in
        *+dirty)
            $allow_dirty || die "$d has uncommitted changes: commit them, or pass --allow-dirty"
            tree="$(git -C "$d" stash create)" ;;
    esac
    id=$(basename "$d")
    stage="$(mktemp -d)"
    trap 'rm -rf "$stage"' EXIT
    git -C "$d" archive --format=tar "$tree" | tar -x -C "$stage"
    [ ! -f "$stage/composer.json" ] || composer_install "$stage"
    write_config "$d" "$stage" "$m"
    mkdir -p "$out"; out="$(cd "$out" && pwd)"
    base="frontaccounting-$FA_LINE-$id.module.$m"
    rm -f "$out/$base.tgz" "$out/$base.zip"
    (cd "$stage" && ls -A | tar -czf "$out/$base.tgz" -T -)
    (cd "$stage" && zip -r -y -q "$out/$base.zip" .)
    echo "$out/$base.tgz"
    echo "$out/$base.zip"
}

cmd="${1:-}"; [ $# -eq 0 ] || shift
case $cmd in
    version) d="$(cd "${1:-.}" && pwd)"; m="$(module_version "$d")"; echo "$m"; echo "$FA_LINE-$m" ;;
    config) d="$(cd "${1:-.}" && pwd)"; write_config "$d" "$d" "$(module_version "$d")" ;;
    package) package "$@" ;;
    *) die "usage: fa-module version|config [dir] | package [--allow-dirty] [dir] [out]" ;;
esac
```

- [ ] **Step 4: Run the tests to check they pass**

Run: `bash deploy/test/fa-module.sh && deploy/test/run.sh`
Expected: `0 failed`, then `all passed`.
- If `git describe --abbrev=7` gives a longer sha in a fixture, compare with
  `git rev-parse --short=7`; they agree unless the abbreviation is ambiguous.
- Run `shellcheck docker/ci/fa-module` if shellcheck is installed.

- [ ] **Step 5: Add the README section and commit**

```bash
git update-index --chmod=+x docker/ci/fa-module   # after git add
git add docker/ci/fa-module deploy/test/fa-module.sh docker/ci/README.md
git commit -m "ci: fa-module works out a module's version and builds its packages"
```

---

### Task 2: `deploy/build-release.sh` writes each component's `_init/config`

**Files:**
- Modify: `deploy/build-release.sh`, the component loop. Today it does
  `git fetch --depth 1` or `git clone --depth 1`, then `rm -rf .git`.
- Test: `deploy/test/build-release.sh`

**Interfaces:**
- Consumes: `sh docker/ci/fa-module config <dir>`, which fails on a shallow
  clone, and `sh docker/ci/fa-module version <dir>` (line 2 is the full
  version), both from Task 1.
- Produces: `<release>/<path>/_init/config` for every component, and a
  manifest line `    version: 2.4-<M>` after each component's line.

- [ ] **Step 1: Write the failing tests.** Append to
  `deploy/test/build-release.sh`, before `finish`:

```bash
git -C "$work/ext" tag v2.0.0
expect_status 0 "builds a tagged component" build HEAD "$b" "modules/ext|$work/ext|main" 7.4.33
expect_contains "writes the component's _init/config" "Version: 2.4-2.0.0" "$(cat "$b/modules/ext/_init/config")"
expect_contains "names the package by its path" "Package: ext" "$(cat "$b/modules/ext/_init/config")"
expect_contains "the manifest has the version" "    version: 2.4-2.0.0" "$(cat "$b.manifest")"
echo three > "$work/ext/a.txt"; git -C "$work/ext" commit -qam third
third="$(git -C "$work/ext" rev-parse --short=7 HEAD)"
expect_status 0 "builds a commit after the tag" build HEAD "$b" "modules/ext|$work/ext|$(git -C "$work/ext" rev-parse HEAD)" 7.4.33
expect_contains "version after a tag, from a commit ref" "Version: 2.4-2.0.0-1-g$third" "$(cat "$b/modules/ext/_init/config")"
expect_status 0 "still no .git" test ! -e "$b/modules/ext/.git"
```

- [ ] **Step 2: Run them to check they fail**

Run: `bash deploy/test/build-release.sh`
Expected: FAIL. There's no `_init/config`, and the clone is shallow.

- [ ] **Step 3: Change the fetch and add the config step.** In the component
  loop of `deploy/build-release.sh`, replace the checkout block, which ends
  with the `echo ... >> "$dir.manifest"` and `rm -rf "$dir/$path/.git"` lines.
  The script's own directory is `deploy/`, so it reaches the script as
  `"$(dirname "$0")/../docker/ci/fa-module"`; set `fa_module` once near the
  top. `deploy` and `docker` are both export-ignored from the FA package,
  which is fine because build-release runs from a checkout.

```sh
    echo "==> $path: $repo @ $cref"
    rm -rf "${dir:?}/$path"
    # Full history and tags, without file contents (a partial clone), so
    # fa-module can describe the commit.
    if is_sha "$cref"; then
        git init --quiet "$dir/$path"
        git -C "$dir/$path" fetch --quiet --filter=blob:none --tags "$repo" "$cref"
        git -C "$dir/$path" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
    else
        git clone --quiet --filter=blob:none --branch "$cref" "$repo" "$dir/$path"
    fi
    sh "$fa_module" config "$dir/$path"
    echo "$path $cref $(git -C "$dir/$path" log -1 --format='%H %s')" >> "$dir.manifest"
    echo "    version: $(sh "$fa_module" version "$dir/$path" | sed -n 2p)" >> "$dir.manifest"
    rm -rf "$dir/$path/.git"
```

- Local fixture repositories served over plain paths ignore `--filter`, with
  a warning. GitHub honours it.
- If git warns on stderr in the tests, add `-c fetch.warnOnFilter=false` or
  silence it with `2>/dev/null` on that line only.
- The fixture config sets `uploadpack.allowReachableSHA1InWant`. For partial
  clone over `file://`, also set `uploadpack.allowFilter true` in
  `mkrepo()` in the test.

- [ ] **Step 4: Run the tests to check they pass**

Run: `deploy/test/run.sh`
Expected: `all passed`. The existing build-release cases still pass:
- the manifest's first line per component is unchanged;
- `version:` is a new line after it.

Check that `deploy/sql-changes.sh` and `deploy/upload.sh` don't parse
manifest lines in a way an extra indented line breaks. `grep -n manifest
deploy/*.sh` shows they compare the `<path> <ref> <sha>` lines. Make them
skip lines starting with four spaces, as they already must for
`    composer:`, and confirm their tests pass.

- [ ] **Step 5: Commit**

```bash
git add deploy/build-release.sh deploy/test/build-release.sh
git commit -m "deploy: each component gets its version and _init/config"
```

---

### Task 3: `admin/inst_module.php` shows the live version of local extensions

**Files:**
- Modify: `admin/inst_module.php`. Add `refresh_local_versions()` and call it
  where the page builds its extensions list, before `display_extensions()`
  and `company_extensions()` run, so both tables and the stored file agree.
- Test: wherever FA's PHP tests live in this repo (`modules/tests/` or the
  CI image's FA test runner, see `docker/ci/README.md`). If
  `inst_module.php` can't be unit-tested because it's a page script, put
  the function in `admin/includes/local_versions.inc`, include it from
  `inst_module.php`, and test that file.

**Interfaces:**
- Consumes: the `_init/config` format from spec §1. Does not depend on
  Task 1's code.
- Produces: `refresh_local_versions(array $exts, string $root): array|false`.
  It returns the updated list when something changed, or false when nothing
  did, and the page calls `update_extensions()` with it.

- [ ] **Step 1: Write the failing test** (PHPUnit, in the repo's existing FA
  test style). Fixture: a temporary FA root with
  `modules/demo/_init/config` containing
  `"Package: demo\nName: demo\nVersion: 2.4-1.5.0\n\n"`, and an extensions
  array:

```php
$exts = [
    0 => ['package' => 'demo', 'name' => 'demo', 'version' => '-', 'type' => 'extension', 'path' => 'modules/demo', 'active' => false],
    1 => ['package' => 'repo_pkg', 'name' => 'repo_pkg', 'version' => '2.4.0-1', 'type' => 'extension', 'path' => 'modules/repo_pkg', 'active' => false],
    2 => ['package' => 'chart_x', 'name' => 'chart', 'version' => '2.3.0-3', 'type' => 'chart', 'path' => 'sql', 'active' => false],
];
$new = refresh_local_versions($exts, $root);
$this->assertSame('2.4-1.5.0', $new[0]['version']);   // refreshed from _init/config
$this->assertSame('2.4.0-1', $new[1]['version']);     // no _init/config: untouched
$this->assertSame($exts[2], $new[2]);                 // not an extension: untouched
$this->assertFalse(refresh_local_versions($new, $root)); // nothing changed now
// garbled config: untouched, no error
file_put_contents("$root/modules/demo/_init/config", "garbage without a colon\n");
$this->assertFalse(refresh_local_versions($exts, $root));
```

Also cover:
- a config with no `Version` key gives false;
- a `path` outside `modules/` (for example `../x`) is never read, which
  `clean_file_name()` and checking `path === 'modules/'.$package` ensure.

- [ ] **Step 2: Run the test to check it fails.** Expected: FAIL, because
  `refresh_local_versions` is undefined.

- [ ] **Step 3: Implement**

```php
/*
	A local extension (installed from modules/<id>, not from FA's package
	repository) carries its version in modules/<id>/_init/config, written by
	its build. FA reads it only at install, so an upgrade by file sync would
	keep showing the old version: refresh it here. Returns the updated list,
	or false when nothing changed.
*/
function refresh_local_versions($exts, $root)
{
	$changed = false;
	foreach ($exts as $i => $ext) {
		if (@$ext['type'] != 'extension' || !isset($ext['package']))
			continue;
		$id = clean_file_name($ext['package']);
		if (@$ext['path'] !== 'modules/'.$id)
			continue;
		$file = $root.'/modules/'.$id.'/_init/config';
		if (!is_file($file))
			continue;
		$ctrl = @get_control_file($file);
		if (!is_array($ctrl) || empty($ctrl['Version']) || $ctrl['Version'] === @$ext['version'])
			continue;
		$exts[$i]['version'] = $ctrl['Version'];
		$changed = true;
	}
	return $changed ? $exts : false;
}
```

- `get_control_file()` calls `display_error()` on a parse error. In the test,
  stub `display_error` if FA's test bootstrap doesn't define it. On the page,
  a garbled file shows FA's own parse message once, which is acceptable.
  Alternatively, read the file with a tiny local parser (`Key: value` lines
  only) and don't call `get_control_file()`. Choose the local parser if the
  stub gets awkward, and say which you chose in the commit message.
- On the page, after the extensions list is loaded and before it's displayed:
  `if (($new = refresh_local_versions(get_company_extensions(), $path_to_root)) !== false) update_extensions($new);`.
  Then the existing code reads the fresh list.
- Repository packages have `_init/config` under the package cache, not
  `modules/<id>`, and FA's own updater handles them. The
  `path === modules/<id>` check plus "no `_init/config` in the module folder"
  keeps those untouched.

- [ ] **Step 4: Run the test to check it passes.** Then a manual check in the
  plugin-dev environment (`docker/ci/plugin-dev.sh --env mcp up`):
  1. write `modules/mcp/_init/config` by hand;
  2. open Setup → Install/Activate Extensions;
  3. see the version, and see it persist in `installed_extensions.php`.

  Record this in the PR.

- [ ] **Step 5: Commit**

```bash
git add admin/inst_module.php admin/includes/local_versions.inc <test file>
git commit -m "inst_module: show a local extension's version from its _init/config"
```

---

### Task 4: `.github/workflows/plugin-release.yml`

**Files:**
- Create: `.github/workflows/plugin-release.yml`
- Modify: `.github/workflows/deploy-test.yml`. Add `docker/ci/fa-module` to
  both `paths:` lists so its tests run when it changes.
- Modify: `docker/ci/README.md`, a "Releasing a module" section showing the
  module's `release.yml` (the same text as Task 5's Step 4).

**Interfaces:**
- Consumes: `fa-module package <dir> <out>`, which prints the tgz path and
  then the zip path (Task 1).
- Produces: a reusable workflow:
  - **inputs:** `module` (string, required, the folder name and FA extension
    id) and `deploy-branch` (string, required);
  - **permissions it needs from the caller:** `contents: write`;
  - **behaviour:** creates the GitHub release `${{ github.ref_name }}` with
    the two archives.

- [ ] **Step 1: Write the workflow**

```yaml
name: Plugin release

# Reusable workflow: package a FrontAccounting module at a pushed v<semver>
# tag with docker/ci/fa-module and publish it as a GitHub release
# (docs/superpowers/specs/2026-10-21-module-releases-design.md). A module's
# release.yml calls it after its tests pass:
#
#   on:
#     push:
#       tags: ['v*']
#   jobs:
#     test: { ... the same plugin-test.yml calls as ci.yml ... }
#     release:
#       needs: [test]
#       permissions:
#         contents: write
#       uses: cambell-prince/frontaccounting/.github/workflows/plugin-release.yml@master-cp
#       with:
#         module: mcp
#         deploy-branch: main

on:
  workflow_call:
    inputs:
      module:
        description: The module's folder name and FrontAccounting extension id
        type: string
        required: true
      deploy-branch:
        description: The branch a release tag must be on
        type: string
        required: true

permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    steps:
      - name: Check the tag
        env:
          TAG: ${{ github.ref_name }}
        run: |
          case "$TAG" in
              v[0-9]*.[0-9]*.[0-9]*) ;;
              *) echo "::error::'$TAG' is not a v<major>.<minor>.<patch> tag"; exit 1 ;;
          esac
          case "${TAG#v}" in *[!0-9.]*) echo "::error::'$TAG' is not a v<major>.<minor>.<patch> tag"; exit 1 ;; esac
      - uses: actions/checkout@v7
        with:
          path: ${{ inputs.module }}
          fetch-depth: 0
          fetch-tags: true
      - uses: actions/checkout@v7
        with:
          repository: cambell-prince/frontaccounting
          ref: master-cp
          path: fa
          sparse-checkout: docker/ci
      - name: Check the tag is on the deploy branch and not yet released
        working-directory: ${{ inputs.module }}
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: ${{ github.ref_name }}
          BRANCH: ${{ inputs.deploy-branch }}
        run: |
          git merge-base --is-ancestor "$TAG" "origin/$BRANCH" \
              || { echo "::error::$TAG is not on $BRANCH"; exit 1; }
          if gh release view "$TAG" >/dev/null 2>&1; then
              echo "::error::a release for $TAG already exists; tag a new patch version instead"; exit 1
          fi
      - name: Package
        id: package
        env:
          MODULE: ${{ inputs.module }}
        run: |
          files="$(sh fa/docker/ci/fa-module package "$MODULE" "$RUNNER_TEMP/dist")"
          printf 'files<<EOF\n%s\nEOF\n' "$files" >> "$GITHUB_OUTPUT"
          echo "version=$(sh fa/docker/ci/fa-module version "$MODULE" | sed -n 1p)" >> "$GITHUB_OUTPUT"
      - name: Release notes
        working-directory: ${{ inputs.module }}
        env:
          VERSION: ${{ steps.package.outputs.version }}
        run: |
          # The CHANGELOG section headed with this version, if any.
          if [ -f CHANGELOG.md ]; then
              awk -v v="$VERSION" '
                  /^## / { if (on) exit; if (index($0, v)) { on = 1; next } }
                  on' CHANGELOG.md > "$RUNNER_TEMP/notes.md"
          fi
      - name: Publish
        working-directory: ${{ inputs.module }}
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: ${{ github.ref_name }}
          MODULE: ${{ inputs.module }}
          VERSION: ${{ steps.package.outputs.version }}
          FILES: ${{ steps.package.outputs.files }}
        run: |
          if [ -s "$RUNNER_TEMP/notes.md" ]; then notes=(--notes-file "$RUNNER_TEMP/notes.md"); else notes=(--generate-notes); fi
          # shellcheck disable=SC2086
          gh release create "$TAG" $FILES --verify-tag --title "$MODULE $VERSION" "${notes[@]}"
      - name: Summary
        env:
          FILES: ${{ steps.package.outputs.files }}
        run: |
          { echo "### Released ${{ github.ref_name }}"; for f in $FILES; do echo "- $(basename "$f")"; done; } >> "$GITHUB_STEP_SUMMARY"
```

- [ ] **Step 2: Lint it.** Run `actionlint .github/workflows/plugin-release.yml`
  if available, or `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:latest`.
  Expected: no errors.
  - The real end-to-end test is Task 5's `v1.0.0` tag.
  - The step-level check that `$GITHUB_OUTPUT` multi-line `files` works is
    exercised there too.
- [ ] **Step 3: Commit**

```bash
git add .github/workflows/plugin-release.yml .github/workflows/deploy-test.yml docker/ci/README.md
git commit -m "ci: plugin-release.yml publishes a module's tagged release"
```

---

### Tasks 5–8: the modules

Each module task is the same work in a different repository, with the
differences listed per task. Do it in a git worktree of that module repo
(`<module>/.claude/worktrees/release-tooling`), branch `ci/release-tooling`.

**Common files per module:**
- Modify: `composer.json`. Add the scripts below and
  `"extra": {"fa-module": {"name": "<display name>"}}`, merging with any
  existing `extra`.
- Create: `.github/workflows/release.yml`.
- Create or modify: `.gitattributes`, adding `export-ignore` lines.
- Modify: `.gitignore`, adding `_init/` and `build/dist/`.
- Modify: `hooks.php`. In `activate_extension()`, when `!$check_only`, call
  `$this->refresh_own_version()`, and add the method below.
- Test: a unit test of `refresh_own_version()` in the module's existing test
  suite.
- Modify: `README.md`, adding a "Releasing" section.

**Common interfaces:**
- Consumes: `../../docker/ci/fa-module` (Task 1) and `plugin-release.yml`
  (Task 4), both on `master-cp`.

**Common steps:**

- [ ] **Step 1: Write the failing hook test.** In the module's test style,
  with FA's test bootstrap, which gives `get_company_extensions()` and
  `update_extensions()`; stub them if that bootstrap doesn't load
  `admin/db/maintenance_db.inc`. Cover:
  - with `modules/<id>/_init/config` holding `Version: 2.4-9.9.9`, the hook
    sets only this module's entry to `2.4-9.9.9`, and other entries are
    byte-identical;
  - with no `_init/config`, nothing is written;
  - with a config lacking `Version`, nothing is written;
  - if the version already matches, `update_extensions` isn't called.

  Restore the real `_init/config` state and `installed_extensions.php` after
  the test.

- [ ] **Step 2: Run it to check it fails.** Expected: undefined method
  `refresh_own_version`.

- [ ] **Step 3: Implement the hook** in the module's `hooks_<id>` class:

```php
	/*
		Stock FrontAccounting reads modules/<id>/_init/config (written by the
		module's build, docker/ci/fa-module) only when the extension is first
		installed. Refresh the stored version on activation so an upgrade shows
		its version on Install/Activate Extensions.
	*/
	function refresh_own_version()
	{
		global $path_to_root;

		$file = $path_to_root.'/modules/'.$this->module_name.'/_init/config';
		if (!is_file($file))
			return;
		$version = null;
		foreach (file($file) as $line)
			if (preg_match('/^Version:\s*(\S+)/', $line, $m))
				$version = $m[1];
		if ($version === null)
			return;
		$exts = get_company_extensions();
		foreach ($exts as $i => $ext)
			if (@$ext['package'] === $this->module_name && @$ext['type'] === 'extension') {
				if (@$ext['version'] !== $version) {
					$exts[$i]['version'] = $version;
					update_extensions($exts);
				}
				return;
			}
	}
```

Match each module's own indentation: tabs in graphql and sgw_sales, spaces
in mcp, and whatever sgw_import's file uses. Call it at the start of
`activate_extension()`'s real run (`if (!$check_only) $this->refresh_own_version();`).
A version refresh must never stop activation.

- [ ] **Step 4: Add the release plumbing.**

`composer.json` scripts:
```json
"fa:version": "sh ../../docker/ci/fa-module version",
"fa:package": "sh ../../docker/ci/fa-module package"
```

`.github/workflows/release.yml`: copy the module's `ci.yml` `jobs:` (the same
`test`/`coverage` jobs, unchanged) and add the release job. Change the header
and trigger:

```yaml
name: Release

# On a pushed v<semver> tag: the same tests as ci.yml, then package and
# publish the GitHub release (cambell-prince/frontaccounting
# .github/workflows/plugin-release.yml).

on:
  push:
    tags: ['v*']

jobs:
  # ... the same jobs as ci.yml ...
  release:
    needs: [test, coverage]   # every job above
    permissions:
      contents: write
    uses: cambell-prince/frontaccounting/.github/workflows/plugin-release.yml@master-cp
    with:
      module: <id>
      deploy-branch: <main|master>
```

The `coverage` job uploads to Codecov. Keep it in `needs` only if it exists
in that module's `ci.yml`.

`.gitattributes`: add these lines (`export-ignore` means they're not packaged):
```
tests export-ignore
tools export-ignore
docs export-ignore
.github export-ignore
.claude export-ignore
phpunit*.xml export-ignore
phpcs.xml export-ignore
phpstan*.neon export-ignore
codecov.yml export-ignore
.gitattributes export-ignore
.gitignore export-ignore
```
Plus module-specific development files, listed per task. Keep
`composer.json` and `composer.lock`, and any runtime directories such as
`sql/` and `includes/`.

README "Releasing" section:
```markdown
## Releasing

Releases are tags. On the deploy branch (`<branch>`), with CI green:

    git tag v1.2.3 && git push origin v1.2.3

`.github/workflows/release.yml` runs the tests, then packages the module with
FrontAccounting's `docker/ci/fa-module` and publishes the GitHub release:
`frontaccounting-2.4-<id>.module.1.2.3.tgz` and `.zip`, each with
`_init/config` (`Version: 2.4-1.2.3`). Untagged builds, such as bms's deploys,
are versioned `2.4-1.2.3-<n>-g<sha>`.

`composer fa:version` prints this checkout's version and
`composer fa:package` builds the packages into `build/dist/`. Both run from
inside a FrontAccounting checkout (`modules/<id>`).
```

- [ ] **Step 5: Verify locally.**
  1. From the module folder inside the FA checkout, with `master-cp`'s
     `docker/ci/fa-module` present (pull the FA root checkout's `master-cp`
     first, or run `sh /path/to/fa/docker/ci/fa-module` directly), run
     `composer fa:version` and `composer fa:package -- --allow-dirty`.
  2. List both archives:
     - no `tests/`, `tools/`, `.github/`, `backup/`, `uploads/<files>`,
       `node_modules/` or `*.sql.gz`;
     - `vendor/` is present when the module has composer runtime deps;
     - `_init/config` is right.
  3. Then run the module's full gate in the CI image (README "## Development").

- [ ] **Step 6: Commit, PR, merge when green.** Use the merge-when-green skill.
  The PR body explains the release flow and links the FA spec.

- [ ] **Step 7: Tag the first release and check it.**
  1. After the merge, `git fetch origin && git tag <first tag> origin/<branch> && git push origin <first tag>`.
  2. Watch the Release workflow: `gh run watch -R <repo>`.
  3. Download the release assets into a temp dir and check:
     - the names follow the convention;
     - both archives list the same files;
     - nothing private is in them;
     - `_init/config` reads `Version: 2.4-<first version>`.
  4. Delete the temp dir.

  If the workflow fails on a release-workflow bug, fix it in the FA repo
  (a PR to master-cp) and re-run the module's Release workflow for the same
  tag (`gh run rerun`). No release was created, so the tag can be reused.

### Task 5: mcp (`saygoweb/frontaccounting-module-mcp`)

- **Path:** `/home/cambell/src/sgw/frontaccounting/modules/mcp`. Deploy
  branch `main`. Id `mcp`. Display name `MCP server`. First tag `v1.0.0`.
- **CHANGELOG:** move "Unreleased - 1.0.0" to `## 1.0.0 - <date>` in the same
  PR, so the release notes come from it. The awk in `plugin-release.yml`
  matches a `## ` heading containing `1.0.0`.
- **Extra `export-ignore`:** `CHANGELOG.md` stays (it's useful to users),
  `config_mcp.php` (it's a local file, so check it isn't tracked) and
  `config_mcp.example.php` stays. Check `git ls-files` for any other
  development-only files.
- **Hook test location:** the mcp unit suite (`tests/Unit/…`). See the
  existing hooks tests, if any, under `tests/`.

### Task 6: graphql (`saygoweb/frontaccounting-module-graphql`)

- **Path:** `/home/cambell/src/sgw/frontaccounting/modules/graphql`. Deploy
  branch `main`. Id `graphql`. Display name `GraphQL API`. First tag
  `v1.0.0`. There's no CHANGELOG, so notes are generated.
- **Before packaging:** `vendor/` in the root checkout is stale (it has
  anorm-graphql v0.3.0 against a v0.3.2 lock). Run `composer install` in the
  worktree.
- **Extra `export-ignore`:** `bin/generate`, `docker/`, `build/`, `tmp/`,
  `ROADMAP-*.md`. Keep `bin/fa-report` and `bin/fa-token` if the README
  documents them for operators; check the README.

### Task 7: sgw_sales (`saygoweb/frontaccounting-module-sgw_sales`)

- **Path:** `/home/cambell/src/sgw/frontaccounting/modules/sgw_sales`. Deploy
  branch `master`. Id `sgw_sales`. Display name `Recurring Sales`. First tag
  `v1.6.0`.
- **Pull `master` first:** the local checkout is behind, and
  `notify-deploy.yml` merged as #12.
- **Remove:** `package.json`, `gulpfile.js`, `package-lock.json` (if
  tracked), `node_modules/` (if tracked), `upload-exclude.txt`,
  `upload-exclude-zip.txt` and `makefile.json` (if it's only the old upload
  config; check what reads it first). Remove the `node_modules` prune from the
  `lint` script if nothing else needs it.
- **README:** replace any gulp instructions with the Releasing section.
- **Extra `export-ignore`:** `phpunit-graphql.xml` (already covered by
  `phpunit*.xml`) and `phpstan-baseline.neon` (covered by `phpstan*.neon`).

### Task 8: sgw_import (`saygoweb/frontaccounting-module-sgw_import`)

- **Path:** `/home/cambell/src/sgw/frontaccounting/modules/sgw_import`.
  Deploy branch `master`. Id `sgw_import`. Display name `Bank Import`. First
  tag `v1.3.0`.
- **Pull `master` first.** PR #20 may be open and touch the same files; base
  on current `master`.
- **Remove:** as in Task 7, plus delete the stray local archives
  `frontaccounting-2.4.RC1-sgw_import.module.1.2.1.{tgz,zip}` from the working
  copy. They're untracked; delete them with `rm`, since they hold the old
  private data.
- **Keep `backup/` and `uploads/` out of git and out of packages:**
  - check they're in `.gitignore`;
  - add `backup/` to `.gitignore` if it isn't;
  - keep `uploads/.gitkeep` tracked, because the module needs the folder.
- **Extra `export-ignore`:** `build/` (check whether it's tracked and what it
  holds), `data/` (check whether it's a runtime schema file the hooks load, and
  keep it if so).
