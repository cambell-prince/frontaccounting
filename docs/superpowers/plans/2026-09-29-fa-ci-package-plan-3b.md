# master-ark: Rehearse the Live Upgrade on a Development Environment (plan 3B)

> **For agentic workers:** REQUIRED SUB-SKILL: Use cjp:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task, wave by wave per the Execution Schedule. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Run only after plan 3A is merged to master-cp**, including its republished images. This plan consumes 3A's `docker/ci/plugin-dev.sh`.

**Goal:** Rehearse the 2.4.3 → 2.4.20 production upgrade of bms.saygoweb.com on a copy of the live database. It runs in a package development environment on master-ark's own code, with graphql, sgw_sales, sgw_import and the bootstrap theme, and live's extension ids.

**Architecture:** The master-ark upgrade branch takes master-cp, which brings the package. `build-image.sh cp` run in that checkout builds an image of master-ark's code. `docker/upgrade/rehearse` is rewritten as a thin wrapper over `plugin-dev.sh`: the backup is the dataset, live's `installed_extensions.php` gives the ids, and activation applies the modules' upgrade SQL through FA as the real upgrade will. `rehearse migrate` adds the core preferences, and `rehearse check` reports before and after.

**Tech Stack:** bash, Docker, the FA CI package (`docker/ci`), MariaDB, FrontAccounting master-ark (2.4.20).

**Spec:** `docs/superpowers/specs/2026-09-28-fa-ci-package-design.md` §7 (and §6)

## Global Constraints

- Branch `merge/master-cp-into-master-ark` in `/home/cambell/src/sgw/frontaccounting/.claude/worktrees/merge-ark`. It is never pushed to `master-ark`; fast-forwarding master-ark is the user's decision after the rehearsal.
- Image `fa-ci:ark-7.4`, from `docker/ci/build-image.sh cp 7.4 fa-ci:ark-7.4` run in that worktree.
- Environment `bms-rehearsal` (`plugin-dev.sh --env bms-rehearsal`), default port 8300. graphql's dev environment keeps 8100.
- Modules come from the local checkouts under `REHEARSE_MODULES`, default `/home/cambell/src/sgw/frontaccounting/modules`: `sgw_sales`, `sgw_import`, `graphql`, activated in that order. The theme comes from `REHEARSE_THEMES/bootstrap`, default `/home/cambell/src/sgw/frontaccounting/themes`. The checkouts must be on the branches the release uses (`makefile.json` components) and have `vendor/` installed.
- Only the `0_` table prefix is supported. `rehearse check` reports the prefix the backup uses.
- Nothing here touches production. The live backup and live's `installed_extensions.php` are copies the user supplies.
- `core.fileMode=false`: record executable modes with `git update-index --chmod=+x`.
- Scratch dirs get their own names (`TMP_A=$(mktemp -d)`), never `HOME`.
- The machine thermally throttles, so run one docker build or suite at a time.
- Commit as `git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit ...` with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

- A backup whose sgw_sales schedules have duplicates: activation of `update_1.4.sql` fails. The environment must stay up, `check` must list the duplicates, and `plugin-dev.sh activate` must succeed once they're fixed. Test: Task 2, the duplicate-schedule run.
- Live users' access: a role on the backup that holds sgw_sales' area for extension 1 must still open sgw_sales' page after the rehearsal. Test: Task 2, "live's roles still reach sgw_sales".
- A module the live list doesn't have (graphql is new on live) must get an id after every live id, not one of theirs. Test: Task 2, "graphql gets an id after live's".
- Running `rehearse up` again must not reload the backup over a rehearsal in progress. Test: Task 2, "up again keeps the rehearsal".
- A missing backup or extensions file must be refused before anything starts. Test: Task 2, "a missing file is refused".

## Execution Schedule

| Wave | Tasks | Model | Notes |
|------|-------|-------|-------|
| 1 | Task 1 | sonnet | Merge master-cp and build the ark image. The package suite on the ark image proves the merge. |
| 2 | Task 2 | opus | Rewrite `rehearse` over `plugin-dev.sh`, with a simulated live backup test. |
| CP1 | — | — | plan base..end of wave 2: code-review medium + spec check (spec §7). |
| 3 | Controller | — | Push the branch (not master-ark). Update the runbook artifact's rehearsal steps. Hand the user the command to run with their real backup. |

---

### Task 1: master-ark takes master-cp, and an image of master-ark

**Files (merge-ark worktree):** the merge commit only, plus conflict resolutions if any.

