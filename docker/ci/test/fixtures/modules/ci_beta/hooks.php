<?php
/* Test fixture for docker/ci: stands in for a plugin that needs another one.
   Its activation fails unless ci_alpha's table is already there. */
class hooks_ci_beta extends hooks
{
	var $module_name = 'ci_beta';

	function activate_extension($company, $check_only = true)
	{
		global $db_connections;

		if (check_table($db_connections[$company]['tbpref'], 'ci_alpha') != 0)
			return false;
		return $this->update_databases($company, array('update_1.0.sql' => array('ci_beta')), $check_only);
	}
}
