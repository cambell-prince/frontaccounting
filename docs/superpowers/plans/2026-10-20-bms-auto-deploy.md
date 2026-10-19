# Automatic Deploys of bms.saygoweb.com Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use cjp:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task, wave by wave per the Execution Schedule. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GitHub Actions deploys bms.saygoweb.com (FrontAccounting `master-ark` plus graphql, mcp, sgw_sales and sgw_import) whenever any of those five repositories goes green, shipping each part at its newest commit that passed CI.

**Architecture:**
- `deploy-bms.yml` lives on `master-cp`, the default branch. It is triggered by `CI image` completing on `master-ark`, by an `extension-green` repository_dispatch from each extension's new `notify-deploy.yml`, or by hand.
- It resolves every part to a green SHA (`deploy/resolve-refs.sh`) and builds the release with the existing `deploy/build-release.sh`, now able to take SHAs.
- It warns about `sql/` changes (`deploy/sql-changes.sh`), then runs the existing `deploy/upload.sh`, which now takes user/host/path and enforces a delete limit. The rsync goes over SSH with a key forced through rrsync.
- Automatic runs stay dry until the `DEPLOY_LIVE` variable is `true`.

**Tech Stack:** POSIX sh and bash, rsync/rrsync, git, `gh`, `jq`, `awk`, GitHub Actions, Docker (CI image only).

**Spec:** `docs/superpowers/specs/2026-10-20-bms-auto-deploy-design.md`. The server side is the "bms Server Rollout" runbook, https://claude.ai/artifact/YYT4uooYtu5mCSoxByxRWz.

## Global Constraints

- **Worktree.** Work in `/home/cambell/src/sgw/frontaccounting/.claude/worktrees/bms-deploy` on branch `feature/bms-auto-deploy`, created from `docs/bms-auto-deploy`. Task 7 works in its own extension worktrees, and Task 8 in `/home/cambell/src/sgw/frontaccounting/.claude/worktrees/merge-ark`.
- **Hands off production branches and the server.** Never push to `master-cp` or `master-ark`, and never merge an extension PR. Nothing in this plan contacts aws1: no ssh, no rsync to it.
- **Shell flavours.**
  - `deploy/build-release.sh` and `deploy/upload.sh` run as `sh` (POSIX). Keep them POSIX.
  - New scripts (`deploy/resolve-refs.sh`, `deploy/sql-changes.sh`, every `deploy/test/*.sh`) are bash: `#!/usr/bin/env bash`, `set -euo pipefail`, with the header-comment style of `docker/ci/*.sh`.
- **Tests.** Tests source `docker/ci/test/lib.sh` (`expect_status`, `expect_contains`, `expect_absent`, `pass`, `fail`, `finish`). They need no network and no docker. Temporary directories come from `mktemp -d`, removed by a trap.
- **File modes.** `core.fileMode` is off, so record executable modes with `git update-index --chmod=+x <file>` after `git add`.
- **Commits.** Commit as `git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit ...`. Messages end with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Shared worktree.** Tasks in one wave share the worktree. Stage only your own files (`git add <paths>`, never `-A`). If `.git/index.lock` exists, wait a few seconds and retry.
- **Fixed names.** These are used verbatim everywhere:
  - dispatch event `extension-green`, with payload keys `component`, `sha`, `run_url`
  - environment `bms`, with secrets `BMS_SSH_KEY` and `BMS_KNOWN_HOSTS` and variables `DEPLOY_USER`, `DEPLOY_HOST`, `DEPLOY_PATH`, `DEPLOY_LIVE`
  - org secret `FA_DEPLOY_DISPATCH`
  - the manifest name for FrontAccounting: `frontaccounting`
- **Delete limit.** Automatic runs use `max_deletes` 25.
- **Linters, run through docker:**
  - actionlint: `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.7 <files>`
  - shellcheck: `docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:v0.10.0 <files>`
- **Thermal limits.** Only Task 5 builds a docker image. Check `cat /sys/devices/system/cpu/intel_pstate/no_turbo` is `1` first, and run one docker build at a time.

## Review Focus

1. **A key forced through rrsync.** With `DEPLOY_PATH=/`, `upload.sh` must deploy into the rrsync root, and rrsync must accept every rsync option `upload.sh` sends (`--chmod`, `--delete`, the filters). `previous` must find `/.deploy-manifest`. Pinned by the rrsync block in Task 2's test.
2. **A server manifest from an older build.** A manifest with short SHAs, or one a component is missing from, gets a "cannot compare" or "new in this deploy" line and never a crash. Pinned in Task 4's test.
3. **Green runs that don't count.** An extension whose only green runs are PR or manual runs must count as having no green run. The query must carry `event=push&status=success`, and Task 3's gh stub refuses any query without them.
4. **A typo in a manual `refs` override** (an unknown path, or a non-SHA) is refused, not silently ignored. Pinned in Task 3's test.
5. **A module installed on the server but missing from the release** (for example, dropped from `components`) survives the deploy through the protect filter. Pinned in Task 2's test (`modules/other`).

## Execution Schedule

| Wave | Tasks | Model | Notes |
|------|-------|-------|-------|
| 1 | Task 1, Task 2, Task 3, Task 4, Task 5, Task 7 | sonnet ×6 | Parallel. Disjoint files: Task 7 is in other repositories, and only Task 5 runs docker, one build. Task 1 creates `deploy/test/run.sh`, which picks up the other tasks' tests by glob. |
| CP1 | — | — | Plan base..end of wave 1: code-review medium + spec check (spec §3, §4, §5). Must finish before wave 2, which builds on these scripts' interfaces. |
| 2 | Task 6 | sonnet | The workflows and README, consuming every wave-1 interface. |
| CP2 | — | — | Plan base..end of wave 2: code-review medium + spec check (full spec). Check the `LIVE` expression by hand: dispatch and workflow_run runs are dry unless `DEPLOY_LIVE` is `true`, and manual runs are live only with `dry_run` off. |
| 3 | Controller | — | `deploy/test/run.sh`, `docker/ci/test/prune.sh`, actionlint on all workflows. Push `feature/bms-auto-deploy`, open a PR into `master-cp` (`gh pr create -R cambell-prince/frontaccounting --base master-cp`), and watch CI. Report the four extension PRs as open, not merged. **The user decides when to merge.** |
| 4 | Task 8 | sonnet | Only after the user has merged the PR into `master-cp`. Brings it into `merge/master-cp-into-master-ark` with bms's site settings. |
| 5 | Controller | — | Push `merge/master-cp-into-master-ark` (never `master-ark`). Update the runbook artifact: phase 4 sets `DEPLOY_LIVE=false`, and a new step sets it `true` after the 2.4.20 upgrade. Hand the rollout to the user. |

---

### Task 1: `build-release.sh` takes commit SHAs and writes `.deploy-manifest`

**Files:**
- Modify: `deploy/build-release.sh`
- Create: `deploy/test/build-release.sh`, `deploy/test/run.sh`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - A component `ref` of exactly 40 lowercase hex digits is fetched as that commit. Any other ref is cloned as a branch or tag, as before.
  - Manifest lines become `frontaccounting <ref> <40-hex sha> <subject>` and `<path> <ref> <40-hex sha> <subject>`, followed by `    composer: …` lines as before.
  - The release carries a copy of the manifest as `<dir>/.deploy-manifest`.
  - `deploy/test/run.sh` runs every `deploy/test/*.sh` except itself.

- [ ] **Step 1: Write the failing test**

`deploy/test/build-release.sh`:

```bash
#!/usr/bin/env bash
#
# build-release.sh against local fixture repositories: branch and commit
# refs, full commits in the manifest, and the manifest's copy in the release.
# No network, no docker (the fixture component has no composer.json).
#
#   deploy/test/build-release.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=../../docker/ci/test/lib.sh
. "$here/../../docker/ci/test/lib.sh"
root="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkrepo() {
    git init -q -b main "$1"
    git -C "$1" config user.email test@example.com
    git -C "$1" config user.name test
    # GitHub serves any reachable commit; a local repository needs telling.
    git -C "$1" config uploadpack.allowReachableSHA1InWant true
}

mkrepo "$work/ext"
echo one > "$work/ext/a.txt"
git -C "$work/ext" add a.txt
git -C "$work/ext" commit -qm first
first="$(git -C "$work/ext" rev-parse HEAD)"
echo two > "$work/ext/a.txt"
git -C "$work/ext" commit -qam second
second="$(git -C "$work/ext" rev-parse HEAD)"

mkrepo "$work/fa"
echo '<?php' > "$work/fa/index.php"
git -C "$work/fa" add index.php
git -C "$work/fa" commit -qm "fa commit"
fa_sha="$(git -C "$work/fa" rev-parse HEAD)"

b="$work/out/release"
build() { (cd "$work/fa" && sh "$root/deploy/build-release.sh" "$@"); }

expect_status 0 "builds with a branch ref" build HEAD "$b" "modules/ext|$work/ext|main" 7.4.33
expect_contains "checks out the branch head" "two" "$(cat "$b/modules/ext/a.txt")"
expect_contains "records FrontAccounting's full commit" "frontaccounting HEAD $fa_sha fa commit" "$(cat "$b.manifest")"
expect_contains "records the component's full commit" "modules/ext main $second second" "$(cat "$b.manifest")"
expect_status 0 "writes .ok" test -f "$b.ok"
expect_status 0 "leaves no .git in the component" test ! -e "$b/modules/ext/.git"
expect_status 0 "the release carries .deploy-manifest" cmp "$b.manifest" "$b/.deploy-manifest"

expect_status 0 "builds with a commit ref" build "$fa_sha" "$b" "modules/ext|$work/ext|$first" 7.4.33
expect_contains "checks out exactly that commit" "one" "$(cat "$b/modules/ext/a.txt")"
expect_contains "records it" "modules/ext $first $first first" "$(cat "$b.manifest")"
expect_status 0 "leaves no .git after a commit ref either" test ! -e "$b/modules/ext/.git"

# sha40 <char>: a made-up 40-character commit id
sha40() { local s; s="$(printf '%040d' 0)"; printf '%s\n' "${s//0/$1}"; }
missing="$(sha40 f)"
expect_status 128 "an unknown commit fails (git's status)" build HEAD "$b" "modules/ext|$work/ext|$missing" 7.4.33
expect_status 0 "and leaves no .ok" test ! -f "$b.ok"

finish
```

