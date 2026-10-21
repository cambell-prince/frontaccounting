<?php
/**********************************************************************
    Copyright (C) FrontAccounting, LLC.
	Released under the terms of the GNU General Public License, GPL, 
	as published by the Free Software Foundation, either version 3 
	of the License, or (at your option) any later version.
    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
    See the License here <http://www.gnu.org/licenses/gpl-3.0.html>.
***********************************************************************/
/*
	Read the Version of a module's _init/config ("Key: value" lines).
	Returns the version string, or null when the file is missing, unreadable
	or has no Version. Never raises an error.
*/
function read_local_version($file)
{
	$lines = @file($file, FILE_IGNORE_NEW_LINES);
	if (!is_array($lines))
		return null;
	foreach ($lines as $line) {
		if (preg_match('/^Version:\s*(\S.*?)\s*$/', $line, $m))
			return $m[1];
	}
	return null;
}

/*
	A local extension (installed from modules/<id>, not from FA's package
	repository) carries its version in modules/<id>/_init/config, written by
	its build. FA reads it only at install, so an upgrade by file sync would
	keep showing the old version: refresh it here. Returns the updated list,
	or false when nothing changed.
*/
function refresh_local_versions($exts, $root)
{
	$changed = false;
	foreach ($exts as $i => $ext) {
		if (@$ext['type'] != 'extension' || !isset($ext['package']))
			continue;
		$id = clean_file_name($ext['package']);
		if (@$ext['path'] !== 'modules/'.$id)
			continue;
		$version = read_local_version($root.'/modules/'.$id.'/_init/config');
		if ($version === null || $version === @$ext['version'])
			continue;
		$exts[$i]['version'] = $version;
		$changed = true;
	}
	return $changed ? $exts : false;
}