**Interfaces:**
- Consumes: `origin/master-cp` with plan 3A merged (`docker/ci/plugin-dev.sh` present).
- Produces: branch `merge/master-cp-into-master-ark` containing `docker/ci` and plan 3A. Image `fa-ci:ark-7.4` of master-ark's code.

- [ ] **Step 1: Check the precondition**

Run: `git -C /home/cambell/src/sgw/frontaccounting/.claude/worktrees/merge-ark fetch -q origin && git -C /home/cambell/src/sgw/frontaccounting/.claude/worktrees/merge-ark show origin/master-cp:docker/ci/plugin-dev.sh | head -3`
Expected: the header of `plugin-dev.sh`. If it's missing, plan 3A isn't merged yet. Stop and report BLOCKED.

- [ ] **Step 2: Merge**

```bash
cd /home/cambell/src/sgw/frontaccounting/.claude/worktrees/merge-ark
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com merge --no-ff origin/master-cp \
  -m "Merge master-cp (the CI package and its dev environments) into master-ark" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Expected: a clean merge. master-ark hasn't touched `docker/ci`, `docs/superpowers` or `.github`. On a conflict, keep master-ark's settings (`makefile.json` variables, `upload-exclude.txt` ark lines, `DEVELOPERS.md`, `docker/upgrade/`) and master-cp's changes to everything else. List each resolution in the report, then `git commit`.

- [ ] **Step 3: Build the ark image and prove it with the package suite**

Run: `docker/ci/build-image.sh cp 7.4 fa-ci:ark-7.4 && FA_CI_IMAGE=fa-ci:ark-7.4 docker/ci/test/run.sh`
Expected: `all passed`. The image's label records the branch: `docker inspect -f '{{index .Config.Labels "io.frontaccounting.ref"}}' fa-ci:ark-7.4` prints `merge/master-cp-into-master-ark`.

If a package test fails because master-ark's own code differs from master-cp (its report or email changes), report the failing check verbatim with DONE_WITH_CONCERNS. Don't change the package from this branch.

---

### Task 2: `rehearse` over `plugin-dev.sh`

**Files (merge-ark worktree):**
- Modify: `docker/upgrade/rehearse` (whole file)
- Create: `docker/upgrade/test/rehearse.sh`
- Modify: `docker/upgrade/README.md` (the rehearsal section)

**Interfaces:**
- Consumes (Task 1): `fa-ci:ark-7.4` and `docker/ci/plugin-dev.sh` (`up --env --port --image --dataset <file> --extensions <file> --with --theme`, `exec`, `status`, `url`, `down`, `destroy --yes`, `activate`), plus the existing `docker/upgrade/00-preflight.sql` and `10-core-2.4.20.sql`.
- Produces:

```
docker/upgrade/rehearse up <backup.sql[.gz]> <installed_extensions.php> [--port N]
docker/upgrade/rehearse check | migrate | url | down | destroy
```

- [ ] **Step 1: Write the failing test**

`docker/upgrade/test/rehearse.sh`:

```bash
#!/usr/bin/env bash
#
# rehearse end to end on a simulated live site: FrontAccounting 2.4.3's schema
# (master-ark before the 2.4.20 merge), sgw_sales 1.0 schedules with one order
# scheduled twice, sgw_import's tables, and a live extension list where
# sgw_sales is 1 and sgw_import 2, whose role 2 holds sgw_sales' area.
#
#   docker/upgrade/test/rehearse.sh      (needs the image fa-ci:ark-7.4)

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
# shellcheck source-path=SCRIPTDIR source=../../ci/test/lib.sh
. "$root/docker/ci/test/lib.sh"

r="$here/../rehearse"
dev="$root/docker/ci/plugin-dev.sh"
TMP_A="$(mktemp -d)"
export XDG_CACHE_HOME="$TMP_A/cache"
export REHEARSE_ENV="rehearsetest$$"
port="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
trap '"$r" destroy >/dev/null 2>&1 || true; rm -rf "$TMP_A"' EXIT