`deploy/test/run.sh`:

```bash
#!/usr/bin/env bash
#
# The deploy/ test suite: every other script in deploy/test. No network, no
# docker.
#
#   deploy/test/run.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failed=()
for t in "$here"/*.sh; do
    name="$(basename "$t")"
    [ "$name" = run.sh ] && continue
    printf '\n## %s\n' "$name"
    bash "$t" || failed+=("$name")
done

if [ "${#failed[@]}" -gt 0 ]; then
    printf '\nFAILED: %s\n' "${failed[*]}"
    exit 1
fi
printf '\nall passed\n'
```

- [ ] **Step 2: Run the test to see it fail**

Run: `bash deploy/test/build-release.sh`
Expected: FAIL on "records FrontAccounting's full commit" (the manifest has `%h`), on "the release carries .deploy-manifest", and on "builds with a commit ref" (`git clone --branch <sha>` fails).

- [ ] **Step 3: Implement**

In `deploy/build-release.sh`:

1. In the header comment, after `#   <components>  space-separated path|repo|ref[|composer], each cloned into` … `<dir>/path at ref.`, add:

```sh
#               A ref of 40 hex digits is a commit (deploy/resolve-refs.sh
#               pins them) and is fetched as exactly that commit.
```

and change the `# On success writes <dir>.ok …` paragraph's first sentence to:

```sh
# On success writes <dir>.ok, which deploy/upload.sh requires, and
# <dir>.manifest, recording what went into the release by full commit. A copy
# of the manifest goes into the release as .deploy-manifest, so the server
# keeps a record of what it runs.
```

2. After `[ -n "$dir" ] && [ "$dir" != "/" ] || …`, add:

```sh
is_sha() { [ "${#1}" -eq 40 ] && case "$1" in *[!0-9a-f]*) false ;; *) true ;; esac; }
```

3. Change the FrontAccounting manifest line to the full commit:

```sh
    echo "frontaccounting $ref $(git log -1 --format='%H %s' "$sha")"
```

4. Replace the clone and its manifest line:

```sh
    git clone --quiet --depth 1 --branch "$cref" "$repo" "$dir/$path"
    echo "$path $cref $(git -C "$dir/$path" log -1 --format='%h %s')" >> "$dir.manifest"
```

with:

```sh
    if is_sha "$cref"; then
        git init --quiet "$dir/$path"
        git -C "$dir/$path" fetch --quiet --depth 1 "$repo" "$cref"
        git -C "$dir/$path" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
    else
        git clone --quiet --depth 1 --branch "$cref" "$repo" "$dir/$path"
    fi
    echo "$path $cref $(git -C "$dir/$path" log -1 --format='%H %s')" >> "$dir.manifest"
```

5. Just before `touch "$dir.ok"`, add:

```sh
cp "$dir.manifest" "$dir/.deploy-manifest"
```

- [ ] **Step 4: Run the test to see it pass**

Run: `bash deploy/test/build-release.sh && bash deploy/test/run.sh`
Expected: `0 failed`, then `all passed`. `run.sh` may also pick up other wave-1 tests that are still failing, so only its build-release section counts here.

- [ ] **Step 5: Lint and commit**

```bash
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:v0.10.0 deploy/build-release.sh deploy/test/build-release.sh deploy/test/run.sh
git add deploy/build-release.sh deploy/test/build-release.sh deploy/test/run.sh
git update-index --chmod=+x deploy/test/build-release.sh deploy/test/run.sh
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "deploy: Pin components to commits, and ship the manifest

build-release.sh fetches a component ref of 40 hex digits as exactly that
commit, records full commits in the manifest, and puts a copy of it in the
release as .deploy-manifest so the server keeps a record of what it runs.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `upload.sh` takes user, host and path, and limits deletes

**Files:**
- Modify: `deploy/upload.sh` (rewrite), `makefile.json`, `upload-exclude.txt`, `deploy/README.md`
- Create: `deploy/test/upload.sh`

**Interfaces:**
- Consumes: the release layout from Task 1: `<dir>/`, `<dir>.ok`, `<dir>.manifest`, `<dir>/.deploy-manifest`.
- Produces:
  - `sh deploy/upload.sh check <dir> <user> <host> <path> <remote_user> [<max_deletes>]`
    - Writes `<dir>.check` (the itemized list) and `<dir>.deletes` (one path per line).
    - Exits 3 when more than `<max_deletes>` files would be deleted. An empty `<max_deletes>` means no limit.
  - `sh deploy/upload.sh go <dir> <user> <host> <path> <remote_user> <confirm>`
  - `sh deploy/upload.sh previous <dir> <user> <host> <path> <remote_user>`
    - Writes the server's `.deploy-manifest` to `<dir>.previous`, or an empty file when there is none.
  - The destination is `<user>@<host>:<path>`, and `<path>` must end with `/`.
  - `UPLOAD_RSH` replaces `ssh`.
  - make.phar variables `user`, `host`, `path`, `max_deletes` (`dest` is gone), and target `deploy-previous`.

- [ ] **Step 1: Write the failing test**

`deploy/test/upload.sh`:

```bash
#!/usr/bin/env bash
#
# upload.sh against a local "server" directory: user, host and path, the
# delete list and its limit, what --delete spares, previous, and the same
# through rrsync as the bms deploy key runs it. No network: UPLOAD_RSH runs
# the remote side here.
#
#   deploy/test/upload.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=../../docker/ci/test/lib.sh
. "$here/../../docker/ci/test/lib.sh"
root="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Stands in for ssh: drops "-l <user>" and the host, runs the command here.
cat > "$work/ssh" <<'EOF'
#!/bin/sh
[ "$1" = -l ] && shift 2
shift
exec sh -c "$*"
EOF
# Stands in for ssh with a key forced through rrsync, as sshd runs it.
cat > "$work/ssh-rrsync" <<'EOF'
#!/bin/sh
[ "$1" = -l ] && shift 2
shift
SSH_ORIGINAL_COMMAND="$*" exec rrsync "$RRSYNC_ROOT"
EOF
chmod +x "$work/ssh" "$work/ssh-rrsync"

# make_release <dir>: a release as build-release.sh leaves it
make_release() {
    rm -rf "$1" "$1.ok"
    mkdir -p "$1/modules/ext"
    echo new > "$1/index.php"
    echo ext > "$1/modules/ext/a.php"
    printf 'built test\nfrontaccounting HEAD %s test\n' "$(printf '%040d' 1)" > "$1.manifest"
    cp "$1.manifest" "$1/.deploy-manifest"
    touch "$1.ok"
}
# make_server <dir>: what is live before a deploy
make_server() {
    rm -rf "$1"
    mkdir -p "$1/modules/ext" "$1/modules/mcp" "$1/modules/other" "$1/company/0"
    echo old > "$1/index.php"
    echo stale > "$1/stale.php"
    echo server > "$1/config.php"
    echo server > "$1/config_db.php"
    echo old > "$1/modules/ext/old.php"
    echo server > "$1/modules/mcp/config_mcp.php"
    echo installed > "$1/modules/other/x.php"
    echo data > "$1/company/0/file"
}

rel="$work/release"
srv="$work/srv"
up() { (cd "$root" && UPLOAD_RSH="$work/ssh" sh deploy/upload.sh "$@"); }
make_release "$rel"
make_server "$srv"

expect_status 1 "refuses an empty user" up check "$rel" "" h "$srv/" ""
expect_contains "and says what to set" "set user, host and path" "$OUT"
expect_status 1 "refuses an empty host" up check "$rel" u "" "$srv/" ""
expect_status 1 "refuses an empty path" up check "$rel" u h "" ""
expect_status 1 "refuses a path without a trailing /" up check "$rel" u h "$srv" ""
expect_status 1 "refuses a max_deletes that is not a number" up check "$rel" u h "$srv/" "" x

expect_status 0 "previous with none recorded" up previous "$rel" u h "$srv/" ""
expect_contains "says so" "no previous deploy" "$OUT"
expect_status 0 "and leaves an empty file" test -f "$rel.previous" -a ! -s "$rel.previous"

expect_status 0 "check" up check "$rel" u h "$srv/" ""
expect_contains "counts the deletes" "2 to delete" "$OUT"
deletes="$(cat "$rel.deletes")"
expect_contains "would delete stale.php" "stale.php" "$deletes"
expect_contains "would delete a stale file in a carried module" "modules/ext/old.php" "$deletes"
for keep in config.php config_db.php company modules/mcp/config_mcp.php modules/other; do
    expect_absent "spares $keep" "$keep" "$deletes"
