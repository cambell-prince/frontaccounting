#!/usr/bin/env bash
#
# docker/ci/fa-module against local fixture repositories: the version rule,
# _init/config, and packages that hold only tracked, non-export-ignored files.
# No network. composer is skipped: no fixture module has a composer.json
# that needs installing (one has it only to name the module).
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
    printf '_init/\nbuild/\nuploads/\n' > "$1/.gitignore"
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

expect_status 1 "config on a shallow clone fails" fam config "$work/shallow"
expect_status 0 "and writes no file" test ! -e "$work/shallow/_init/config"
expect_status 1 "config on a non-repo fails" fam config "$work"
expect_status 0 "and writes no file there either" test ! -e "$work/_init/config"

# Tags that are not versions are skipped; the nearest real version tag counts.
r="$work/rc_mod"; mkmod "$r"; git -C "$r" tag v1.0.0
echo a >> "$r/hooks.php"; git -C "$r" commit -qam two
git -C "$r" tag v1.0.0-rc1; git -C "$r" tag 2024-10-01
expect_status 0 "rc and date tags are skipped" fam version "$r"
expect_contains "nearest real version tag is used" "1.0.0-1-g$(git -C "$r" rev-parse --short=7 HEAD)" "$OUT"

# Two version tags on one commit: the highest wins.
q="$work/two_tags"; mkmod "$q"; git -C "$q" tag v1.0.0; git -C "$q" tag v1.0.1
expect_status 0 "two tags on HEAD" fam version "$q"
expect_contains "the highest is the version" "$(printf '1.0.1\n2.4-1.0.1')" "$OUT"
git -C "$q" tag v1.0.10; git -C "$q" tag v1.0.9
expect_contains "highest by version order, not text" "$(printf '1.0.10\n')" "$(fam version "$q")"

git -C "$m" tag v1.5.0
expect_status 0 "config" fam config "$m"
cfg="$(cat "$m/_init/config"; echo END)"
expect_contains "config: package" "Package: demo_mod" "$cfg"
expect_contains "config: name defaults to id" "Name: demo_mod" "$cfg"
expect_contains "config: version" "Version: 2.4-1.5.0" "$cfg"
expect_contains "config ends with a blank line" "$(printf '2.4-1.5.0\n\nEND')" "$cfg"

# An existing _init/config keeps its other keys.
e="$work/keep_mod"; mkmod "$e"; git -C "$e" tag v3.0.0
mkdir -p "$e/_init"
printf 'Package: old\nName: Old Name\nDescription: x\nDepends: y\nVersion: 1.1\n' > "$e/_init/config"
expect_status 0 "config over an existing config" fam config "$e"
cfg="$(cat "$e/_init/config"; echo END)"
expect_contains "keeps Description" "Description: x" "$cfg"
expect_contains "keeps Depends" "Depends: y" "$cfg"
expect_contains "gets the new Version" "Version: 2.4-3.0.0" "$cfg"
expect_absent "old Version gone" "Version: 1.1" "$cfg"
expect_contains "Package is the id" "Package: keep_mod" "$cfg"
expect_contains "Name is replaced" "Name: keep_mod" "$cfg"
expect_contains "still ends with a blank line" "$(printf '3.0.0\n\nEND')" "$cfg"
expect_status 0 "config twice" fam config "$e"
expect_contains "idempotent" "$cfg" "$(cat "$e/_init/config"; echo END)"
printf 'Description: only\n' > "$e/_init/config"
expect_status 0 "config over a file without the three keys" fam config "$e"
cfg="$(cat "$e/_init/config")"
expect_contains "adds Version" "Version: 2.4-3.0.0" "$cfg"
expect_contains "keeps Description there too" "Description: only" "$cfg"

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
pout="$(fam package "$m" "$out" 2>/dev/null)"
expect_status 0 "stdout is exactly the two paths" test "$pout" = "$(printf '%s\n%s' "$tgz" "$zip")"
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

# composer's chatter goes to stderr, never into the two paths on stdout.
mkdir -p "$work/bin"
printf '#!/bin/sh\necho "composer noise: $*"\n' > "$work/bin/composer"; chmod +x "$work/bin/composer"
c="$work/comp_mod"; mkmod "$c"
echo '{"name":"x/y"}' > "$c/composer.json"; git -C "$c" add composer.json; git -C "$c" commit -qm composer
cout="$(PATH="$work/bin:$PATH" fam package "$c" "$work/cdist" 2>/dev/null)"
expect_status 0 "with composer: stdout is exactly two lines" test "$(printf '%s\n' "$cout" | wc -l)" = 2
expect_absent "with composer: no composer noise on stdout" "noise" "$cout"

finish
