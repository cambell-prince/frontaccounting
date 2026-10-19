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
    # older than the release, so rsync's size+mtime check can't skip a file
    # whose content differs but whose size matches ("old" and "new")
    find "$1" -type f -exec touch -d '2 days ago' {} +
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

expect_status 1 "previous with a missing remote directory fails" up previous "$rel" u h "$work/nodir/" ""
expect_absent "and does not call it 'none recorded'" "no previous deploy" "$OUT"
expect_status 0 "previous creates the local directory" up previous "$work/new/sub/release" u h "$srv/" ""
expect_status 0 "and writes there" test -f "$work/new/sub/release.previous"

# a stale directory counts as its files, not as itself
mkdir "$srv/staledir"
echo 1 > "$srv/staledir/a"
echo 2 > "$srv/staledir/b"
expect_status 0 "check with a stale directory" up check "$rel" u h "$srv/" "" 4
expect_contains "counts files, not the directory" "4 to delete" "$OUT"
expect_contains "the list still names the directory" "staledir/" "$(cat "$rel.deletes")"
expect_status 3 "the limit counts files" up check "$rel" u h "$srv/" "" 3
rm -r "$srv/staledir"

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