done
expect_status 0 "check changes nothing" test -f "$srv/stale.php"

expect_status 3 "fails above max_deletes" up check "$rel" u h "$srv/" "" 1
expect_contains "and says why" "more than the limit of 1" "$OUT"
expect_status 0 "passes at max_deletes" up check "$rel" u h "$srv/" "" 2

expect_status 1 "go needs confirm=yes" up go "$rel" u h "$srv/" "" no
expect_status 0 "go" up go "$rel" u h "$srv/" "" yes
expect_status 0 "stale.php is gone" test ! -e "$srv/stale.php"
expect_status 0 "the stale module file is gone" test ! -e "$srv/modules/ext/old.php"
expect_contains "index.php is the release's" "new" "$(cat "$srv/index.php")"
for keep in config.php config_db.php modules/mcp/config_mcp.php modules/other/x.php company/0/file; do
    expect_status 0 "$keep survives" test -f "$srv/$keep"
done
expect_contains "config.php is still the server's" "server" "$(cat "$srv/config.php")"
expect_status 0 "the server records the deploy" cmp "$rel.manifest" "$srv/.deploy-manifest"

expect_status 0 "previous after a deploy" up previous "$rel" u h "$srv/" ""
expect_status 0 "fetches the server's manifest" cmp "$rel.manifest" "$rel.previous"

rm -f "$rel.ok"
expect_status 1 "refuses a release without .ok" up check "$rel" u h "$srv/" ""

# The bms deploy key runs through rrsync rooted at the site, so path is /.
if command -v rrsync >/dev/null; then
    make_release "$rel"
    make_server "$srv"
    rr() { (cd "$root" && UPLOAD_RSH="$work/ssh-rrsync" RRSYNC_ROOT="$srv" sh deploy/upload.sh "$@"); }
    expect_status 0 "rrsync: previous with none recorded" rr previous "$rel" u h / ""
    expect_status 0 "rrsync: check" rr check "$rel" u h / ""
    expect_contains "rrsync: / is the site" "stale.php" "$(cat "$rel.deletes")"
    expect_status 0 "rrsync: go accepts upload.sh's options" rr go "$rel" u h / "" yes
    expect_status 0 "rrsync: deployed into its root" test ! -e "$srv/stale.php" -a -f "$srv/.deploy-manifest"
    expect_status 0 "rrsync: wrote nothing above it" test ! -e "$work/index.php"
    expect_status 0 "rrsync: previous" rr previous "$rel" u h / ""
    expect_status 0 "rrsync: fetched the manifest" cmp "$rel.manifest" "$rel.previous"
    set +e
    rr check "$rel" u h ../ "" >/dev/null 2>&1
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then pass "rrsync: refuses a path above its root"; else fail "rrsync: refuses a path above its root (exit 0)"; fi
else
    printf '  skip  rrsync (none on PATH)\n'
fi

finish
```

- [ ] **Step 2: Run the test to see it fail**

Run: `bash deploy/test/upload.sh`
Expected: FAIL from the first check onward, because the old `upload.sh` takes `<dest>` and has no `previous`.

- [ ] **Step 3: Implement `upload.sh`**

Replace `deploy/upload.sh` entirely:

```sh
#!/bin/sh
# rsync a built release to the server, for make.phar's deploy targets and the
# bms deploy workflow (.github/workflows/deploy-bms.yml).
#
#   deploy/upload.sh check    <dir> <user> <host> <path> <remote_user> [<max_deletes>]
#   deploy/upload.sh go       <dir> <user> <host> <path> <remote_user> <confirm>
#   deploy/upload.sh previous <dir> <user> <host> <path> <remote_user>
#
# The destination is <user>@<host>:<path>, and <path> ends with /. For a key
# forced through rrsync, <path> is relative to the directory rrsync is rooted
# at, so the bms workflow passes /.
#
# check     dry run: lists what would change and every file the server would
#           lose, also written to <dir>.deletes one per line. Fails (exit 3)
#           if more than <max_deletes> would go; no limit when it is empty.
# go        the upload itself; needs <confirm> = yes
# previous  fetches the server's .deploy-manifest, the record of the last
#           deploy, to <dir>.previous; an empty file when there is none
#
# --delete makes the server match the release, except for:
#   - anything upload-exclude.txt names, which is neither sent nor deleted
#     (configuration, company data, tmp/, extension settings and uploads)
#   - protected top-level entries of modules/, themes/ and lang/: an extension,
#     theme or language installed on the server but not in this release is left
#     alone. Stale files inside ones the release does carry are still removed.
#
# UPLOAD_RSH replaces ssh as the remote shell (deploy/test/upload.sh).
set -eu

mode="${1:-}"
dir="${2:-}"
user="${3:-}"
host="${4:-}"
path="${5:-}"
remote_user="${6:-}"
extra="${7:-}"

[ -n "$user" ] && [ -n "$host" ] && [ -n "$path" ] || { echo "upload: set user, host and path (in makefile.json, or user=... host=... path=...)" >&2; exit 1; }
case "$path" in */) ;; *) echo "upload: path must end with / ($path)" >&2; exit 1 ;; esac
dest="$user@$host:$path"

rsync_path="rsync"
[ -z "$remote_user" ] || rsync_path="sudo -u $remote_user rsync"
rsh="${UPLOAD_RSH:-ssh}"

if [ "$mode" = previous ]; then
    out="$dir.previous"
    rm -f "$out" "$out.err"
    if rsync -t --rsync-path="$rsync_path" --rsh="$rsh" "${dest}.deploy-manifest" "$out" 2> "$out.err"; then
        echo "==> previous deploy: $(head -2 "$out" | tail -1)"
    elif grep -q 'No such file' "$out.err"; then
        : > "$out"
        echo "==> no previous deploy recorded on $dest"
    else
        cat "$out.err" >&2
        rm -f "$out.err"
        exit 1
    fi
    rm -f "$out.err"
    exit 0
fi

[ -f "$dir.ok" ] && [ -d "$dir" ] || { echo "upload: no complete release in $dir; run 'make.phar release' (and check it succeeded)" >&2; exit 1; }

set -- -rzlt --chmod=Dug=rwx,Fug=rw,o-rwx --delete \
    --exclude-from=upload-exclude.txt \
    --filter='P /modules/*' --filter='P /themes/*' --filter='P /lang/*' \
    --rsync-path="$rsync_path" --rsh="$rsh"

echo "==> release: $(head -2 "$dir.manifest" | tail -1)"
case "$mode" in
    check)
        case "$extra" in *[!0-9]*) echo "upload: max_deletes must be a number ($extra)" >&2; exit 1 ;; esac
        out="$dir.check"
        rsync "$@" --dry-run --itemize-changes "$dir/" "$dest" > "$out"
        sed -n 's/^\*deleting *//p' "$out" > "$dir.deletes"
        deletes="$(wc -l < "$dir.deletes" | tr -d ' ')"
        echo "==> dry run against $dest: $(grep -c '^[<>]f' "$out" || true) file(s) to send, $deletes to delete"
        if [ "$deletes" -gt 0 ]; then
            echo "==> the server would lose these:"
            sed 's/^/    /' "$dir.deletes"
        else
            echo "==> nothing on the server would be deleted"
        fi
        echo "==> full list: $out"
        if [ -n "$extra" ] && [ "$deletes" -gt "$extra" ]; then
            echo "upload: $deletes file(s) would be deleted, more than the limit of $extra; check the list, then rerun with a higher max_deletes if they should go" >&2
            exit 3
        fi
        ;;
    go)
        [ "$extra" = yes ] || { echo "upload: this changes $dest; run 'make.phar deploy-check' first, then 'make.phar deploy confirm=yes'" >&2; exit 1; }
        rsync "$@" --stats "$dir/" "$dest"
        ;;
    *)
        echo "upload: mode must be check, go or previous" >&2; exit 1 ;;
esac
```

- [ ] **Step 4: Protect mcp's settings**

In `upload-exclude.txt`, after `/modules/graphql/config_graphql.php`, add:

```
/modules/mcp/config_mcp.php
```

- [ ] **Step 5: Update `makefile.json`**

In `variables`, remove `"dest": "",` and add these, keeping the other variables as they are:

```json
        "user": "",
        "host": "",
        "path": "",
        "max_deletes": "",
```

Replace the `deploy-check` and `deploy` targets and add `deploy-previous` after them:

```json
    "deploy-check": {
        "by": [
            "sh deploy/upload.sh check '{{release}}' '{{user}}' '{{host}}' '{{path}}' '{{remote_user}}' '{{max_deletes}}'"
        ]
    },
    "deploy": {
        "by": [
            "sh deploy/upload.sh go '{{release}}' '{{user}}' '{{host}}' '{{path}}' '{{remote_user}}' '{{confirm}}'"
        ]
    },
    "deploy-previous": {
        "by": [
            "sh deploy/upload.sh previous '{{release}}' '{{user}}' '{{host}}' '{{path}}' '{{remote_user}}'"
        ]
    },
