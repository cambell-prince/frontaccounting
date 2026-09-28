# Developer Notes

## Deploying

`makefile.json` deploys this branch with [make.phar](https://github.com/saygoweb/phpmake)
to bms.saygoweb.com; see `deploy/README.md`.

    make.phar release          # build/release: this branch plus graphql, sgw_sales, sgw_import and the bootstrap theme
    make.phar deploy-check     # dry run against the server; read what it would delete
    make.phar deploy confirm=yes

The demo site takes the same release with another destination:

    make.phar deploy-check dest=root@saygoweb.com:/var/www/virtual/saygoweb.com/demo/htdocs/frontaccounting/

`make.phar db-backup` dumps the live database into `backup/`.
