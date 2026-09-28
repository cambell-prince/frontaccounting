# shellcheck shell=bash
# Assertions for the docker/ci tests. Sourced, not run.

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
fail() {
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n' "$1"
    [ -z "${2:-}" ] || printf '%s\n' "$2" | tail -n 40 | sed 's/^/        /'
}

# expect_status <want> <label> <command...>: run the command, compare its exit
# status. Its combined output is left in $OUT for the checks that follow.
expect_status() {
    local want="$1" label="$2" got
    shift 2
    set +e
    OUT="$("$@" 2>&1)"
    got=$?
    set -e
    if [ "$got" -eq "$want" ]; then pass "$label"; else fail "$label (exit $got, wanted $want)" "$OUT"; fi
}

# expect_contains <label> <needle> <haystack>
expect_contains() {
    case "$3" in *"$2"*) pass "$1" ;; *) fail "$1 (no '$2')" "$3" ;; esac
}

# expect_absent <label> <needle> <haystack>
expect_absent() {
    case "$3" in *"$2"*) fail "$1 ('$2' is there)" "$3" ;; *) pass "$1" ;; esac
}

finish() {
    printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
    [ "$FAIL" -eq 0 ]
}