```

Check it parses: `jq . makefile.json >/dev/null`.

- [ ] **Step 6: Update `deploy/README.md`**

Replace:

```
Every variable in `makefile.json` can be overridden on the command line, for
example `make.phar release ref=v2.4.20` or `make.phar deploy-check dest=...`. A
site's own branch sets its values in `makefile.json`: `dest`, `remote_user`,
`components`, `db_ssh` and `db`.
```

with:

```
Every variable in `makefile.json` can be overridden on the command line, for
example `make.phar release ref=v2.4.20` or `make.phar deploy-check user=me`. A
site's own branch sets its values in `makefile.json`: `user`, `host` and `path`
(the destination is `user@host:path`, and `path` ends with `/`),
`remote_user`, `components`, `db_ssh` and `db`.
```

Add rows to the "Other targets" table:

```
| `deploy-previous` | fetch the server's `.deploy-manifest`, the record of the last deploy, to `build/release.previous` |
```

Replace the bullet `- `deploy` needs `confirm=yes`.` with:

```
- `deploy` needs `confirm=yes`.
- `deploy-check max_deletes=<n>` fails if more than `n` files would be
  deleted. The GitHub deploy uses 25.
```

After the `deploy-check` paragraph ("`deploy-check` prints every file …"), add:

```
Every release carries its manifest as `.deploy-manifest`, so the server's copy
names the commits it is running.
```

- [ ] **Step 7: Run the test to see it pass**

Run: `bash deploy/test/upload.sh`
Expected: `0 failed`, with the rrsync block running (this machine has `/usr/bin/rrsync`). If rrsync rejects one of `upload.sh`'s options, the rrsync `go` line fails. Fix the option in `upload.sh`, not the test.

- [ ] **Step 8: Lint and commit**

```bash
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:v0.10.0 deploy/upload.sh deploy/test/upload.sh
git add deploy/upload.sh deploy/test/upload.sh makefile.json upload-exclude.txt deploy/README.md
git update-index --chmod=+x deploy/test/upload.sh
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "deploy: user, host and path; a delete limit; the previous manifest

upload.sh builds the destination from user, host and path, so a key forced
through rrsync can use path /. check writes the delete list and fails above
max_deletes; previous fetches the server's .deploy-manifest. mcp's
config_mcp.php is now protected like graphql's.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `deploy/resolve-refs.sh`

**Files:**
- Create: `deploy/resolve-refs.sh`, `deploy/test/resolve-refs.sh`

**Interfaces:**
- Consumes:
  - `.github/workflows/ci-image.yml`'s list under `paths: &image-paths`. Task 5 keeps that anchor and its `- <glob>` items.
  - The `components` format `path|repo|ref[|composer]`.
- Produces:
  - `deploy/resolve-refs.sh <fa_branch> "<components>" ["<overrides>"]`, run in a FrontAccounting checkout with full history.
  - It prints exactly two lines on stdout, notes on stderr:
    ```
    ref=<40-hex>
    components=<path|repo|sha[|composer]> ...
    ```
  - Overrides are `<path>=<sha>`, and `frontaccounting=<sha>`.
  - `RESOLVE_FA_REPO` (default `cambell-prince/frontaccounting`).

- [ ] **Step 1: Write the failing test**

`deploy/test/resolve-refs.sh`:

```bash
#!/usr/bin/env bash
#
# resolve-refs.sh with a stand-in gh: the newest green commit of each part,
# the docs-only rule for FrontAccounting, overrides, and every refusal.
#
#   deploy/test/resolve-refs.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=../../docker/ci/test/lib.sh
. "$here/../../docker/ci/test/lib.sh"
root="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# gh stand-in: answers the runs query from $GH_STUB_RUNS, lines of
# "<owner/repo> <workflow file> <branch> <sha|none|error>". A query without
# event=push&status=success is a bug in the script, so it is refused.
mkdir "$work/bin"
cat > "$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = api ] || exit 2
re='^repos/([^/]+/[^/]+)/actions/workflows/([^/]+)/runs\?branch=([^&]+)&event=push&status=success'
[[ "$2" =~ $re ]] || { echo "gh stub: unexpected query $2" >&2; exit 2; }
want="${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
while read -r s w b sha; do
    [ "$s $w $b" = "$want" ] || continue
    case "$sha" in
        none) exit 0 ;;
        error) echo "HTTP 502" >&2; exit 1 ;;
        *) echo "$sha"; exit 0 ;;
    esac
done < "$GH_STUB_RUNS"
exit 0
EOF
chmod +x "$work/bin/gh"

fa="$work/fa"
git init -q -b master-ark "$fa"
git -C "$fa" config user.email test@example.com
git -C "$fa" config user.name test
mkdir -p "$fa/.github/workflows" "$fa/docs" "$fa/reporting"
cp "$root/.github/workflows/ci-image.yml" "$fa/.github/workflows/"
git -C "$fa" add .github
git -C "$fa" commit -qm green
c1="$(git -C "$fa" rev-parse HEAD)"
echo notes > "$fa/docs/notes.md"
git -C "$fa" add docs
git -C "$fa" commit -qm docs
c2="$(git -C "$fa" rev-parse HEAD)"
echo '<?php' > "$fa/reporting/rep.php"
git -C "$fa" add reporting
git -C "$fa" commit -qm report
c3="$(git -C "$fa" rev-parse HEAD)"

# sha40 <char>: a made-up 40-character commit id
sha40() { local s; s="$(printf '%040d' 0)"; printf '%s\n' "${s//0/$1}"; }
a1="$(sha40 a)"
b1="$(sha40 b)"
e1="$(sha40 e)"
runs="$work/runs"
cat > "$runs" <<EOF
cambell-prince/frontaccounting ci-image.yml master-ark $c1
o/a ci.yml main $a1
o/b ci.yml master $b1
o/none ci.yml main none
o/err ci.yml main error
EOF

resolve() { (cd "$fa" && PATH="$work/bin:$PATH" GH_STUB_RUNS="$runs" "$root/deploy/resolve-refs.sh" "$@"); }
comps="modules/a|https://github.com/o/a.git|main modules/b|git@github.com:o/b.git|master|legacy"

git -C "$fa" checkout -q "$c2"
expect_status 0 "a docs-only head" resolve master-ark "$comps"
expect_contains "takes the head" "ref=$c2" "$OUT"
expect_contains "pins each component, keeping its composer mode" \
    "components=modules/a|https://github.com/o/a.git|$a1 modules/b|git@github.com:o/b.git|$b1|legacy" "$OUT"

git -C "$fa" checkout -q "$c3"
expect_status 0 "a head that changes the image" resolve master-ark "$comps"
expect_contains "takes the last green commit" "ref=$c1" "$OUT"
expect_contains "and says why" "has not passed CI image" "$OUT"

git -C "$fa" checkout -q "$c1"
expect_status 0 "a green head" resolve master-ark "$comps"
expect_contains "takes it" "ref=$c1" "$OUT"

git -C "$fa" checkout -q "$c3"
expect_status 0 "overrides" resolve master-ark "$comps" "frontaccounting=$c3 modules/a=$e1"
expect_contains "pin FrontAccounting" "ref=$c3" "$OUT"
expect_contains "and a component" "modules/a|https://github.com/o/a.git|$e1 " "$OUT"
expect_status 1 "refuses an override for no component" resolve master-ark "$comps" "modules/zz=$e1"
expect_contains "naming it" "modules/zz" "$OUT"
expect_status 1 "refuses an override that is not a commit" resolve master-ark "$comps" "modules/a=main"

expect_status 1 "a component with no green run" resolve master-ark "modules/n|https://github.com/o/none.git|main"
expect_contains "fails naming it" "modules/n: no successful ci.yml push run" "$OUT"
expect_status 1 "a failing API read" resolve master-ark "modules/e|https://github.com/o/err.git|main"
expect_contains "fails naming the component" "modules/e: could not read CI runs" "$OUT"
expect_status 1 "a malformed component" resolve master-ark "modules/a|x"
expect_contains "is refused" "is not path|repo|ref" "$OUT"
expect_status 1 "a repository not on GitHub" resolve master-ark "modules/g|https://gitlab.com/o/a.git|main"
expect_contains "is refused" "is not a GitHub repository" "$OUT"

sed -i "s/^cambell-prince.*/cambell-prince\/frontaccounting ci-image.yml master-ark none/" "$runs"
expect_status 1 "FrontAccounting with no green run" resolve master-ark "$comps"
expect_contains "fails" "no successful ci-image.yml push run on master-ark" "$OUT"

git -C "$fa" checkout -q --orphan rewritten
git -C "$fa" commit -qm rewritten
sed -i "s/^cambell-prince.*/cambell-prince\/frontaccounting ci-image.yml master-ark $c1/" "$runs"
expect_status 1 "a green commit outside the branch's history" resolve master-ark "$comps"
expect_contains "fails" "is not in master-ark's history" "$OUT"

finish
```

- [ ] **Step 2: Run the test to see it fail**

Run: `bash deploy/test/resolve-refs.sh`
Expected: FAIL everywhere (`deploy/resolve-refs.sh` does not exist).

- [ ] **Step 3: Implement**

`deploy/resolve-refs.sh`:

```bash
#!/usr/bin/env bash
#
# Pin every part of a release to its newest commit that passed CI, for the bms
# deploy workflow (.github/workflows/deploy-bms.yml).
#
#   deploy/resolve-refs.sh <fa_branch> "<components>" ["<overrides>"]
#
# Run in a FrontAccounting checkout of <fa_branch> with full history. Prints,
# for $GITHUB_OUTPUT, with notes on stderr:
#
#   ref=<sha>                                  FrontAccounting
#   components=<path|repo|sha[|composer]> ...  <components>, each ref pinned
#
# FrontAccounting: G is the head of the newest successful push run of
# ci-image.yml on <fa_branch>, H is HEAD. H when nothing between them touches
# the image's paths (so a docs-only push still ships), else G: H is then still
# being tested, and its run triggers its own deploy, or it failed.
# A component: the head of the newest successful push run of its ci.yml on the
# branch its ref names.
# <overrides>: space-separated <path>=<sha>, and frontaccounting=<sha>, used
# as given.
#
# Needs gh signed in (GH_TOKEN in CI). RESOLVE_FA_REPO names FrontAccounting's
# repository (default cambell-prince/frontaccounting).

set -euo pipefail
die() { printf 'resolve-refs: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

[ "$#" -ge 2 ] || die 'usage: resolve-refs.sh <fa_branch> "<components>" ["<overrides>"]'
fa_branch="$1"
components="$2"
overrides="${3:-}"
fa_repo="${RESOLVE_FA_REPO:-cambell-prince/frontaccounting}"
image_workflow=.github/workflows/ci-image.yml

declare -A pin=() used=()
for o in $overrides; do
    k="${o%%=*}"
    v="${o#*=}"
    [[ "$o" == *=* && "$v" =~ ^[0-9a-f]{40}$ ]] || die "override '$o' is not <path>=<40-hex commit>"
    pin[$k]="$v"
done

# newest_green <owner/repo> <workflow file> <branch>: the head commit of the
# newest successful push run, or nothing
newest_green() {
    gh api "repos/$1/actions/workflows/$2/runs?branch=$3&event=push&status=success&per_page=1" \
        --jq '.workflow_runs[0].head_sha // empty'
}

# repo_slug <url>: owner/name of a GitHub https or ssh URL
repo_slug() {
    local s="$1"
    s="${s#https://github.com/}"
    s="${s#git@github.com:}"
    s="${s%.git}"
    [[ "$s" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && printf '%s\n' "$s"
}

# The globs under "paths: &image-paths" in ci-image.yml
image_paths() {
    [ -f "$image_workflow" ] || die "no $image_workflow in $(pwd)"
    awk '/paths: &image-paths/ { on = 1; next }
         on && /^[[:space:]]*- / { sub(/^[[:space:]]*- /, ""); print; next }
         on { exit }' "$image_workflow" | tr -d "'\""
}

# touches_image <from> <to>: does any change between them fall under the
# image's paths? In a bash pattern * also matches /, so this can say yes where
# GitHub would say no; that only ever picks the older, green commit.
touches_image() {
    local f p pats
    mapfile -t pats < <(image_paths)
    [ "${#pats[@]}" -gt 0 ] || die "no paths under 'paths: &image-paths' in $image_workflow"
    while IFS= read -r f; do
        for p in "${pats[@]}"; do
            # shellcheck disable=SC2053 # $p is a glob on purpose
            [[ "$f" == $p ]] && return 0
        done
    done < <(git diff --name-only "$1" "$2")
    return 1
}

if [ -n "${pin[frontaccounting]:-}" ]; then
    fa="${pin[frontaccounting]}"
    used[frontaccounting]=1
    note "frontaccounting: $fa (override)"
else
    head="$(git rev-parse HEAD)"
    green="$(newest_green "$fa_repo" ci-image.yml "$fa_branch")" \
        || die "frontaccounting: could not read CI runs of $fa_repo"
    [ -n "$green" ] || die "frontaccounting: no successful ci-image.yml push run on $fa_branch"
    git merge-base --is-ancestor "$green" "$head" 2>/dev/null \
        || die "frontaccounting: $green, the last green commit, is not in $fa_branch's history at $head (shallow checkout, or a rewritten branch?)"
    if [ "$green" = "$head" ]; then
        fa="$head"
        note "frontaccounting: $fa (green)"
    elif touches_image "$green" "$head"; then
        fa="$green"
        note "frontaccounting: $fa, the last green commit; ${head:0:7} changes the image and has not passed CI image"
    else
        fa="$head"
        note "frontaccounting: $fa (nothing the image builds from changed since green ${green:0:7})"
    fi
fi

out=()
for c in $components; do
    IFS='|' read -r path repo ref mode extra <<< "$c"
    [ -n "$path" ] && [ -n "$repo" ] && [ -n "$ref" ] && [ -z "${extra:-}" ] \
        || die "'$c' is not path|repo|ref[|composer]"
    if [ -n "${pin[$path]:-}" ]; then
        sha="${pin[$path]}"
        used[$path]=1
        note "$path: $sha (override)"
    else
        slug="$(repo_slug "$repo")" || die "$path: '$repo' is not a GitHub repository URL"
        sha="$(newest_green "$slug" ci.yml "$ref")" || die "$path: could not read CI runs of $slug"
        [ -n "$sha" ] || die "$path: no successful ci.yml push run on $slug $ref"
        note "$path: $sha (green on $ref)"
    fi
    out+=("$path|$repo|$sha${mode:+|$mode}")
done

for k in "${!pin[@]}"; do
    [ -n "${used[$k]:-}" ] || die "override '$k' matches no component"
done

printf 'ref=%s\n' "$fa"
printf 'components=%s\n' "${out[*]}"
```

- [ ] **Step 4: Run the test to see it pass**

Run: `bash deploy/test/resolve-refs.sh`
Expected: `0 failed`.

- [ ] **Step 5: Lint and commit**

```bash
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:v0.10.0 deploy/resolve-refs.sh deploy/test/resolve-refs.sh
git add deploy/resolve-refs.sh deploy/test/resolve-refs.sh
git update-index --chmod=+x deploy/resolve-refs.sh deploy/test/resolve-refs.sh
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "deploy: resolve-refs.sh, the newest green commit of every part

Extensions resolve to the head of their newest successful push run of
ci.yml; FrontAccounting to master-ark's head unless something since the last
green CI image run touches the image's paths. Overrides pin parts by hand.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `deploy/sql-changes.sh`

**Files:**
- Create: `deploy/sql-changes.sh`, `deploy/test/sql-changes.sh`

**Interfaces:**
- Consumes: the manifest line format from Task 1 (`<name> <ref> <40-hex> <subject>`), and the `components` format.
- Produces:
  - `deploy/sql-changes.sh <previous manifest> <new manifest> "<components>"`
  - Findings go to stdout, one per line, as `<name>: <file under sql/>` or `<name>: cannot compare …` / `<name>: new in this deploy …`. Notes go to stderr.
  - It exits 0 except on usage errors (exit 1).

- [ ] **Step 1: Write the failing test**

`deploy/test/sql-changes.sh`:

```bash
#!/usr/bin/env bash
#
# sql-changes.sh: database changes between two manifests, FrontAccounting
# from git and components through a stand-in gh, and every comparison it
# cannot make.
#
#   deploy/test/sql-changes.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=../../docker/ci/test/lib.sh
. "$here/../../docker/ci/test/lib.sh"
root="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# gh stand-in: answers "gh api repos/<o>/<r>/compare/<a>...<b>" from
# $GH_STUB_COMPARE lines "<o>/<r> <a>...<b> <file>"; an unknown range is a 404.
mkdir "$work/bin"
cat > "$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = api ] || exit 2
[[ "$2" =~ ^repos/([^/]+/[^/]+)/compare/([0-9a-f]+\.\.\.[0-9a-f]+)$ ]] || exit 2
slug="${BASH_REMATCH[1]}"
range="${BASH_REMATCH[2]}"
hit=no
while read -r s r f; do
    if [ "$s" = "$slug" ] && [ "$r" = "$range" ]; then echo "$f"; hit=yes; fi
done < "$GH_STUB_COMPARE"
[ "$hit" = yes ] || { echo "HTTP 404" >&2; exit 1; }
EOF
chmod +x "$work/bin/gh"

fa="$work/fa"
git init -q -b master-ark "$fa"
git -C "$fa" config user.email test@example.com
git -C "$fa" config user.name test
echo '<?php' > "$fa/index.php"
git -C "$fa" add index.php
git -C "$fa" commit -qm one
f1="$(git -C "$fa" rev-parse HEAD)"
mkdir "$fa/sql"
echo 'ALTER TABLE x;' > "$fa/sql/alter.sql"
git -C "$fa" add sql
git -C "$fa" commit -qm two
f2="$(git -C "$fa" rev-parse HEAD)"

# sha40 <char>: a made-up 40-character commit id
sha40() { local s; s="$(printf '%040d' 0)"; printf '%s\n' "${s//0/$1}"; }
x1="$(sha40 1)"; x2="$(sha40 2)"; y1="$(sha40 3)"; z2="$(sha40 4)"; n1="$(sha40 5)"; w1="$(sha40 6)"; w2="$(sha40 7)"
comps="modules/x|https://github.com/o/x.git|main modules/y|https://github.com/o/y.git|main modules/z|https://github.com/o/z.git|main modules/n|https://github.com/o/n.git|main modules/w|git@github.com:o/w.git|main"
cat > "$work/prev" <<EOF
built 2026-10-20T00:00:00Z on test
frontaccounting master-ark $f1 one
modules/x main $x1 x
modules/y main $y1 y
modules/z main abc1234 z, from an older build
    composer: nodev
modules/w main $w1 w
EOF
cat > "$work/new" <<EOF
built 2026-10-21T00:00:00Z on test
frontaccounting $f2 $f2 two
modules/x $x2 $x2 x
modules/y $y1 $y1 y
modules/z $z2 $z2 z
modules/n $n1 $n1 n
modules/w $w2 $w2 w
EOF
cat > "$work/compare" <<EOF
o/x $x1...$x2 sql/update_2.sql
o/x $x1...$x2 README.md
EOF

