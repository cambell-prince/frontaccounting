#!/usr/bin/env bash
#
# prune-images.sh's decision, on the fixture versions and no network.
#
#   docker/ci/test/prune.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

p="$here/../prune-images.sh"
f="$here/fixtures/prune/versions.json"

expect_status 0 "dry run" env PRUNE_VERSIONS_FILE="$f" PRUNE_OPEN_PRS='17 19' "$p" --dry-run
for id in 5 8 10 11 12; do expect_contains "deletes version $id" "would delete $id " "$OUT"; done
for id in 1 2 3 4 6 7 9 13; do expect_absent "keeps version $id" "would delete $id " "$OUT"; done
expect_contains "says why for the old sha" "older than the newest 3 cp-php7.4-<sha>" "$OUT"
expect_contains "counts them" "5 version(s) would be deleted (dry run)" "$OUT"

expect_status 0 "--keep 1" env PRUNE_VERSIONS_FILE="$f" PRUNE_OPEN_PRS='17' "$p" --dry-run --keep 1
for id in 3 4; do expect_contains "--keep 1 also deletes version $id" "would delete $id " "$OUT"; done
expect_absent "--keep 1 keeps version 2" "would delete 2 " "$OUT"

expect_status 0 "--pr 17 drops that PR's images only" env PRUNE_VERSIONS_FILE="$f" "$p" --dry-run --pr 17
expect_contains "PR 17's image" "would delete 9 " "$OUT"
expect_absent "not PR 18's" "would delete 10 " "$OUT"

expect_status 0 "nothing to do" env PRUNE_VERSIONS_FILE="$f" "$p" --dry-run --pr 99
expect_contains "and says so" "nothing to delete" "$OUT"

expect_status 1 "--keep needs a number" "$p" --keep x
expect_status 1 "--pr needs a number" "$p" --pr x
expect_status 1 "unknown arguments are refused" "$p" --bogus
finish
