#!/bin/sh
# rsync a built release to the server, for `make.phar deploy` and `deploy-check`.
#
#   deploy/upload.sh check|go <dir> <dest> <remote_user> <confirm>
#
# check  dry run: lists what would change, and every file the server would lose
# go     the upload itself; needs <confirm> = yes
#
# --delete makes the server match the release, except for:
#   - anything upload-exclude.txt names, which is neither sent nor deleted
#     (configuration, company data, tmp/, extension settings and uploads)
#   - protected top-level entries of modules/, themes/ and lang/: an extension,
#     theme or language installed on the server but not in this release is left
#     alone. Stale files inside ones the release does carry are still removed.
set -eu

mode="$1"
dir="$2"
dest="$3"
remote_user="$4"
confirm="${5:-}"

[ -n "$dest" ] || { echo "upload: no destination; set dest in makefile.json or pass dest=user@host:/path/" >&2; exit 1; }
[ -f "$dir.ok" ] && [ -d "$dir" ] || { echo "upload: no complete release in $dir; run 'make.phar release' (and check it succeeded)" >&2; exit 1; }
case "$dest" in */) ;; *) echo "upload: dest must end with / ($dest)" >&2; exit 1 ;; esac

rsync_path="rsync"
[ -z "$remote_user" ] || rsync_path="sudo -u $remote_user rsync"

set -- -rzlt --chmod=Dug=rwx,Fug=rw,o-rwx --delete \
    --exclude-from=upload-exclude.txt \
    --filter='P /modules/*' --filter='P /themes/*' --filter='P /lang/*' \
    --rsync-path="$rsync_path" --rsh=ssh

echo "==> release: $(head -2 "$dir.manifest" | tail -1)"
case "$mode" in
    check)
        out="$dir.check"
        rsync "$@" --dry-run --itemize-changes "$dir/" "$dest" > "$out"
        echo "==> dry run against $dest: $(grep -c '^[<>]f' "$out" || true) file(s) to send"
        if grep -q '^\*deleting' "$out"; then
            echo "==> the server would lose these:"
            grep '^\*deleting' "$out"
        else
            echo "==> nothing on the server would be deleted"
        fi
        echo "==> full list: $out"
        ;;
    go)
        [ "$confirm" = yes ] || { echo "upload: this changes $dest; run 'make.phar deploy-check' first, then 'make.phar deploy confirm=yes'" >&2; exit 1; }
        rsync "$@" --stats "$dir/" "$dest"
        ;;
    *)
        echo "upload: mode must be check or go" >&2; exit 1 ;;
esac