changes() { (cd "$fa" && PATH="$work/bin:$PATH" GH_STUB_COMPARE="$work/compare" "$root/deploy/sql-changes.sh" "$@"); }

expect_status 0 "compares" changes "$work/prev" "$work/new" "$comps"
expect_contains "FrontAccounting's sql/ from git" "frontaccounting: sql/alter.sql" "$OUT"
expect_contains "a component's sql/ from GitHub" "modules/x: sql/update_2.sql" "$OUT"
expect_absent "only sql/" "README.md" "$OUT"
expect_absent "an unchanged component is not mentioned" "modules/y" "$OUT"
expect_contains "a short commit cannot be compared" "modules/z: cannot compare" "$OUT"
expect_contains "a new component is pointed out" "modules/n: new in this deploy" "$OUT"
expect_contains "a failed comparison is reported" "modules/w: cannot compare ${w1:0:7}..${w2:0:7} on GitHub" "$OUT"

: > "$work/empty"
expect_status 0 "the first deploy" changes "$work/empty" "$work/new" "$comps"
expect_contains "says there is nothing to compare" "no previous deploy" "$OUT"
expect_status 0 "and prints no findings" test -z "$(changes "$work/empty" "$work/new" "$comps" 2>/dev/null)"

expect_status 1 "usage" changes "$work/prev"

finish
```

- [ ] **Step 2: Run the test to see it fail**

Run: `bash deploy/test/sql-changes.sh`
Expected: FAIL (`deploy/sql-changes.sh` does not exist).

- [ ] **Step 3: Implement**

`deploy/sql-changes.sh`:

```bash
#!/usr/bin/env bash
#
# Say which database changes a deploy carries, for the bms deploy workflow.
#
#   deploy/sql-changes.sh <previous manifest> <new manifest> "<components>"
#
# The manifests are the server's .deploy-manifest (upload.sh previous) and the
# release's (build-release.sh). For every part whose commit differs, prints
# one line per file under sql/ that changed between the two commits:
#
#   modules/sgw_sales: sql/update_1.7.sql
#
# FrontAccounting is compared in this checkout (it needs full history),
# components through GitHub's compare API, by their repositories in
# <components>. A comparison it cannot make gets a line saying so. Notes go to
# stderr. Exits 0 unless the arguments are wrong: it informs a deploy and
# never stops one.

set -euo pipefail
die() { printf 'sql-changes: %s\n' "$*" >&2; exit 1; }

[ "$#" -eq 3 ] || die 'usage: sql-changes.sh <previous manifest> <new manifest> "<components>"'
prev="$1"
new="$2"
components="$3"
[ -f "$new" ] || die "no manifest at $new"

if [ ! -s "$prev" ]; then
    echo "sql-changes: no previous deploy recorded, so nothing to compare" >&2
    exit 0
fi

# commits <manifest>: "<name> <sha>" for each part recorded by full commit
commits() { sed -nE 's/^([^ ]+) [^ ]+ ([0-9a-f]{40})( .*)?$/\1 \2/p' "$1"; }

declare -A old=() seen=() repo=()
while read -r name _; do seen[$name]=1; done < <(grep -E '^[^ ]' "$prev")
while read -r name sha; do old[$name]="$sha"; done < <(commits "$prev")
for c in $components; do
    IFS='|' read -r path url _ <<< "$c"
    s="${url#https://github.com/}"
    s="${s#git@github.com:}"
    repo[$path]="${s%.git}"
done

while read -r name sha; do
    was="${old[$name]:-}"
    if [ -z "$was" ]; then
        if [ -n "${seen[$name]:-}" ]; then
            echo "$name: cannot compare, the previous deploy did not record its full commit"
        else
            echo "$name: new in this deploy; check its sql/ by hand"
        fi
        continue
    fi
    [ "$was" != "$sha" ] || continue
    range="${was:0:7}..${sha:0:7}"
    if [ "$name" = frontaccounting ]; then
        files="$(git diff --name-only "$was" "$sha" -- sql/ 2>/dev/null)" \
            || { echo "$name: cannot compare $range in this checkout"; continue; }
    elif [ -n "${repo[$name]:-}" ]; then
        files="$(gh api "repos/${repo[$name]}/compare/$was...$sha" --jq '.files[].filename' 2>/dev/null)" \
            || { echo "$name: cannot compare $range on GitHub"; continue; }
        files="$(grep '^sql/' <<< "$files" || true)"
    else
        echo "$name: cannot compare, it is not in the components list"
        continue
    fi
    while IFS= read -r f; do
        [ -z "$f" ] || echo "$name: $f"
    done <<< "$files"
done < <(commits "$new")
```

- [ ] **Step 4: Run the test to see it pass**

Run: `bash deploy/test/sql-changes.sh`
Expected: `0 failed`.

- [ ] **Step 5: Lint and commit**

```bash
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:v0.10.0 deploy/sql-changes.sh deploy/test/sql-changes.sh
git add deploy/sql-changes.sh deploy/test/sql-changes.sh
git update-index --chmod=+x deploy/sql-changes.sh deploy/test/sql-changes.sh
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "deploy: sql-changes.sh, the database changes a deploy carries

Compares the server's manifest with the release's and lists every file under
sql/ that changed, so a deploy can warn that a migration is due. It reports
what it cannot compare and never fails a deploy.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: An `ark` flavour of the CI image

**Files:**
- Modify: `docker/ci/build-image.sh`, `docker/ci/prune-images.sh:71-72`, `docker/ci/test/prune.sh`, `docker/ci/test/fixtures/prune/versions.json`, `.github/workflows/ci-image.yml`, `docker/ci/lib.sh:8` (comment), `docker/ci/plugin-test.sh:22` (comment), `.github/workflows/plugin-test.yml` (`fa` description)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `build-image.sh ark <php> <tag>…` builds from the checkout, as `cp` does.
  - On `master-ark`, and for PRs into it, CI image builds `ark-php7.4`, `ark-php8.3` and their `-<sha7>` tags.
  - `paths: &image-paths` stays exactly as it is (Task 3 reads it).

- [ ] **Step 1: Write the failing test**

Add to `docker/ci/test/fixtures/prune/versions.json`, before the closing `]`, after the id 13 entry (add a comma to that line):

```json
  {"id": 14, "created_at": "2026-09-05T00:00:00Z", "metadata": {"container": {"tags": ["ark-php7.4", "ark-php7.4-aaaaaaa"]}}},
  {"id": 15, "created_at": "2026-09-04T00:00:00Z", "metadata": {"container": {"tags": ["ark-php7.4-bbbbbbb"]}}},
  {"id": 16, "created_at": "2026-09-03T00:00:00Z", "metadata": {"container": {"tags": ["ark-php7.4-ccccccc"]}}},
  {"id": 17, "created_at": "2026-09-02T00:00:00Z", "metadata": {"container": {"tags": ["ark-php7.4-ddddddd"]}}},
  {"id": 18, "created_at": "2026-09-02T00:00:00Z", "metadata": {"container": {"tags": ["pr-20-ark-php7.4"]}}}
```

In `docker/ci/test/prune.sh`, change the first block's loops and count to:

```bash
for id in 5 8 10 11 12 17 18; do expect_contains "deletes version $id" "would delete $id " "$OUT"; done
for id in 1 2 3 4 6 7 9 13 14 15 16; do expect_absent "keeps version $id" "would delete $id " "$OUT"; done
expect_contains "says why for the old sha" "older than the newest 3 cp-php7.4-<sha>" "$OUT"
expect_contains "and for an old ark sha" "older than the newest 3 ark-php7.4-<sha>" "$OUT"
expect_contains "counts them" "7 version(s) would be deleted (dry run)" "$OUT"
```

- [ ] **Step 2: Run the test to see it fail**

Run: `docker/ci/test/prune.sh`
Expected: FAIL on "deletes version 17", "deletes version 18" and the count (unrecognised `ark-*` tags protect a version).

- [ ] **Step 3: Implement**

`docker/ci/prune-images.sh`, lines 71-72:

```bash
    def sha_tag: test("^(cp|upstream|ark)-php[0-9.]+-[0-9a-f]{7,40}$");
    def pr_tag: test("^pr-[0-9]+-(cp|upstream|ark)-php[0-9.]+$");
```

`docker/ci/build-image.sh`:
- Usage line 5: `#   docker/ci/build-image.sh [--cache-gha] <cp|ark|upstream> <php> <tag> [<tag>...]`
- After the `cp` description (lines 7-9), add:
  ```bash
  #   ark         the same, for a master-ark checkout; its own name keeps its
  #               images apart from master-cp's
  ```
- Line 28: `[ "$#" -ge 3 ] || die "usage: build-image.sh [--cache-gha] <cp|ark|upstream> <php> <tag>..."`
- Line 38: `    cp|ark)`
- Line 50: `    *) die "flavour must be cp, ark or upstream, not '$flavour'" ;;`

`docker/ci/lib.sh` line 8: `# flavour (cp, ark or upstream) and PHP version.`
`docker/ci/plugin-test.sh` line 22: `#   --fa cp|ark|upstream   FrontAccounting flavour (default: cp)`
`.github/workflows/plugin-test.yml`, the `fa` input's description:
`FrontAccounting flavour, cp (cambell-prince/frontaccounting master-cp), ark (its master-ark) or upstream`