# A 2.4.3 site: master-ark's own schema from before the 2.4.20 merge.
backup="$TMP_A/live.sql"
{
    git -C "$root" show bc7ef07d:sql/en_US-new.sql
    echo "SET SESSION sql_mode='';"
    cat "${REHEARSE_MODULES:-/home/cambell/src/sgw/frontaccounting/modules}/sgw_sales/sql/update_1.0.sql"
    echo "INSERT INTO \`0_sales_recurring\` (trans_no,dt_start,dt_end,dt_next,auto,every,repeats,occur) VALUES
      (720,'2024-01-01','0000-00-00','2026-10-01',1,1,'year','1'),
      (720,'2024-01-01','0000-00-00','2026-10-01',1,1,'year','1'),
      (721,'2024-02-01','2027-01-31','0000-00-00',1,1,'month','1');"
    sed -e '/^SET AUTOCOMMIT/d;/^START TRANSACTION/d;/^COMMIT/d' \
        "${REHEARSE_MODULES:-/home/cambell/src/sgw/frontaccounting/modules}/sgw_import/data/0.1.0.sql"
    # Live's admin role holds sgw_sales' section and its three areas as extension 1.
    echo "UPDATE \`0_security_roles\` SET sections = CONCAT(sections, ';91136'), areas = CONCAT(areas, ';91236;91237;91238') WHERE id = 2;"
} > "$backup"
cat > "$TMP_A/installed_extensions.php" <<'PHP'
<?php
$next_extension_id = 3;
$installed_extensions = array (
  1 => array ('package' => 'sgw_sales', 'name' => 'sgw_sales', 'version' => '-', 'available' => '', 'type' => 'extension', 'path' => 'modules/sgw_sales', 'active' => false),
  2 => array ('package' => 'sgw_import', 'name' => 'sgw_import', 'version' => '-', 'available' => '', 'type' => 'extension', 'path' => 'modules/sgw_import', 'active' => false),
);
PHP

expect_status 2 "a missing file is refused" "$r" up "$TMP_A/nope.sql" "$TMP_A/installed_extensions.php" --port "$port"
expect_status 0 "and nothing was created" sh -c "! docker inspect fa-dev-$REHEARSE_ENV >/dev/null 2>&1"

expect_status 1 "up stops at sgw_sales' 1.4 on the duplicate schedule" "$r" up "$backup" "$TMP_A/installed_extensions.php" --port "$port"
expect_contains "naming sgw_sales" "did not activate sgw_sales" "$OUT"
expect_status 0 "the environment stays for inspection" docker inspect "fa-dev-$REHEARSE_ENV"
expect_status 0 "check lists the duplicate" "$r" check
expect_contains "order 720" "720" "$OUT"
expect_contains "the prefix" "0_" "$OUT"

expect_status 0 "fix the duplicate by hand" "$dev" --env "$REHEARSE_ENV" exec \
    "mariadb -h localhost -u fa -pfa fa_test -e 'DELETE FROM 0_sales_recurring WHERE trans_no = 720 ORDER BY id DESC LIMIT 1'"
expect_status 0 "activate carries on" "$dev" --env "$REHEARSE_ENV" activate
expect_status 0 "migrate adds the core preferences" "$r" migrate
expect_status 0 "check after" "$r" check
expect_contains "7 of 7 preferences" "| 2.4.20 prefs already present (of 7) |      7 |" "$OUT"
expect_contains "dt_next nullable" "YES" "$OUT"

expect_status 0 "graphql gets an id after live's" "$dev" --env "$REHEARSE_ENV" exec \
    'for m in sgw_sales sgw_import graphql; do printf "%s=%s " "$m" "$(fa-ci-ext-id "$m")"; done'
