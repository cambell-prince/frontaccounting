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
    git -C "$1" config uploadpack.allowFilter true
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

expect_status 0 "builds with a branch ref" build HEAD "$b" "modules/ext|file://$work/ext|main" 7.4.33
expect_contains "checks out the branch head" "two" "$(cat "$b/modules/ext/a.txt")"
expect_contains "records FrontAccounting's full commit" "frontaccounting HEAD $fa_sha fa commit" "$(cat "$b.manifest")"
expect_contains "records the component's full commit" "modules/ext main $second second" "$(cat "$b.manifest")"
expect_status 0 "writes .ok" test -f "$b.ok"
expect_status 0 "leaves no .git in the component" test ! -e "$b/modules/ext/.git"
expect_status 0 "the release carries .deploy-manifest" cmp "$b.manifest" "$b/.deploy-manifest"

expect_status 0 "builds with a commit ref" build "$fa_sha" "$b" "modules/ext|file://$work/ext|$first" 7.4.33
expect_contains "checks out exactly that commit" "one" "$(cat "$b/modules/ext/a.txt")"
expect_contains "records it" "modules/ext $first $first first" "$(cat "$b.manifest")"
expect_status 0 "leaves no .git after a commit ref either" test ! -e "$b/modules/ext/.git"

# sha40 <char>: a made-up 40-character commit id
sha40() { local s; s="$(printf '%040d' 0)"; printf '%s\n' "${s//0/$1}"; }
missing="$(sha40 f)"
expect_status 128 "an unknown commit fails (git's status)" build HEAD "$b" "modules/ext|file://$work/ext|$missing" 7.4.33
expect_status 0 "and leaves no .ok" test ! -f "$b.ok"
git -C "$work/ext" tag v2.0.0
expect_status 0 "builds a tagged component" build HEAD "$b" "modules/ext|file://$work/ext|main" 7.4.33
expect_contains "writes the component's _init/config" "Version: 2.4-2.0.0" "$(cat "$b/modules/ext/_init/config")"
expect_contains "names the package by its path" "Package: ext" "$(cat "$b/modules/ext/_init/config")"
expect_contains "the manifest has the version" "    version: 2.4-2.0.0" "$(cat "$b.manifest")"
echo three > "$work/ext/a.txt"; git -C "$work/ext" commit -qam third
third="$(git -C "$work/ext" rev-parse --short=7 HEAD)"
expect_status 0 "builds a commit after the tag" build HEAD "$b" "modules/ext|file://$work/ext|$(git -C "$work/ext" rev-parse HEAD)" 7.4.33
expect_contains "version after a tag, from a commit ref" "Version: 2.4-2.0.0-1-g$third" "$(cat "$b/modules/ext/_init/config")"
expect_status 0 "still no .git" test ! -e "$b/modules/ext/.git"

# A component whose version cannot be worked out fails the build: run a copy
# of the script beside an fa-module that fails.
mkdir -p "$work/stub/deploy" "$work/stub/docker/ci"
cp "$root/deploy/build-release.sh" "$work/stub/deploy/"
printf '#!/bin/sh\n[ "$1" != version ] || { echo "fa-module: no version" >&2; exit 1; }\n' > "$work/stub/docker/ci/fa-module"
stubbed() { (cd "$work/fa" && sh "$work/stub/deploy/build-release.sh" "$@"); }
expect_status 1 "a component with no version fails the build" stubbed HEAD "$b" "modules/ext|file://$work/ext|main" 7.4.33
expect_status 0 "and leaves no .ok" test ! -f "$b.ok"
expect_absent "and no 'version:' line with nothing after it" "version: " "$(cat "$b.manifest")"

# A component given as a plain local path (no file://) still builds.
expect_status 0 "builds a component from a plain path" build HEAD "$b" "modules/ext|$work/ext|main" 7.4.33
expect_contains "plain path: checks out the head" "three" "$(cat "$b/modules/ext/a.txt")"
expect_status 0 "builds a plain-path component at a commit" build HEAD "$b" "modules/ext|$work/ext|$first" 7.4.33
expect_contains "plain path: exactly that commit" "one" "$(cat "$b/modules/ext/a.txt")"

finish
