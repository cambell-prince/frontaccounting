<?php
/* Test fixture for docker/ci: a module whose update SQL fails, so its
   activation does. */
class hooks_ci_broken extends hooks
{
	var $module_name = 'ci_broken';

	function activate_extension($company, $check_only = true)
	{
		return $this->update_databases($company, array('update_1.0.sql' => array('ci_broken')), $check_only);
	}
}