expect_contains "sgw_sales keeps 1" "sgw_sales=1" "$OUT"
expect_contains "sgw_import keeps 2" "sgw_import=2" "$OUT"
expect_contains "graphql after them" "graphql=3" "$OUT"
expect_status 0 "live's roles still reach sgw_sales (admin, role 2, opens its order page)" sh -c "
    j=\$(mktemp); u=\$(\"$r\" url);
    curl -fsS -c \$j -b \$j -o /dev/null \${u}index.php &&
    curl -fsS -c \$j -b \$j -o /dev/null --data 'user_name_entry_field=admin&password=password&company_login_name=0' \${u}index.php &&
    p=\$(curl -fsS -b \$j \${u}modules/sgw_sales/inquiry/sales_orders_view.php) &&
    printf '%s' \"\$p\" | grep -qi logout && ! printf '%s' \"\$p\" | grep -qi 'security settings'"
expect_status 0 "up again keeps the rehearsal" "$r" up "$backup" "$TMP_A/installed_extensions.php" --port "$port"
expect_status 0 "the fix is still there" "$dev" --env "$REHEARSE_ENV" exec \
    "mariadb -h localhost -u fa -pfa -N fa_test -e 'SELECT COUNT(*) FROM 0_sales_recurring WHERE trans_no = 720'"
expect_contains "one schedule" "1" "$OUT"
expect_status 0 "destroy" "$r" destroy
finish
```

Run: `chmod +x docker/upgrade/test/rehearse.sh`.

The admin login in the test uses `admin`/`password`, which master-ark's `en_US-new.sql` sets for `admin` (MD5 of `password`). If it doesn't, sign in as `test`/`test` instead: the dataset adds that user on role 2, so the check still exercises role 2's grants. Say which one you used in the report.

- [ ] **Step 2: Run it to verify it fails**

Run: `docker/upgrade/test/rehearse.sh`
Expected: it FAILs from "a missing file is refused", because the current `rehearse` has no `up` command.

- [ ] **Step 3: Rewrite `rehearse`**

`docker/upgrade/rehearse` (whole file):

```bash
#!/usr/bin/env bash
#
# Rehearse the 2.4.3 (master-ark) -> 2.4.20 upgrade of the live site on a copy
# of its database, in a development environment of the FA CI package
# (docker/ci/plugin-dev.sh) running master-ark's own code. See README.md here.
#
#   docker/upgrade/rehearse up <backup.sql[.gz]> <installed_extensions.php> [--port N]
#   docker/upgrade/rehearse check     read-only report (before and after)
#   docker/upgrade/rehearse migrate   the core preferences (the modules' SQL runs at activation)
#   docker/upgrade/rehearse url | down | destroy
#
# up builds the image fa-ci:ark-7.4 from this checkout if it isn't there, then
# creates the environment (REHEARSE_ENV, default bms-rehearsal) from the backup,
# with live's extension ids, and activates sgw_sales, sgw_import and graphql
# from the checkouts under REHEARSE_MODULES and the bootstrap theme from
# REHEARSE_THEMES. Activation runs each module's upgrade SQL through FA, as
# the real upgrade will; if one fails, the environment stays up: `check`, fix,
# then `docker/ci/plugin-dev.sh --env <env> activate`.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
dev="$root/docker/ci/plugin-dev.sh"
ENV_NAME="${REHEARSE_ENV:-bms-rehearsal}"
MODULES="${REHEARSE_MODULES:-/home/cambell/src/sgw/frontaccounting/modules}"
THEMES="${REHEARSE_THEMES:-/home/cambell/src/sgw/frontaccounting/themes}"
IMAGE="${REHEARSE_IMAGE:-fa-ci:ark-7.4}"

die() { printf 'rehearse: %s\n' "$*" >&2; exit 1; }
# sql <file>: run a SQL file against the environment's database. plugin-dev.sh
# exec does not pass stdin through, so the file goes into the container first.
sql() {
    docker cp "$1" "fa-dev-$ENV_NAME:/tmp/rehearse.sql"
    "$dev" --env "$ENV_NAME" exec "mariadb -h localhost -u fa -pfa -t fa_test < /tmp/rehearse.sql"
}

cmd_up() {
    [ "$#" -ge 2 ] || die "usage: rehearse up <backup.sql[.gz]> <installed_extensions.php> [--port N]"
    local backup="$1" extensions="$2" port=8300
    shift 2
    if [ "${1:-}" = --port ]; then port="$2"; fi
    [ -f "$backup" ] || { printf 'rehearse: no such backup: %s\n' "$backup" >&2; exit 2; }
    [ -f "$extensions" ] || { printf 'rehearse: no such file: %s\n' "$extensions" >&2; exit 2; }
    local m
    for m in sgw_sales sgw_import graphql; do
        [ -f "$MODULES/$m/hooks.php" ] || die "no $m checkout in $MODULES (set REHEARSE_MODULES)"
        [ -d "$MODULES/$m/vendor" ] || die "$MODULES/$m has no vendor/: run composer install --no-dev there"
    done
    [ -d "$THEMES/bootstrap" ] || die "no bootstrap theme in $THEMES (set REHEARSE_THEMES)"
    docker image inspect "$IMAGE" >/dev/null 2>&1 \
        || "$root/docker/ci/build-image.sh" cp 7.4 "$IMAGE"
    "$dev" --env "$ENV_NAME" up --port "$port" --image "$IMAGE" \
        --dataset "$backup" --extensions "$extensions" \
        --with "sgw_sales=$MODULES/sgw_sales" --with "sgw_import=$MODULES/sgw_import" \
        --with "graphql=$MODULES/graphql" --theme "bootstrap=$THEMES/bootstrap"
}

cmd_check() {
    echo "== pre-flight"
    sql "$here/00-preflight.sql"
    echo "== table prefixes in the backup (only 0_ is supported)"
    "$dev" --env "$ENV_NAME" exec "mariadb -h localhost -u fa -pfa -N fa_test -e \"SELECT table_name FROM information_schema.tables WHERE table_schema = 'fa_test' AND table_name LIKE '%users'\""
    echo "== orders with more than one sgw_sales schedule (must be none for sgw_sales 1.4)"
    "$dev" --env "$ENV_NAME" exec "mariadb -h localhost -u fa -pfa -t fa_test -e \"SELECT trans_no, COUNT(*) AS schedules FROM 0_sales_recurring GROUP BY trans_no HAVING schedules > 1\"" || true
}

cmd_migrate() {
    echo "== core: 2.4.20 company preferences"
    sql "$here/10-core-2.4.20.sql"
    echo "== migrated (the modules' SQL ran when they were activated)"
}

cmd="${1:-help}"
shift || true
case "$cmd" in
    up) cmd_up "$@" ;;
    check) cmd_check ;;
    migrate) cmd_migrate ;;
    url) "$dev" --env "$ENV_NAME" url ;;
    down) "$dev" --env "$ENV_NAME" down ;;
    destroy) "$dev" --env "$ENV_NAME" destroy --yes ;;
    *) sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
