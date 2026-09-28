<?php
/*
	FrontAccounting CI image (docker/ci). The database is in this container,
	seeded from modules/tests/data/fa_test.sql.gz when the image was built.
*/
$def_coy = 0;
$tb_pref_counter = 1;
$db_connections = array (
  0 =>
  array (
    'name' => 'FA CI',
    'host' => 'localhost',
    'dbuser' => 'fa',
    'dbpassword' => 'fa',
    'dbname' => 'fa_test',
    'tbpref' => '0_',
  ),
);
