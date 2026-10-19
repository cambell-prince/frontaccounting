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
        out="$(gh api "repos/${repo[$name]}/compare/$was...$sha" --jq '.status, (.files[].filename)' 2>/dev/null)" \
            || { echo "$name: cannot compare $range on GitHub"; continue; }
        if [ "$(head -n1 <<< "$out")" = behind ]; then
            # the new commit is an ancestor of the old: a rollback. What the
            # old direction would have undone is the reverse comparison.
            echo "$name: rolled back from ${was:0:7} to ${sha:0:7}; sql/ changes in the range it left:"
            out="$(gh api "repos/${repo[$name]}/compare/$sha...$was" --jq '.status, (.files[].filename)' 2>/dev/null)" \
                || { echo "$name: cannot compare $range on GitHub"; continue; }
        fi
        files="$(tail -n +2 <<< "$out")"
        if [ "$(grep -c . <<< "$files" || true)" -ge 300 ]; then
            echo "$name: cannot fully compare $range (300 or more files changed); check its sql/ by hand"
            continue
        fi
        files="$(grep '^sql/' <<< "$files" || true)"
    else
        echo "$name: cannot compare, it is not in the components list"
        continue
    fi
    while IFS= read -r f; do
        [ -z "$f" ] || echo "$name: $f"
    done <<< "$files"
done < <(commits "$new")