`.github/workflows/ci-image.yml`:
- Under `on.push.branches`, after `- master-cp`, add `- master-ark`.
- Replace the matrix's `fa: [cp, upstream]` with:
  ```yaml
          # master-ark (pushes, and pull requests into it) builds its own
          # flavour; everything else builds master-cp's and upstream's.
          fa: ${{ fromJSON((github.base_ref || github.ref_name) == 'master-ark' && '["ark"]' || '["cp","upstream"]') }}
  ```
- Leave `paths: &image-paths` and its list untouched.

- [ ] **Step 4: Run the tests to see them pass**

Run: `docker/ci/test/prune.sh`
Expected: `0 failed`.

Run: `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.7 .github/workflows/ci-image.yml .github/workflows/plugin-test.yml`
Expected: no output.

- [ ] **Step 5: Build and smoke-test an ark image**

First check `cat /sys/devices/system/cpu/intel_pstate/no_turbo` prints `1`. If it doesn't, ask the user to run `echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo`, and wait.

```bash
docker/ci/build-image.sh ark 7.4 fa-ci:ark-php7.4-test
docker/ci/smoke-test.sh fa-ci:ark-php7.4-test
docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.description"}}' fa-ci:ark-php7.4-test
docker rmi fa-ci:ark-php7.4-test
```

Expected: the smoke test passes, and the description reads `FrontAccounting (ark, PHP 7.4) for plugin CI`.

- [ ] **Step 6: Commit**

```bash
git add docker/ci/build-image.sh docker/ci/prune-images.sh docker/ci/test/prune.sh docker/ci/test/fixtures/prune/versions.json docker/ci/lib.sh docker/ci/plugin-test.sh .github/workflows/ci-image.yml .github/workflows/plugin-test.yml
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "ci: An ark flavour of the CI image, built on master-ark

master-ark runs the same image build and smoke test as master-cp, tagged
ark-php<v>, so a push to it is tested before bms deploys it. Prune treats
ark tags like cp's.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The deploy workflow, the scripts' CI, and the README

**Files:**
- Create: `.github/workflows/deploy-bms.yml`, `.github/workflows/deploy-test.yml`
- Modify: `deploy/README.md` (new section at the end)

**Interfaces:**
- Consumes:
  - Task 1: `sh deploy/build-release.sh <ref> <dir> "<components>" <php>`, which leaves `build/release.manifest`.
  - Task 2: `sh deploy/upload.sh check|go|previous <dir> <user> <host> <path> <remote_user> [...]`, `build/release.deletes`, and exit 3 above the limit.
  - Task 3: `deploy/resolve-refs.sh master-ark "<components>" "<overrides>"`, which prints `ref=` and `components=`.
  - Task 4: `deploy/sql-changes.sh <prev> <new> "<components>"`, which prints findings on stdout.
  - Task 5: the `CI image` workflow name, run on `master-ark`.
  - Task 7: the `extension-green` dispatch.
- Produces: the `Deploy bms` workflow, with `workflow_dispatch` inputs `dry_run`, `refs` and `max_deletes`.

- [ ] **Step 1: Write `deploy-test.yml`**

```yaml
name: Deploy scripts

# deploy/test/run.sh: the release, upload, resolve and sql-changes scripts,
# with local fixtures and no network.

