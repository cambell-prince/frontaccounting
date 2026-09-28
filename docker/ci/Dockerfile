# FrontAccounting CI image: Apache + mod_php + MariaDB + FrontAccounting with a
# seeded fa_test database, in one container, for plugins' tests. Built by
# docker/ci/build-image.sh, which supplies two named build contexts:
#
#   fa       the FrontAccounting tree to install (this fork's HEAD, or upstream)
#   fixture  fa_test.sql.gz, the database it is seeded with
#
# PHP comes from Ondřej Surý's repository on Debian trixie, as in docker/Dockerfile.
FROM debian:trixie-slim

ARG PHP_VERSION=7.4
ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://packages.sury.org/php/apt.gpg -o /etc/apt/keyrings/sury-php.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/sury-php.gpg] https://packages.sury.org/php/ trixie main" \
        > /etc/apt/sources.list.d/sury-php.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        apache2 \
        git \
        mariadb-client \
        mariadb-server \
        unzip \
        libapache2-mod-php${PHP_VERSION} \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-common \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-xdebug \
        ; \
    phpdismod -v "${PHP_VERSION}" xdebug; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY image/php.ini /etc/php/${PHP_VERSION}/apache2/conf.d/zz-fa-ci.ini
COPY image/php.ini /etc/php/${PHP_VERSION}/cli/conf.d/zz-fa-ci.ini
COPY image/apache-fa-ci.conf /etc/apache2/conf-available/fa-ci.conf
RUN a2enmod rewrite && a2enconf fa-ci
# Files Apache creates (tmp/faillog.php, tmp/errors.log) stay writable by the
# test uid, which runs with group www-data.
RUN echo 'umask 002' >> /etc/apache2/envvars

COPY image/fa-mail-catcher /usr/local/bin/fa-mail-catcher
RUN chmod 0755 /usr/local/bin/fa-mail-catcher && install -d -m 0777 /var/mail-catcher

COPY image/fa-ci-* /usr/local/lib/fa-ci/
RUN set -eux; \
    chmod 0755 /usr/local/lib/fa-ci/*; \
    for f in /usr/local/lib/fa-ci/*; do ln -s "$f" /usr/local/bin/; done

# The seeded database. utf8mb4_general_ci by default, for parity with the
# plugins' old MariaDB 10.11 stacks (11.x otherwise defaults utf8mb4 to
# utf8mb4_uca1400_ai_ci, which reorders some ORDER BY results tests rely on).
COPY image/mariadb-fa-ci.cnf /etc/mysql/mariadb.conf.d/60-fa-ci.cnf
COPY --from=fixture fa_test.sql.gz /usr/local/share/fa-ci/fa_test.sql.gz
COPY image/seed-db.sh /usr/local/lib/fa-ci-build/seed-db.sh
RUN sh /usr/local/lib/fa-ci-build/seed-db.sh

# FrontAccounting, configured for that database. Owned by www-data, group-
# writable and setgid, so commands run as the caller's uid with group
# www-data can change it (tests rewrite config_db.php and the extension lists).
COPY --from=fa . /var/www/html/
COPY image/config_db.php /var/www/html/config_db.php
COPY image/grant.php /var/www/html/fa-ci/grant.php
RUN set -eux; \
    cd /var/www/html; \
    rm -f index.html; \
    cp config.default.php config.php; \
    printf '<?php\n\n$next_extension_id = 1;\n\n$installed_extensions = array (\n);\n' > installed_extensions.php; \
    install -d company/0 company/0/js_cache company/0/pdf_files company/0/backup company/0/images company/0/attachments tmp lang fa-ci; \
    printf '<?php\n\n$installed_extensions = array (\n);\n' > company/0/installed_extensions.php; \
    printf '<?php\n\n$installed_languages = array (\n  0 => array (\n    %s,\n    %s,\n    %s,\n    %s,\n  ),\n);\n\n$dflt_lang = %s;\n' \
        "'code' => 'C'" "'name' => 'English'" "'encoding' => 'iso-8859-1'" "'version' => '1'" "'C'" \
        > lang/installed_languages.inc; \
    chown -R www-data:www-data /var/www/html; \
    chmod -R g+w /var/www/html; \
    find /var/www/html -type d -exec chmod g+s {} +

ENV PHP_VERSION=${PHP_VERSION} \
    FA_ROOT=/var/www/html \
    FA_URL=http://localhost \
    FA_DB_HOST=localhost \
    FA_DB_NAME=fa_test \
    FA_DB_PREFIX=0_ \
    FA_DB_USER=fa \
    FA_DB_PASSWORD=fa

WORKDIR /var/www/html
EXPOSE 80

COPY image/entrypoint.sh /usr/local/bin/fa-ci-entrypoint
RUN chmod 0755 /usr/local/bin/fa-ci-entrypoint
ENTRYPOINT ["fa-ci-entrypoint"]
CMD ["apache2ctl", "-D", "FOREGROUND"]
