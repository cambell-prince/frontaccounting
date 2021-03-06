<?php
require_once (__DIR__ . '/TestConfig.php');

$path_to_root = SRC_PATH;
require_once (SRC_PATH . '/config_db.php');
require_once (SRC_PATH . '/config.php');

require_once (SRC_PATH . '/includes/current_user.inc');

class TestUser extends current_user
{
	public $cur_con;
	public $company;

	public function __construct()
	{
		$this->cur_con = 0;
		$this->company = 0;
		parent::__construct();
	}
}

class MockRefs
{
	function save() {
	}

}

class TestEnvironment
{

	private static function resetErrorReporting()
	{
		// Undo that which is setup in config.php (of all places)
		error_reporting(-1);

	}

	/**
	 * This function setups up dependencies that exist in code that have been included at too high a level
	 * for unit testing (i.e. in a function that also declares global variable at the top level), so they are included here.
	 */
	private static function setupCodeDependencies()
	{
		self::includeFile('admin/db/transactions_db.inc');
	}
	
	private static function setupSQL()
	{
		global $db, $show_sql, $sql_trail, $select_trail, $go_debug, $sql_queries, $Ajax,
			$db_connections, $db_last_inserted_id;
		self::includeFile('config_db.php');
		self::includeFile('includes/db/connect_db.inc');
		self::includeFile('includes/db/sql_functions.inc');
		self::includeFile('includes/errors.inc');
		set_global_connection();
	}

	private static function setupSQLDependencies()
	{
		self::includeFile('includes/hooks.inc');
		self::includeFile('includes/types.inc');
		self::includeFile('includes/db/comments_db.inc');
		self::includeFile('includes/db/audit_trail_db.inc');
		self::mockRefs();
	}

	private static function setupSesstion()
	{
		self::includeFile('includes/session_utils.inc');
		self::includeFile('includes/prefs/sysprefs.inc');
		$_SESSION['SysPrefs'] = new sys_prefs();
		$GLOBALS['SysPrefs'] = &$_SESSION['SysPrefs'];
		
		self::includeFile('includes/lang/language.inc');
		$_SESSION['language'] = new language('default', 'C', 'utf-8', 'ltr');
		
		$_SESSION["wa_current_user"] = new TestUser();
	}

	private static function mockRefs()
	{
		$GLOBALS['Refs'] = new MockRefs();
	}

	public static function isGoodToGo()
	{
		global $db_connections;
		self::resetErrorReporting();
		self::setupSesstion();
		self::setupSQL();
		self::setupSQLDependencies();
		self::setupCodeDependencies();
		$msg = '';
		$dbname = $db_connections[0]['dbname'];
		$expected = 'fa_test';
		if ($dbname != $expected) {
			$msg .= "Error: Wrong database '$dbname' expected '$expected'";
		}
		return ($msg == '') ? 'OK' : $msg;
	}

	public static function includeFile($filePath)
	{
		$path_to_root = SRC_PATH;
		require_once(SRC_PATH . '/' . $filePath);
	}

	public static function currentAccount() {
		return 1;
	}

	public static function cashAccount() {
		return 2;
	}

	public static function cleanTable($table) {
		$sql = 'DELETE FROM ' . '0_' . $table;
		db_query($sql, "Could not clean table '$table'");
	}

	public static function cleanBanking() {
		self::cleanTable('bank_trans');
		self::cleanTable('gl_trans');
		self::cleanTable('comments');
	}

}