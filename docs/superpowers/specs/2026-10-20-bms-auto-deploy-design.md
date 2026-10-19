# Automatic deploys of bms.saygoweb.com: design

Status: agreed in conversation on 2026-10-20 (sections 1-5 approved one by one).
Server-side rollout steps: the "bms Server Rollout" runbook
(https://claude.ai/artifact/YYT4uooYtu5mCSoxByxRWz).

## Purpose

bms.saygoweb.com runs FrontAccounting `master-ark` with the graphql, mcp,
sgw_sales and sgw_import extensions. Today it is updated by a scripted sync
from a local working copy, so what is live is whatever that checkout held,
including uncommitted files.

After this work, GitHub deploys it. A push to `master-ark`, or to the deploy
branch of any of the four extensions, deploys once that repository's CI is
green, with no one at a keyboard.

Success looks like this:

- A green push to any of the five repositories reaches the server without
  manual steps, normally within a few minutes of CI finishing.
- Nothing that has not passed CI is deployed, including another repository's
  head that is still being tested.
- `~/bms/htdocs/.deploy-manifest` on the server names every commit that is
  live.
- The server's own configuration, company data and uploads survive every
  deploy.

## Scope

In scope:

- The deploy workflow, its helper scripts and the changes to `deploy/`.
- An `ark` flavour of the CI image, built on pushes to `master-ark`.
- A `notify-deploy.yml` workflow in each extension repository.
- The server preparation, which the runbook covers step by step.

Out of scope:

- Database migrations. They stay manual, but a deploy warns when one is due
  (§5).
- The bootstrap theme, which bms does not use.
- Sites other than bms.
- Atomic or blue/green release switching.

Prerequisite: `merge/master-cp-into-master-ark` is merged into `master-ark`.
That merge brings `deploy/`, `makefile.json`, `upload-exclude.txt` and
`.github/` to the branch.

## §1 The components

| path | repository | deploy branch | CI workflow |
| --- | --- | --- | --- |
| (root) | cambell-prince/frontaccounting | `master-ark` | `ci-image.yml` |
| `modules/graphql` | saygoweb/frontaccounting-module-graphql | `main` | `ci.yml` |
| `modules/mcp` | saygoweb/frontaccounting-module-mcp | `main` | `ci.yml` |
| `modules/sgw_sales` | saygoweb/frontaccounting-module-sgw_sales | `master` | `ci.yml` |
| `modules/sgw_import` | saygoweb/frontaccounting-module-sgw_import | `master` | `ci.yml` |

All five repositories are public. Clones use `https://` URLs, so neither the
runner nor a workstation needs a GitHub SSH key to build a release.

The extension rows are `components` in `master-ark`'s `makefile.json`. They
use the existing `path|repo|ref[|composer]` form, with the deploy branch as
`ref`. This file is the only place the list lives: the workflow reads it and
does not repeat it.

## §2 Flow

```
push master-ark ──▶ CI image (ark × PHP 7.4/8.3) ──green──┐
                                                          ├──▶ deploy-bms.yml
extension push ──▶ extension CI ──green──▶ dispatch ──────┤    (one at a time, queued)
                                                          │
manual run (dry_run, ref overrides, max_deletes) ─────────┘
```

`deploy-bms.yml` lives on `master-cp`, the repository's default branch.
GitHub only runs `workflow_run` and `repository_dispatch` workflows from the
default branch. The workflow checks out `master-ark` to build.

Triggers:

- `workflow_run` of "CI image", completed with success on `master-ark`.
- `repository_dispatch` of type `extension-green`, with payload
  `{component, sha, run_url}`. The payload is logged and otherwise ignored
  (§4).
- `workflow_dispatch`, with these inputs:
  - `dry_run` (boolean, default `true`)
  - `refs` (optional overrides, `path=sha` separated by spaces)
  - `max_deletes` (default 25)

Automatic triggers run with `max_deletes` at 25, and go live only when the
`bms` environment variable `DEPLOY_LIVE` is `true`. Until then they stop after
the check, like a dry run. bms and `master-ark` are both on FrontAccounting
2.4.3, and the 2.4.20 upgrade needs database migrations done by hand. So
`DEPLOY_LIVE` is set only after that upgrade is live, and no automatic run can
ship 2.4.20 code to a 2.4.3 database. A manual run goes live whenever
`dry_run` is off.

`concurrency: {group: deploy-bms, cancel-in-progress: false}`. GitHub keeps one
pending run behind the running one and replaces older pending runs. That is
correct here: every run re-resolves from scratch, so the newest pending run
covers everything the replaced ones would have shipped.

The job runs in the `bms` environment, with `permissions: {contents: read,
actions: read}`. It runs these steps:

1. **Resolve.** `deploy/resolve-refs.sh` (§3) prints `ref=<sha>` and a
   `components` string with every ref pinned to a SHA. `refs` overrides
   replace the matching entries.
2. **Build.** `deploy/build-release.sh`, with `php` and `components` read
   from `master-ark`'s `makefile.json` with `jq`. The workflow calls the
   scripts that make.phar's targets wrap, because `saygoweb/phpmake` publishes
   no release to install on a runner.
3. **Check.** `deploy/upload.sh check`, with `host`, `user` and `path` set.
   The step fails if more than `max_deletes` files would be deleted, which
   catches a broken release (an empty extension, say) before it can wipe the
   server. It also runs the migration check in §5.
4. **Deploy** (skipped on a dry run, and on an automatic run until
   `DEPLOY_LIVE` is `true`). `deploy/upload.sh go`.
5. **Report.** The manifest, the deletion list and any migration warnings go
   to the job summary. The manifest is also uploaded as an artifact.

## §3 Resolving what to deploy (`deploy/resolve-refs.sh`)

The job deploys each component at its newest commit whose CI passed, never at
its branch head. Otherwise a deploy started by one repository could ship
another repository's head while that head is still under test.

- **Extensions:** take the `head_sha` of the newest run of `ci.yml` on the
  deploy branch, filtered to `event=push` and `status=success`, through
  `gh api repos/<repo>/actions/workflows/ci.yml/runs`. A run only succeeds
  when every matrix leg passed.
- **FrontAccounting:** `ci-image.yml` only runs for changes under its `paths`
  filter, so a docs-only push to `master-ark` never gets a run of its own.
  1. Take G, the `head_sha` of the newest successful `ci-image.yml` push run
     on `master-ark`, and H, the head of `master-ark`.
  2. If `git diff --name-only G H` touches none of those paths, deploy H.
  3. Otherwise deploy G, with a notice in the summary. The run for H is either
     in progress, and will trigger its own deploy when it finishes, or it
     failed.

  The script reads the list under `paths: &image-paths` in `ci-image.yml`
  with `awk`, so the list isn't duplicated. It matches with bash patterns,
  where `*` also matches `/`. That can treat a change as touching the image
  when GitHub wouldn't, and then the script picks G. It never wrongly picks
  H.
- **No green run at all** for a component fails the job, naming the
  component.

The output is a `components` string in the makefile's own format, with each
`ref` replaced by a SHA. The script works the same from a workstation with
`gh` signed in.

## §4 Changes, repository by repository

### cambell-prince/frontaccounting

`deploy/build-release.sh`:

- A component `ref` of 40 hex digits is fetched as a commit:
  `git init`, `git fetch --depth 1 origin <sha>`, `git checkout FETCH_HEAD`.
  Branch and tag refs keep using `git clone --depth 1 --branch`.
- The manifest records full SHAs.
- The manifest is also written into the release as `.deploy-manifest`, so
  every deploy, from GitHub or by hand, records itself on the server. Because
  it is part of the release, `--delete` never removes it and it needs no
  exclude rule.

`deploy/upload.sh` and `makefile.json`:

- `dest` is replaced by three variables: `user`, `host` and `path`.
  `path` defaults to `bms/htdocs/` on `master-ark`.
- The makefile passes all three to `upload.sh`, which builds
  `<user>@<host>:<path>` and refuses to run if any of them is empty.
- `remote_user` stays, for sites that `sudo -u`. bms leaves it empty.
- `deploy-check` additionally writes the deletion count and list where the
  workflow can read them.
- A `previous` mode fetches the server's `.deploy-manifest` (for §5).

`makefile.json` on `master-ark`:

- `host` is `aws1.saygoweb.com`. `user` is empty, so it must be set on the
  command line or in the workflow.
- `components` lists the four extensions from §1 with `https://` URLs. mcp is
  added and the theme removed.
- `php` stays 7.4.33 unless the runbook's inventory finds bms on another PHP.

`upload-exclude.txt`:

- Adds `/modules/mcp/config_mcp.php`. Without this line, the first deploy
  would delete the server's MCP config.

CI image:

- `docker/ci/build-image.sh` accepts an `ark` flavour. It builds from the
  checkout like `cp` and tags `ark-php<v>` and `ark-php<v>-<sha7>`.
- `ci-image.yml` runs on pushes to `master-ark`. On that branch the matrix is
  `[ark] × [7.4, 8.3]`, and on `master-cp` it stays `[cp, upstream] × [7.4, 8.3]`.
- `docker/ci/prune-images.sh` keeps `ark-*` tags as it keeps `cp-*` tags.

New files:

- `deploy/resolve-refs.sh` (§3).
- `.github/workflows/deploy-bms.yml` on `master-cp` (§2).

### The four extension repositories

Each gains `.github/workflows/notify-deploy.yml`:

- It runs on `workflow_run` of `CI` completing on the deploy branch, and only
  when that run succeeded on a push.
- It is a separate workflow, not a job inside `ci.yml`. A job inside `ci.yml`
  would dispatch while its own run was still in progress, so resolve would
  not yet count that commit as green and would deploy the previous one. A
  failed dispatch also leaves the CI result alone.
- It runs `gh api repos/cambell-prince/frontaccounting/dispatches` with
  `event_type: extension-green` and `client_payload: {component, sha, run_url}`,
  using `secrets.FA_DEPLOY_DISPATCH`.
- If the secret isn't set, it says so and succeeds.

Optionally, each extension's test matrix adds `fa: ark`, so the extension is
also tested against the FrontAccounting that gets deployed with it. Doing
that also makes `plugin-test.yml` accept `ark`.

### Secrets and settings

| name | where | holds |
| --- | --- | --- |
| `FA_DEPLOY_DISPATCH` | saygoweb organisation secret, visible to the four extension repositories | Fine-grained PAT of cambell-prince, access to `cambell-prince/frontaccounting` only, Contents read/write (the minimum for `repository_dispatch`). Rotated before it expires. |
| `BMS_SSH_KEY` | `bms` environment secret | Private half of the dedicated ed25519 deploy key |
| `BMS_KNOWN_HOSTS` | `bms` environment secret | aws1's ed25519 host key, pinned after comparing fingerprints |
| `DEPLOY_LIVE` | `bms` environment variable | `true` lets automatic runs deploy. Unset until the 2.4.20 upgrade is live. |
| `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_PATH` | `bms` environment variables | Passed as `host=`, `user=` and `path=`, so CI deploys to `<user>@<host>:<path>`. Named so they don't clobber the runner's `$USER`. `DEPLOY_PATH` is `/` because rrsync roots the key at the site directory (see "The server" below). |

The `bms` environment only allows deployments from `master-cp`, so workflows on
other branches and pull requests cannot read the key.

### The server

The runbook covers the details. In summary:

- The deploy key goes into the site user's `authorized_keys` as
  `restrict,command="/usr/bin/rrsync <absolute path of ~/bms/htdocs>"`.
  - It has no shell or forwarding and cannot reach anything outside the site
    directory.
  - It has no `-no-del`, so deploys can remove stale files.
  - rrsync resolves every client path relative to that directory, so
    `DEPLOY_PATH` is `/`. A value of `bms/htdocs/` would write to
    `~/bms/htdocs/bms/htdocs/`. The site directory is fixed on the server in
    `authorized_keys`, not in GitHub. Deploys from a workstation use your own,
    unrestricted key and keep `path=bms/htdocs/`.
  - Jailing at the home directory instead, so the path could read
    `bms/htdocs/`, was rejected: the key could then overwrite
    `~/.ssh/authorized_keys` and lift its own restriction.
- SSH is open to the internet. Key-only authentication plus rrsync is the
  protection, and the runbook confirms password login is off.
- The dispatch token can only start a deploy, never choose what is deployed:
  resolution ignores the payload. A forged dispatch can at most redeploy the
  current green set.

## §5 Failures, rollback and visibility

| fails at | server | what you see |
| --- | --- | --- |
| a repository's CI | untouched; nothing is dispatched or triggered | the CI failure, as today |
| resolve | untouched | failed run naming the component |
| build (clone, composer) | untouched; no `.ok`, so upload refuses | failed run with the build log |
| delete guard | untouched | failed run listing the files. Re-run by hand with a higher `max_deletes` if the deletions are intended. |
| rsync, part way | mixed tree. Each file is replaced atomically, the set is not. | failed run. Re-running converges. |

- **Migration warning.** Before deploying, the job fetches the previous
  `.deploy-manifest` from the server. For each component whose SHA changed,
  it asks the GitHub compare API whether files under `sql/` changed. If any
  did, the summary warns that a migration may be due. The deploy still goes
  ahead. On the first deploy there is no previous manifest, so the job skips
  this check and says so.
- **Rollback.** Revert the bad commit. Its CI goes green and deploys the
  revert. For an immediate fix, run the workflow by hand with `refs`
  overrides. An override applies to that run only.
- **Notification.**
  - Failed runs notify through GitHub's Actions emails. The rollout includes
    one deliberate failure to confirm the email arrives.
  - Successful runs write the manifest to the job summary, and
    `.deploy-manifest` on the server is the record of what is live.
- **opcache.** Deploys assume PHP revalidates file timestamps. If the runbook
  finds `opcache.validate_timestamps=0`, a php-fpm reload is needed after each
  deploy, and that needs a design change because the rrsync key cannot do it.

## §6 Testing and rollout

1. `build-release.sh`: build locally with one component pinned to a SHA and
   one on a branch. Check the tree and both manifests.
2. `resolve-refs.sh`: run it locally against the real repositories, plus
   these cases:
   - an extension whose head is red resolves to its previous green commit;
   - a docs-only `master-ark` head is taken;
   - a component with no green run fails.
3. After the merge lands on `master-ark`: the `ark` images build, pass the
   smoke test and push, and the prune keeps them.
4. Server preparation, runbook phases 1-7: inventory, backups, the deploy
   key, the pinned host key and the exclude fix.
5. `deploy-bms.yml` by hand with `dry_run=true`. The deletion list must contain
   only leftovers from the manual syncs.
6. The first live deploy by hand while watching, then the runbook's server and
   browser checks.
7. bms is upgraded to 2.4.20 by its own runbook, and `master-ark` takes
   the merge. Then `DEPLOY_LIVE` is set to `true`.
8. `notify-deploy.yml` merged into the extensions one at a time. A trivial push to
   one of them must reach the server on its own.
9. The manual sync is retired. `deploy/README.md` gains a section on the
   GitHub deploy and the bms environment. `make.phar deploy` from a
   workstation stays available for emergencies.
