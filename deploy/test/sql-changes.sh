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
# $GH_STUB_COMPARE lines "<o>/<r> <a>...<b> <status> <file>"; prints the
# status, then the files (what the script's --jq asks for). An unknown range
# is a 404.
mkdir "$work/bin"
cat > "$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = api ] || exit 2
[[ "$2" =~ ^repos/([^/]+/[^/]+)/compare/([0-9a-f]+\.\.\.[0-9a-f]+)$ ]] || exit 2
slug="${BASH_REMATCH[1]}"
range="${BASH_REMATCH[2]}"
hit=no
while read -r s r st f; do
    if [ "$s" = "$slug" ] && [ "$r" = "$range" ]; then
        [ "$hit" = yes ] || echo "$st"
        echo "$f"; hit=yes
    fi
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
x1="$(sha40 1)"; x2="$(sha40 2)"; y1="$(sha40 3)"; z2="$(sha40 4)"; n1="$(sha40 5)"; w1="$(sha40 6)"; w2="$(sha40 7)"; r1="$(sha40 8)"; r2="$(sha40 9)"; q1="$(sha40 b)"; q2="$(sha40 c)"; d1="$(sha40 d)"; d2="$(sha40 e)"
comps="modules/x|https://github.com/o/x.git|main modules/y|https://github.com/o/y.git|main modules/z|https://github.com/o/z.git|main modules/n|https://github.com/o/n.git|main modules/w|git@github.com:o/w.git|main modules/r|https://github.com/o/r.git|main modules/q|https://github.com/o/q.git|main modules/d|https://github.com/o/d.git|main"
cat > "$work/prev" <<EOF
built 2026-10-20T00:00:00Z on test
frontaccounting master-ark $f1 one
modules/x main $x1 x
modules/y main $y1 y
modules/z main abc1234 z, from an older build
    composer: nodev
modules/w main $w1 w
modules/r main $r1 r
modules/q main $q1 q
modules/d main $d1 d
EOF
cat > "$work/new" <<EOF
built 2026-10-21T00:00:00Z on test
frontaccounting $f2 $f2 two
modules/x $x2 $x2 x
modules/y $y1 $y1 y
modules/z $z2 $z2 z
modules/n $n1 $n1 n
modules/w $w2 $w2 w
modules/r $r2 $r2 r
modules/q $q2 $q2 q
modules/d $d2 $d2 d
EOF
cat > "$work/compare" <<EOF
o/x $x1...$x2 ahead sql/update_2.sql
o/x $x1...$x2 ahead README.md
o/d $d1...$d2 diverged sql/update_4.sql
o/r $r1...$r2 behind
o/r $r2...$r1 ahead sql/update_3.sql
o/r $r2...$r1 ahead README.md
EOF
for i in $(seq 1 300); do echo "o/q $q1...$q2 ahead file$i.txt"; done >> "$work/compare"

changes() { (cd "$fa" && PATH="$work/bin:$PATH" GH_STUB_COMPARE="$work/compare" "$root/deploy/sql-changes.sh" "$@"); }

expect_status 0 "compares" changes "$work/prev" "$work/new" "$comps"
expect_contains "FrontAccounting's sql/ from git" "frontaccounting: sql/alter.sql" "$OUT"
expect_contains "a component's sql/ from GitHub" "modules/x: sql/update_2.sql" "$OUT"
expect_absent "only sql/" "README.md" "$OUT"
expect_absent "an unchanged component is not mentioned" "modules/y" "$OUT"
expect_contains "a short commit cannot be compared" "modules/z: cannot compare" "$OUT"
expect_contains "a new component is pointed out" "modules/n: new in this deploy" "$OUT"
expect_contains "a failed comparison is reported" "modules/w: cannot compare ${w1:0:7}..${w2:0:7} on GitHub" "$OUT"
expect_contains "a rollback is said to be one" "modules/r: rolled back from ${r1:0:7} to ${r2:0:7}" "$OUT"
expect_contains "and lists what the rolled-back range changed in sql/" "modules/r: sql/update_3.sql" "$OUT"
expect_contains "a diverged history is flagged" "modules/d: history diverged between ${d1:0:7} and ${d2:0:7}; check its sql/ by hand" "$OUT"
expect_contains "and still lists the sql/ the compare returned" "modules/d: sql/update_4.sql" "$OUT"
expect_contains "300 files is a truncated compare" "modules/q: cannot fully compare ${q1:0:7}..${q2:0:7} (300 or more files changed); check its sql/ by hand" "$OUT"

: > "$work/empty"
expect_status 0 "the first deploy" changes "$work/empty" "$work/new" "$comps"
expect_contains "says there is nothing to compare" "no previous deploy" "$OUT"
expect_status 0 "and prints no findings" test -z "$(changes "$work/empty" "$work/new" "$comps" 2>/dev/null)"

expect_status 1 "usage" changes "$work/prev"

finish
