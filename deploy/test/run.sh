#!/usr/bin/env bash
#
# The deploy/ test suite: every other script in deploy/test. No network, no
# docker.
#
#   deploy/test/run.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failed=()
for t in "$here"/*.sh; do
    name="$(basename "$t")"
    [ "$name" = run.sh ] && continue
    printf '\n## %s\n' "$name"
    bash "$t" || failed+=("$name")
done

if [ "${#failed[@]}" -gt 0 ]; then
    printf '\nFAILED: %s\n' "${failed[*]}"
    exit 1
fi
printf '\nall passed\n'