esac
```

- [ ] **Step 4: Run the test**

Run: `docker/upgrade/test/rehearse.sh`
Expected: `0 failed`. `rehearse destroy` leaves no `fa-dev-rehearsetest*` container or volume.

- [ ] **Step 5: README**

In `docker/upgrade/README.md`, replace the "## Rehearsal" section with:

````markdown
## Rehearsal

On a copy of live, in a development environment of the FA CI package running
this branch's code (`docker/ci/plugin-dev.sh`). You need two files from live:
a database backup and live's `installed_extensions.php`. The second keeps the
modules' extension ids, which live's security roles were built with.

    docker/upgrade/rehearse up ~/backups/saygoweb_fa.sql.gz ~/backups/installed_extensions.php
    docker/upgrade/rehearse check      # before
    docker/upgrade/rehearse migrate
    docker/upgrade/rehearse check      # after: 7 of 7 preferences, dt_next nullable

`up` builds the image `fa-ci:ark-7.4` from this checkout if it isn't there,
then loads the backup and activates sgw_sales, sgw_import and graphql, as the
real upgrade will. Their upgrade SQL runs through FrontAccounting. The modules
come from `/home/cambell/src/sgw/frontaccounting/modules/*` (`REHEARSE_MODULES`)
and the bootstrap theme from `themes/bootstrap` (`REHEARSE_THEMES`). They must
be on the branches the release uses and have `vendor/` installed.

If an activation fails, e.g. sgw_sales 1.4 on an order with two schedules,
the environment stays up:

    docker/upgrade/rehearse check      # shows the cause
    docker/ci/plugin-dev.sh --env bms-rehearsal exec "mariadb -h localhost -u fa -pfa fa_test -e '...'"
    docker/ci/plugin-dev.sh --env bms-rehearsal activate

Then browse `docker/upgrade/rehearse url` (port 8300), signing in as your own
users. Mail is caught, never sent (`plugin-dev.sh --env bms-rehearsal mail list`).
`rehearse down` stops it and `rehearse destroy` removes it.
````

Also remove the old text about `docker/fa up` and `docker/fa db reset` from the rest of the file.

- [ ] **Step 6: Commit**

```bash
git add docker/upgrade
git update-index --chmod=+x docker/upgrade/rehearse docker/upgrade/test/rehearse.sh
git -c user.name=Cambell -c user.email=cambell.prince@gmail.com commit -m "docker/upgrade: Rehearse in a dev environment of master-ark's code

rehearse up loads the live backup into a plugin-dev.sh environment built
from this branch, with live's extension ids, and activates sgw_sales,
sgw_import and graphql as the real upgrade will; a failed activation leaves
it up to inspect and retry. Tested on a simulated 2.4.3 site with a
duplicate schedule.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Wave 3 (controller)

- [ ] Push `merge/master-cp-into-master-ark` (the branch only, never master-ark).
- [ ] Update the runbook artifact (https://claude.ai/artifact/2CA7YreiLywTAQDh4bVVh3, republished by URL): step 1.2's rehearsal commands become the `rehearse up <backup> <installed_extensions.php>` sequence above. It needs live's `installed_extensions.php` from `/var/www/virtual/saygoweb.com/bms/htdocs/`, fetched read-only with `scp`.
- [ ] Tell the user the two files to fetch from live and the one command to run. The rehearsal on real data is theirs to start.
