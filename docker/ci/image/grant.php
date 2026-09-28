<?php
/*
	CI image only (docker/ci), not part of FrontAccounting. Requested by
	fa-ci-grant. Extension security codes depend on each module's extension id
	and are only worked out during a request (add_access_extensions()), which is
	why this runs as a page.

	  (no query)            every section and area, to role "FA CI", which the
	                        test user is moved to; role 2 is left alone
	  ?role=N&module=NAME   that module's sections and areas, added to role N

	An area only takes effect once its section is granted too:
	includes/current_user.inc keeps only areas whose `$code & ~0xff` is in
	the role's sections. For an area an extension places in a CORE section
	(section byte < 99<<8), add_access_extensions() leaves that section
	untranslated (it's not one of the extension's own $security_sections
	entries), so it never turns up in $security_sections' own keys and a
	scan of those alone misses it. FA's own role editor
	(admin/security_roles.php) handles this by deriving the section from
	each granted area instead of only from $security_sections:
	`if (($a&~0xffff) && (($a&0xff00)<(99<<8))) $sections[] = $a&~0xff;`
	Both grant modes below do the same for every area they grant.
*/
$page_security = 'SA_SECROLES';
$path_to_root = '..';
include_once($path_to_root . '/includes/session.inc');
include_once($path_to_root . '/admin/db/security_db.inc');

add_access_extensions();
header('Content-Type: text/plain');

if (isset($_GET['module'])) {
	$module = $_GET['module'];
	$role_id = (int) $_GET['role'];
	$ext_id = null;
	foreach ($installed_extensions as $id => $ext)
		if ($ext['package'] === $module)
			$ext_id = $id;
	$role = get_security_role($role_id);
	if ($ext_id === null || !$role) {
		http_response_code(404);
		echo $ext_id === null ? "no module $module\n" : "no role $role_id\n";
		exit;
	}
	$sections = array_filter($role['sections'], 'strlen');
	$areas = array_filter($role['areas'], 'strlen');
	$added = 0;
	foreach (array_keys($security_sections) as $code)
		if (($code >> 16) == $ext_id && !in_array((string) $code, $sections, true))
			$sections[] = (string) $code;
	foreach ($security_areas as $area)
		if (($area[0] >> 16) == $ext_id && !in_array((string) $area[0], $areas, true)) {
			$areas[] = (string) $area[0];
			$added++;
			if (($area[0] & ~0xffff) && (($area[0] & 0xff00) < (99 << 8))) {
				$extra = (string) ($area[0] & ~0xff);
				if (!in_array($extra, $sections, true))
					$sections[] = $extra;
			}
		}
	update_security_role($role_id, $role['role'], $role['description'], $sections, $areas);
	echo "granted $added areas of $module to role $role_id\n";
	exit;
}

$sections = array_keys($security_sections);
$areas = array();
foreach ($security_areas as $area) {
	$areas[] = $area[0];
	if (($area[0] & ~0xffff) && (($area[0] & 0xff00) < (99 << 8))) {
		$extra = $area[0] & ~0xff;
		if (!in_array($extra, $sections, true))
			$sections[] = $extra;
	}
}
$row = db_fetch(db_query("SELECT id FROM " . TB_PREF . "security_roles WHERE role = 'FA CI'"));
if ($row) {
	$role_id = (int) $row['id'];
	update_security_role($role_id, 'FA CI', 'Every area (docker/ci)', $sections, $areas);
} else {
	add_security_role('FA CI', 'Every area (docker/ci)', $sections, $areas);
	$role_id = (int) db_insert_id();
}
db_query("UPDATE " . TB_PREF . "users SET role_id = $role_id WHERE user_id = 'test'");
echo 'granted ', count($areas), ' areas in ', count($sections), " sections to role FA CI\n";
