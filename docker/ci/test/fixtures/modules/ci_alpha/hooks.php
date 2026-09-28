<?php
/* Test fixture for docker/ci: a module whose activation creates a table, and
   which declares one security area. */
define('SS_CI_ALPHA', 111 << 8);

class hooks_ci_alpha extends hooks
{
	var $module_name = 'ci_alpha';

	function install_access()
	{
		$security_sections[SS_CI_ALPHA] = 'CI alpha';
		$security_areas['SA_CI_ALPHA'] = array(SS_CI_ALPHA | 1, 'CI alpha area');
		return array($security_areas, $security_sections);
	}

	function activate_extension($company, $check_only = true)
	{
		return $this->update_databases($company, array('update_1.0.sql' => array('ci_alpha')), $check_only);
	}
}
