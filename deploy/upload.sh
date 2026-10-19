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
#           deploy, to <dir>.previous; an empty file when the server says that
#           file is missing (any other error, such as a wrong path, fails)
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
    mkdir -p "$(dirname "$out")"
    rm -f "$out" "$out.err"
    if rsync -t --rsync-path="$rsync_path" --rsh="$rsh" "${dest}.deploy-manifest" "$out" 2> "$out.err"; then
        echo "==> previous deploy: $(head -2 "$out" | tail -1)"
    elif grep -q '\.deploy-manifest".*No such file' "$out.err"; then
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
        # files only: rsync also lists each directory it would remove, as dir/
        deletes="$(grep -vc '/$' "$dir.deletes" || true)"
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
