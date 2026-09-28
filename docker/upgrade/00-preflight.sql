-- Read-only checks to run against the restored backup before migrating.
-- Table prefix: written for '0_'; `rehearse` rewrites it for another company.

SELECT 'FA database version (expect 2.4.1)' AS `check`, value AS result
  FROM `0_sys_prefs` WHERE name = 'version_id';

SELECT '2.4.20 prefs already present (of 7)' AS `check`, COUNT(*) AS result
  FROM `0_sys_prefs`
 WHERE name IN ('barcodes_on_stock', 'ref_no_auto_increase', 'print_dialog_direct',
                'dim_on_recurrent_invoice', 'long_description_invoice',
                'max_days_in_docs', 'company_logo_on_views');

SELECT 'Extension tables present' AS `check`,
       IFNULL(GROUP_CONCAT(table_name ORDER BY table_name), '(none)') AS result
  FROM information_schema.tables
 WHERE table_schema = DATABASE()
   AND table_name IN ('0_sales_recurring', '0_graphql_refresh_token', '0_graphql_machine_token',
                      '0_import_file', '0_import_file_type', '0_import_line');

-- sgw_sales update_1.4.sql makes 0_sales_recurring.trans_no UNIQUE and fails
-- if an order has more than one schedule. Any rows listed here must be
-- resolved by hand first (see modules/sgw_sales/sql/helpers/update_1.4-duplicates.sql).
SELECT 'sgw_sales 1.4 applied (dt_next nullable)' AS `check`, IFNULL(MAX(is_nullable), '(no table)') AS result
  FROM information_schema.columns
 WHERE table_schema = DATABASE() AND table_name = '0_sales_recurring' AND column_name = 'dt_next';