on:
  push:
    branches: [master-cp, master-ark]
    paths: &deploy-paths
      - deploy/**
      - upload-exclude.txt
      - makefile.json
      - .github/workflows/deploy-test.yml
  pull_request:
    paths: *deploy-paths

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
      - name: Test
        run: deploy/test/run.sh
```

- [ ] **Step 2: Write `deploy-bms.yml`**

```yaml
name: Deploy bms

# Deploys bms.saygoweb.com: FrontAccounting master-ark and the extensions its
# makefile.json lists, each at its newest commit that passed CI
# (deploy/resolve-refs.sh). It lives on master-cp, the default branch,
# because GitHub runs workflow_run and repository_dispatch workflows only from
# there; it builds from master-ark. See deploy/README.md.

on:
  workflow_run:
    workflows: [CI image]
    types: [completed]
    branches: [master-ark]
  repository_dispatch:
    types: [extension-green]
  workflow_dispatch:
    inputs:
      dry_run:
        description: Build and check only; change nothing on the server
        type: boolean
        default: true
      refs:
        description: Pin parts instead of resolving them, e.g. "modules/sgw_sales=<sha> frontaccounting=<sha>"
        type: string
        default: ''
      max_deletes:
        description: Refuse to deploy if more files than this would be deleted
        type: string
        default: '25'

permissions:
  contents: read
  actions: read

# One at a time. A pending run replaces an older pending one, which is fine:
# every run resolves afresh.
concurrency:
  group: deploy-bms
  cancel-in-progress: false

defaults:
  run:
    shell: bash

jobs:
  deploy:
    if: >-
      github.event_name != 'workflow_run'
      || (github.event.workflow_run.conclusion == 'success'
          && github.event.workflow_run.event == 'push')
    runs-on: ubuntu-24.04
    timeout-minutes: 30
    environment: bms
    env:
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      DEPLOY_USER: ${{ vars.DEPLOY_USER }}
      DEPLOY_HOST: ${{ vars.DEPLOY_HOST }}
      DEPLOY_PATH: ${{ vars.DEPLOY_PATH }}
      # A manual run goes live when dry_run is off. An automatic run goes live
      # only once DEPLOY_LIVE is true, which is set after bms runs 2.4.20.
      LIVE: ${{ (github.event_name == 'workflow_dispatch' && !inputs.dry_run) || (github.event_name != 'workflow_dispatch' && vars.DEPLOY_LIVE == 'true') }}
      MAX_DELETES: ${{ inputs.max_deletes || '25' }}
      REFS: ${{ inputs.refs }}
    steps:
      - uses: actions/checkout@v7
        with:
          ref: master-ark
          fetch-depth: 0

      - name: Say what started this
        env:
          PAYLOAD: ${{ toJSON(github.event.client_payload) }}
          CI_RUN: ${{ github.event.workflow_run.html_url }}
        run: |
          echo "event: $GITHUB_EVENT_NAME; live: $LIVE; max_deletes: $MAX_DELETES"
          [ -z "$CI_RUN" ] || echo "CI image run: $CI_RUN"
          [ "$GITHUB_EVENT_NAME" != repository_dispatch ] || echo "dispatch: $PAYLOAD"

      - name: Check the settings
        run: |
          if [ -z "$DEPLOY_USER" ] || [ -z "$DEPLOY_HOST" ] || [ -z "$DEPLOY_PATH" ]; then
              echo "::error::Set DEPLOY_USER, DEPLOY_HOST and DEPLOY_PATH in the bms environment"
              exit 1
          fi
          case "$MAX_DELETES" in
              ''|*[!0-9]*) echo "::error::max_deletes must be a number, not '$MAX_DELETES'"; exit 1 ;;
          esac

      - name: Resolve
        id: resolve
        run: |
          deploy/resolve-refs.sh master-ark "$(jq -r .variables.components makefile.json)" "$REFS" \
              > "$RUNNER_TEMP/refs"
          cat "$RUNNER_TEMP/refs" >> "$GITHUB_OUTPUT"
          echo "php=$(jq -r .variables.php makefile.json)" >> "$GITHUB_OUTPUT"

      - name: Build the release
        env:
          REF: ${{ steps.resolve.outputs.ref }}
          COMPONENTS: ${{ steps.resolve.outputs.components }}
          PHP: ${{ steps.resolve.outputs.php }}
        run: sh deploy/build-release.sh "$REF" build/release "$COMPONENTS" "$PHP"

      - name: Set up SSH
        env:
          SSH_KEY: ${{ secrets.BMS_SSH_KEY }}
          KNOWN_HOSTS: ${{ secrets.BMS_KNOWN_HOSTS }}
        run: |
          if [ -z "$SSH_KEY" ] || [ -z "$KNOWN_HOSTS" ]; then
              echo "::error::Set BMS_SSH_KEY and BMS_KNOWN_HOSTS in the bms environment"
              exit 1
          fi
          install -d -m 700 ~/.ssh
          printf '%s\n' "$SSH_KEY" > ~/.ssh/bms_deploy
          chmod 600 ~/.ssh/bms_deploy
          printf '%s\n' "$KNOWN_HOSTS" > ~/.ssh/known_hosts
          printf 'Host %s\n  IdentityFile ~/.ssh/bms_deploy\n  IdentitiesOnly yes\n  StrictHostKeyChecking yes\n  BatchMode yes\n' \
              "$DEPLOY_HOST" > ~/.ssh/config

      - name: Look for database changes
        env:
          COMPONENTS: ${{ steps.resolve.outputs.components }}
        run: |
          sh deploy/upload.sh previous build/release "$DEPLOY_USER" "$DEPLOY_HOST" "$DEPLOY_PATH" ""
          deploy/sql-changes.sh build/release.previous build/release.manifest "$COMPONENTS" \
              | tee build/sql-changes.txt
          while IFS= read -r line; do
              echo "::warning title=Database changes::$line"
          done < build/sql-changes.txt

      - name: Check
        run: sh deploy/upload.sh check build/release "$DEPLOY_USER" "$DEPLOY_HOST" "$DEPLOY_PATH" "" "$MAX_DELETES"

      - name: Deploy
        if: env.LIVE == 'true'
        run: sh deploy/upload.sh go build/release "$DEPLOY_USER" "$DEPLOY_HOST" "$DEPLOY_PATH" "" yes

      - name: Summary
        if: always()
        run: |
          {
              if [ "$LIVE" = true ]; then
                  echo "## bms deploy"
              else
                  echo "## bms deploy: dry run, nothing changed on the server"
              fi
              if [ -f build/release.manifest ]; then
                  printf '\n```\n'
                  cat build/release.manifest
                  printf '```\n'
              fi
              if [ -s build/sql-changes.txt ]; then
                  printf '\n### Database changes to apply by hand\n\n'
                  sed 's/^/- /' build/sql-changes.txt
              fi
              if [ -s build/release.deletes ]; then
                  printf '\n### Files deleted from the server\n\n'
                  sed 's/^/- `/; s/$/`/' build/release.deletes
              fi
          } >> "$GITHUB_STEP_SUMMARY"

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: bms-release
          path: |
            build/release.manifest
            build/release.check
            build/release.deletes
            build/sql-changes.txt
          if-no-files-found: ignore
```

Before committing, check the newest major of `actions/upload-artifact` with `gh api repos/actions/upload-artifact/releases/latest --jq .tag_name`, and use that major instead of `v4` if it is newer.

- [ ] **Step 3: Lint**

Run: `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.7 .github/workflows/deploy-bms.yml .github/workflows/deploy-test.yml`
Expected: no output. actionlint also runs shellcheck over the `run:` blocks. Fix what it reports.

- [ ] **Step 4: Check the `LIVE` expression by hand**

Write out its value for these five cases and confirm each in the commit message's notes to the reviewer:

| event | inputs.dry_run | vars.DEPLOY_LIVE | LIVE |
|---|---|---|---|
| workflow_dispatch | true | true | false |
| workflow_dispatch | false | (unset) | true |
| repository_dispatch | — | (unset) | false |
| workflow_run | — | true | true |
| workflow_run | — | false | false |

- [ ] **Step 5: Add the README section**

Append to `deploy/README.md`:

````markdown
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
them.
````

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/deploy-bms.yml .github/workflows/deploy-test.yml deploy/README.md
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "ci: Deploy bms from GitHub

deploy-bms.yml deploys master-ark and its extensions, each at its newest
green commit, on a green CI image run, an extension-green dispatch, or by
hand. Automatic runs stay dry until DEPLOY_LIVE is true. deploy-test.yml
runs deploy/test on changes to the deploy scripts.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `notify-deploy.yml` in each extension (pull requests, not merged)

**Files** (one per repository, on branch `ci/notify-deploy`):
- Create `.github/workflows/notify-deploy.yml` in:
  - saygoweb/frontaccounting-module-graphql (deploy branch `main`, component `modules/graphql`)
  - saygoweb/frontaccounting-module-mcp (`main`, `modules/mcp`)
  - saygoweb/frontaccounting-module-sgw_sales (`master`, `modules/sgw_sales`)
  - saygoweb/frontaccounting-module-sgw_import (`master`, `modules/sgw_import`)

**Interfaces:**
- Consumes: each repository's CI workflow, named `CI`, on its deploy branch.
- Produces: a repository_dispatch `extension-green` to cambell-prince/frontaccounting, with `client_payload` `{component, sha, run_url}`.

- [ ] **Step 1: Make a worktree per repository**

For each `m` in `graphql mcp sgw_sales sgw_import`, with `b` its deploy branch:

```bash
git -C /home/cambell/src/sgw/frontaccounting/modules/$m fetch origin
git -C /home/cambell/src/sgw/frontaccounting/modules/$m worktree add \
    /home/cambell/src/sgw/frontaccounting/.claude/worktrees/notify-$m -b ci/notify-deploy origin/$b
```

- [ ] **Step 2: Write the workflow**

In each worktree, write `.github/workflows/notify-deploy.yml`, replacing `<BRANCH>` and `<COMPONENT>` with the values listed under **Files**:

```yaml
name: Notify deploy

# When CI passes on <BRANCH>, ask cambell-prince/frontaccounting to deploy
# bms.saygoweb.com. Its deploy-bms.yml decides what to ship itself, so this
# only says "something went green". It is a workflow of its own, not a job in
# ci.yml, so it runs once CI has finished and counts as green.

on:
  workflow_run:
    workflows: [CI]
    types: [completed]
    branches: [<BRANCH>]

permissions: {}

jobs:
  dispatch:
    if: >-
      github.event.workflow_run.conclusion == 'success'
      && github.event.workflow_run.event == 'push'
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - name: Send extension-green
        env:
          GH_TOKEN: ${{ secrets.FA_DEPLOY_DISPATCH }}
          SHA: ${{ github.event.workflow_run.head_sha }}
          RUN_URL: ${{ github.event.workflow_run.html_url }}
        run: |
          if [ -z "$GH_TOKEN" ]; then
              echo "::notice::FA_DEPLOY_DISPATCH is not set, so no deploy was asked for"
              exit 0
          fi
          gh api repos/cambell-prince/frontaccounting/dispatches \
              -f event_type=extension-green \
              -f "client_payload[component]=<COMPONENT>" \
              -f "client_payload[sha]=$SHA" \
              -f "client_payload[run_url]=$RUN_URL"
```

- [ ] **Step 3: Lint**

In each worktree:
`docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.7 .github/workflows/notify-deploy.yml`
Expected: no output.

- [ ] **Step 4: Commit, push, open a PR**

In each worktree (`<repo>` is the repository name, `<b>` the deploy branch):

```bash
git add .github/workflows/notify-deploy.yml
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "ci: Ask for a bms deploy when CI passes on <b>

notify-deploy.yml sends extension-green to cambell-prince/frontaccounting
once CI succeeds on a push to <b>. It does nothing until the saygoweb
organisation secret FA_DEPLOY_DISPATCH is set.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin ci/notify-deploy
gh pr create -R saygoweb/<repo> --base <b> --head ci/notify-deploy \
    --title "ci: Ask for a bms deploy when CI passes on <b>" \
    --body "Part of automatic deploys of bms.saygoweb.com (cambell-prince/frontaccounting, docs/superpowers/specs/2026-10-20-bms-auto-deploy-design.md). Sends \`extension-green\` once CI succeeds on a push to \`<b>\`; a no-op until \`FA_DEPLOY_DISPATCH\` is set. **Merge only during rollout step 8**, after bms runs 2.4.20 and \`DEPLOY_LIVE\` is set.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

Do not merge. Report the four PR URLs.

---

### Task 8: bms's site settings on `merge/master-cp-into-master-ark`

**Run only after the user has merged `feature/bms-auto-deploy` into `master-cp`.**

**Files:**
- Modify: `makefile.json` in `/home/cambell/src/sgw/frontaccounting/.claude/worktrees/merge-ark` (branch `merge/master-cp-into-master-ark`)

**Interfaces:**
- Consumes: everything on `master-cp` from Tasks 1-6.
- Produces: `master-ark`-to-be with `components` (the four extensions over https), `host` `aws1.saygoweb.com`, `user` `""`, `path` `bms/htdocs/`, and `remote_user` `""`.

- [ ] **Step 1: Merge master-cp**

```bash
cd /home/cambell/src/sgw/frontaccounting/.claude/worktrees/merge-ark
git fetch origin
git merge origin/master-cp
```

`makefile.json` will likely conflict in `variables`. Resolve it as in Step 2. Any other conflict is the user's call, so stop and report it.

- [ ] **Step 2: Set bms's variables**

In `makefile.json`'s `variables`, make these match exactly, removing `dest`. Keep `db_ssh`, `db`, `db_opts` and `file` as the branch has them, and take every target from master-cp:

```json
        "components": "modules/graphql|https://github.com/saygoweb/frontaccounting-module-graphql.git|main modules/mcp|https://github.com/saygoweb/frontaccounting-module-mcp.git|main modules/sgw_sales|https://github.com/saygoweb/frontaccounting-module-sgw_sales.git|master modules/sgw_import|https://github.com/saygoweb/frontaccounting-module-sgw_import.git|master",
        "php": "7.4.33",
        "user": "",
        "host": "aws1.saygoweb.com",
        "path": "bms/htdocs/",
        "remote_user": "",
        "max_deletes": "",
```

- [ ] **Step 3: Verify**

```bash
jq -e '.variables | has("dest") | not' makefile.json
jq -r .variables.components makefile.json | tr ' ' '\n'
deploy/test/run.sh
```

Expected: `true`, the four component lines, then `all passed`.

Then resolve against the real repositories. This is read-only, and needs `gh` signed in:

```bash
deploy/resolve-refs.sh master-ark "$(jq -r .variables.components makefile.json)"
```

Expected: a `components=` line with four pinned SHAs. The `frontaccounting` line fails with "no successful ci-image.yml push run on master-ark" until `master-ark` has a green ark build. That failure is expected here, so report it rather than fixing it.

- [ ] **Step 4: Commit** (the merge commit, if it conflicted, or a commit of its own)

```bash
git add makefile.json
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "makefile: bms's deploy settings for GitHub deploys

aws1.saygoweb.com:bms/htdocs/ as the site user (user= on the command line,
DEPLOY_USER in CI); graphql, mcp, sgw_sales and sgw_import over https; no
bootstrap theme, which bms does not use.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Do not push. The controller pushes this branch, and never `master-ark`.
