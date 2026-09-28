<?php
/*
	CI image only (docker/ci), not part of FrontAccounting. Gives the System
	Administrator role (id 2) every security section and area known in this
	request, extension ones included. Extension codes depend on each module's
	extension id and are only worked out during a request
	(add_access_extensions()), which is why this runs as a page.
*/
$page_security = 'SA_SECROLES';
$path_to_root = '..';
include_once($path_to_root . '/includes/session.inc');
include_once($path_to_root . '/admin/db/security_db.inc');

add_access_extensions();

$role = get_security_role(2);
$sections = array_keys($security_sections);
$areas = array();
foreach ($security_areas as $area)
	$areas[] = $area[0];
update_security_role(2, $role['role'], $role['description'], $sections, $areas);

header('Content-Type: text/plain');
echo 'granted ', count($areas), ' areas in ', count($sections), " sections\n";
