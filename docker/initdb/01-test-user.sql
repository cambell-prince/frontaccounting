-- Runs once, when the db volume is first created.
--
-- modules/tests/data/config_db.php and the gulpfile's env-db/test-php tasks
-- both expect a passwordless 'travis' account (the suite was written against
-- Travis CI, where that is the stock mysql user). Creating it here means the
-- committed test fixtures work unedited inside this stack.
CREATE USER IF NOT EXISTS 'travis'@'%' IDENTIFIED BY '';
GRANT ALL PRIVILEGES ON *.* TO 'travis'@'%';

FLUSH PRIVILEGES;
