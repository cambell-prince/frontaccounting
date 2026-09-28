<?php
/* Test fixture for docker/ci: a module whose activation creates a table, and
   which declares two security areas (the second in a core section). */
define('SS_CI_ALPHA', 111 << 8);

class hooks_ci_alpha extends hooks
{
	var $module_name = 'ci_alpha';

	function install_access()
	{
		$security_sections[SS_CI_ALPHA] = 'CI alpha';
		$security_areas['SA_CI_ALPHA'] = array(SS_CI_ALPHA | 1, 'CI alpha area');
		// A second area, in a CORE section (SS_SALES, 12<<8) rather than one
		// of this module's own $security_sections entries: proves grant.php
		// grants the section for an extension area left in a core section
		// (docker/ci/image/grant.php).
		$security_areas['SA_CI_ALPHA_SALES'] = array(SS_SALES | 71, 'CI alpha area in the sales section');
		return array($security_areas, $security_sections);
	}

	function activate_extension($company, $check_only = true)
	{
		return $this->update_databases($company, array('update_1.0.sql' => array('ci_alpha')), $check_only);
	}
}
