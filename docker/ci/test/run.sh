#!/usr/bin/env bash
#
# The docker/ci test suite.
#
#   docker/ci/test/run.sh [<image>]
#
# prune.sh needs no image and always runs. With an image (the argument, else
# $FA_CI_IMAGE) image.sh, attach.sh and driver.sh run against it.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

image="${1:-${FA_CI_IMAGE:-}}"
failed=()
run() {
    printf '\n## %s\n' "$1"
    "$here/$1" || failed+=("$1")
}

run prune.sh
if [ -n "$image" ]; then
    export FA_CI_IMAGE="$image"
    run image.sh
    run attach.sh
    run driver.sh
else
    printf '\n(no image given: skipped image.sh, attach.sh, driver.sh)\n'
fi

if [ "${#failed[@]}" -gt 0 ]; then
    printf '\nFAILED: %s\n' "${failed[*]}"
    exit 1
fi
printf '\nall passed\n'
