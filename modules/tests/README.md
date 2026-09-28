# FrontAccounting Test Module

This module contains tests for the [Front Accounting](http://frontaccounting.com) web based accounting system.

Currently two types of tests are available:

1. E2E tests using the protractor test framework
2. PHP unit tests using the PHPUnit test framework

The E2E tests exercise the UI much as a user would.
The PHP unit tests exercise the database back end for various functions.

### Status
The test suite is far (very far) from complete. In fact, it has only just begun.

You can have a look at our current [Code Coverage](https://rawgit.com/wiki/cambell-prince/frontaccounting/code_coverage/index.html).  The code coverage report is updated manually from time to time and may not be up to date.  The Code Coverage report only reflects code covered by the PHPUnit tests.  It does not report on code covered by the E2E tests.

### Running the tests

The PHPUnit suite runs in the docker test stack (see `docker/README.md`):

	docker/fa up
	docker/fa test

or `make.phar test` from the top of the checkout, which does the same.

The Protractor E2E tests under `e2e/` are not run any more. They need node 10,
selenium 3 and PhantomJS, and the gulp tasks and Travis configuration that drove
them were removed along with gulp; they are in the history before
`makefile.json` if the suite is revived.
