#!/usr/bin/env bash
#
# Check a built CI image before it is pushed, with the docker/ci test suite:
# it boots ready, FrontAccounting signs in, modules activate through FA's own
# form, and plugin-test.sh drives a run end to end.
#
#   docker/ci/smoke-test.sh <image>

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$#" -eq 1 ] || { echo "usage: smoke-test.sh <image>" >&2; exit 2; }
exec "$here/test/run.sh" "$1"
