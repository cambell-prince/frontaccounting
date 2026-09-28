-- FrontAccounting 2.4.3 -> 2.4.20: core database changes. Idempotent.
--
-- The schema is unchanged between 2.4.3 and 2.4.20: both declare
-- $db_version = "2.4.1", so Setup -> Upgrade Company shows the company as
-- current and runs nothing. What 2.4.20 adds is seven company preferences.
-- The code reads each with !empty() (so a missing row means "off") and
-- Setup -> Company Setup inserts any that are missing the first time it is
-- opened, so this script is optional; it just makes the upgrade explicit
-- rather than depending on someone opening that page. Values are
-- sql/en_US-new.sql's defaults.
--
-- Table prefix: written for '0_'; `rehearse` rewrites it for another company.

INSERT IGNORE INTO `0_sys_prefs` (`name`, `category`, `type`, `length`, `value`) VALUES
('barcodes_on_stock',        'setup.company', 'tinyint',  1, '0'),   -- 2.4.3
('ref_no_auto_increase',     'setup.company', 'tinyint',  1, '0'),   -- 2.4.4
('print_dialog_direct',      'setup.company', 'tinyint',  1, '0'),   -- 2.4.5
('dim_on_recurrent_invoice', 'setup.company', 'tinyint',  1, '0'),
('long_description_invoice', 'setup.company', 'tinyint',  1, '0'),
('max_days_in_docs',         'setup.company', 'smallint', 5, '180'),
('company_logo_on_views',    'setup.company', 'tinyint',  1, '0');
