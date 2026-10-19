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
printf 'a file that will move out of the image paths\n' > "$fa/reporting/old.txt"
cp "$root/.github/workflows/ci-image.yml" "$fa/.github/workflows/"
git -C "$fa" add .github reporting
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

# a rename out of an image path still counts: the old path is a change
git -C "$fa" checkout -q -b renamed "$c2"
git -C "$fa" mv reporting/old.txt docs/old.txt
git -C "$fa" commit -qm rename
expect_status 0 "a head that renames a file out of an image path" resolve master-ark "$comps"
expect_contains "takes the last green commit" "ref=$c1" "$OUT"
git -C "$fa" checkout -q "$c3"

# a comment or a blank line inside the image-paths list must not cut it short:
# reporting/** comes after both, and the head changes only reporting/
git -C "$fa" checkout -q -b commented "$c3"
sed -i "0,/^      - '\\*.php'\$/s//      - '*.php'\\n\\n      # a note in the list\\n/" "$fa/.github/workflows/ci-image.yml"
git -C "$fa" commit -qam "comment in the list"
g1="$(git -C "$fa" rev-parse HEAD)"
echo more > "$fa/reporting/more.txt"
git -C "$fa" add reporting
git -C "$fa" commit -qm "report again"
sed "s/ master-ark $c1/ master-ark $g1/" "$runs" > "$runs.commented"
expect_contains "the test list has a comment" "# a note in the list" "$(cat "$fa/.github/workflows/ci-image.yml")"
OLD_RUNS="$runs"; runs="$runs.commented"
expect_status 0 "a head that changes a glob after a comment and a blank line" resolve master-ark "$comps"
expect_contains "takes the last green commit" "ref=$g1" "$OUT"
runs="$OLD_RUNS"
git -C "$fa" checkout -q "$c3"

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
expect_status 1 "refuses an override with no path" resolve master-ark "$comps" "=$e1"
expect_contains "with the usual message" "is not <path>=<40-hex commit>" "$OUT"

expect_status 0 "a component whose ref is already a commit" resolve master-ark "modules/p|https://github.com/o/nowhere.git|$e1"
expect_contains "is passed through" "components=modules/p|https://github.com/o/nowhere.git|$e1" "$OUT"
expect_contains "and says it was pinned" "pinned in components" "$OUT"

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
