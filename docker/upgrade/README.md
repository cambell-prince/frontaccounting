# Upgrading live: master-ark 2.4.3 → 2.4.20

Everything needed to rehearse the upgrade on a copy of the live database, and
then do it for real. `docker/` is in `upload-exclude.txt`, so none of this is
deployed.

## What changes in the database

**FrontAccounting core: no schema change.** 2.4.3 and 2.4.20 both declare
`$db_version = "2.4.1"`, and loading each version's `sql/en_US-new.sql` gives
the same tables and columns. Setup → Upgrade Company will show the company as
current and run nothing.

2.4.20 does add seven company preferences to `sys_prefs`: `barcodes_on_stock`,
`ref_no_auto_increase`, `print_dialog_direct`, `dim_on_recurrent_invoice`,
`long_description_invoice`, `max_days_in_docs` and `company_logo_on_views`. The
code treats a missing one as off (or 180 days for `max_days_in_docs`), and
Setup → Company Setup inserts any that are missing when it is opened.
`10-core-2.4.20.sql` inserts them up front with the stock defaults, so nothing
depends on someone opening that page.

**Extensions:**

| module | tables | from | notes |
| --- | --- | --- | --- |
| sgw_sales | `sales_recurring` | `update_1.0.sql`, `update_1.4.sql` | 1.4 makes `dt_end`/`dt_next` nullable, turns `0000-00-00` into `NULL`, and makes `trans_no` **unique**. It fails if an order has two schedules, so `rehearse check` lists them first. |
| graphql | `graphql_refresh_token`, `graphql_machine_token` | `update_1.0.sql`, `update_1.1.sql` | new tables |
| sgw_import | `import_file`, `import_file_type`, `import_line` | `data/0.1.0.sql` | no change; activation does not create them, so they should already exist on live |

In production these are applied by Setup → Install/Activate Extensions →
(company) → activate, which runs each module's `activate_extension()`.
`rehearse migrate` runs the same files with the same checks, so the rehearsal
can be scripted.

## Code that has to go with it

- **sgw_import `fix/anorm3`.** FrontAccounting loads every extension's hooks
  in one process, and with graphql installed all of them get Anorm 3.2.1.
  sgw_import `master` (on Anorm ^1.6) declares a static `delete($id)` that
  Anorm 3.2 forbids. Every sgw_import page then dies part-way through, with a
  fatal error in the Apache log and nothing on screen. The branch renames the
  method and requires `^3.2.1`.
- **Each module's `vendor/`**: run `composer install --no-dev` in `graphql`,
  `sgw_sales` and `sgw_import` before `gulp upload`, which rsyncs the tree with
  `--delete`.
- **graphql**: `modules/graphql/config_graphql.php` with a production secret
  (see `config_graphql.example.php`). Don't use the test stack's file, which
  has `allow_insecure_login` and `debug` on.
- **Access**: after activation, give the relevant roles the new areas under
  Setup → Access Setup (SayGo Import, GraphQL, and sgw_sales).

## Rehearsal

From the checkout root, with the stack up (`docker/fa up`):

    docker/upgrade/rehearse load ~/backups/live.sql.gz   # replaces the stack's database
    docker/upgrade/rehearse check                        # read-only report
    docker/upgrade/rehearse migrate                      # idempotent
    docker/upgrade/rehearse check

or `docker/upgrade/rehearse all ~/backups/live.sql.gz`. `PREFIX=1_` targets
another company's tables. `check` should end with 7 of 7 preferences, the
extension tables present, and `dt_next` nullable.

Then point the app at the data and click through it. `installed_extensions.php`
and `company/<n>/installed_extensions.php` have to list the modules that live
has. Things worth checking:

- Sign in as a live user. Look at a customer, and at the invoice and statement
  PDFs: the ark header layout and "TAX INVOICE" title.
- Email an invoice to yourself. This exercises the merged `pdf_report.inc`: the
  ark wording, with 2.4.20's `email::to($name, $mail)`.
- sgw_sales: open a recurring order, and run `generate_recurring_invoices.php`.
- sgw_import: list the files and open one.
- graphql: log in, and issue a machine token.
- `tmp/errors.log` stays empty.

`docker/fa db reset` puts the test fixture back afterwards, so `docker/fa test`
can run again.

## The real upgrade

1. Back up the database and the web root.
2. Pre-flight: run `00-preflight.sql` against live, and fix any duplicate
   sgw_sales schedules.
3. Deploy the merged `master-ark` plus the modules (with vendor/ and
   `config_graphql.php`).
4. Run `10-core-2.4.20.sql`, or open Company Setup and save it.
5. Install/Activate Extensions: activate graphql (and re-activate sgw_sales)
   for each company.
6. Set up role access, then work through the smoke checks above.
