<?php
/*
	Self-contained test of admin/includes/local_versions.inc. It needs no FA
	bootstrap, database or PHPUnit; run it with plain php:

		php modules/tests/local_versions_test.php
*/
$root = dirname(dirname(__DIR__));
if (!function_exists('clean_file_name')) { // as in includes/main.inc
	function clean_file_name($filename) {
		$filename = str_replace(chr(0), '', $filename);
		return preg_replace('/[^a-zA-Z0-9.\-_]/', '_', $filename);
	}
}
require_once $root.'/admin/includes/local_versions.inc';

$failures = 0;
function check($ok, $what) {
	global $failures;
	echo ($ok ? 'ok     ' : 'FAILED ').$what."\n";
	if (!$ok) $failures++;
}
function rrmdir($d) {
	foreach (array_diff(scandir($d), array('.', '..')) as $f)
		is_dir("$d/$f") ? rrmdir("$d/$f") : unlink("$d/$f");
	rmdir($d);
}

$tmp = sys_get_temp_dir().'/fa_lv_'.getmypid();
mkdir("$tmp/modules/demo/_init", 0777, true);
mkdir("$tmp/modules/repo_pkg", 0777, true);
mkdir("$tmp/x/_init", 0777, true);
$cfg = "$tmp/modules/demo/_init/config";
file_put_contents($cfg, "Package: demo\nName: demo\nVersion: 2.4-1.5.0\n\n");
file_put_contents("$tmp/x/_init/config", "Version: 9.9\n");

$exts = array(
	0 => array('package' => 'demo', 'name' => 'demo', 'version' => '-', 'type' => 'extension', 'path' => 'modules/demo', 'active' => false),
	1 => array('package' => 'repo_pkg', 'name' => 'repo_pkg', 'version' => '2.4.0-1', 'type' => 'extension', 'path' => 'modules/repo_pkg', 'active' => false),
	2 => array('package' => 'chart_x', 'name' => 'chart', 'version' => '2.3.0-3', 'type' => 'chart', 'path' => 'sql', 'active' => false),
);
$new = refresh_local_versions($exts, $tmp);
check(is_array($new) && $new[0]['version'] === '2.4-1.5.0', 'version refreshed from _init/config');
check(is_array($new) && $new[1]['version'] === '2.4.0-1', 'no _init/config: untouched');
check(is_array($new) && $new[2] === $exts[2], 'not an extension: untouched');
check(refresh_local_versions($new, $tmp) === false, 'nothing changed on a second run');

file_put_contents($cfg, "garbage without a colon\n");
check(refresh_local_versions($exts, $tmp) === false, 'garbled config: untouched');
file_put_contents($cfg, "Package: demo\nName: demo\n\n");
check(refresh_local_versions($exts, $tmp) === false, 'no Version key: untouched');
unlink($cfg);
check(refresh_local_versions($exts, $tmp) === false, 'missing config: untouched');

$evil = array(0 => array('package' => '../x', 'name' => 'x', 'version' => '-', 'type' => 'extension', 'path' => 'modules/../x'));
check(refresh_local_versions($evil, $tmp) === false, 'path outside modules/ never read');
$evil[0]['path'] = '../x';
check(refresh_local_versions($evil, $tmp) === false, 'path ../x never read');

rrmdir($tmp);
echo $failures ? "$failures FAILED\n" : "all passed\n";
exit($failures ? 1 : 0);
