# FrontAccounting test/development image: Debian trixie, Apache + mod_php.
#
# The official php:7.4-* images are built on Debian bullseye, whose LTS ended on
# 2026-08-31 — deb.debian.org still serves the bullseye-security index but not
# the packages it points at, so those images can only be built against
# archive.debian.org. There is no 7.4 image on trixie and never will be; PHP 7.4
# itself went end-of-life in 2022.
#
# So the base is plain Debian trixie and PHP comes from Ondřej Surý's
# repository, which still builds 7.4 for current Debian. That keeps the OS
# supported and patched while FrontAccounting 2.4.x stays on the PHP version it
# is actually written against.
FROM debian:trixie-slim

# Any version sury publishes for trixie: 7.4, 8.0 … 8.4. FA 2.4.x is written
# against PHP 5.4-7.x, so 7.4 is the newest it is known to run on.
ARG PHP_VERSION=7.4
ARG INSTALL_XDEBUG=true

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        ; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://packages.sury.org/php/apt.gpg \
        -o /etc/apt/keyrings/sury-php.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/sury-php.gpg] https://packages.sury.org/php/ trixie main" \
        > /etc/apt/sources.list.d/sury-php.list; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# mysqli is required (includes/db/connect_db_mysqli.inc); gd is used by the
# reporting/ PDF and chart code; mbstring, xml and zip are what the extension
# installer and composer expect. gettext gives native _() rather than FA's
# slower PHP emulation and comes bundled in php-common. mariadb-client is what
# `docker/fa mysql` and the db load/dump commands use.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        apache2 \
        mariadb-client \
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
        ; \
    if [ "${INSTALL_XDEBUG}" = "true" ]; then \
        apt-get install -y --no-install-recommends php${PHP_VERSION}-xdebug; \
    fi; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Debian keeps a conf.d per SAPI rather than the single one the php images have,
# and the CLI (phpunit, composer) must see the same settings as Apache.
COPY php.ini /etc/php/${PHP_VERSION}/apache2/conf.d/zz-frontaccounting.ini
COPY php.ini /etc/php/${PHP_VERSION}/cli/conf.d/zz-frontaccounting.ini

COPY apache-frontaccounting.conf /etc/apache2/conf-available/frontaccounting.conf

RUN set -eux; \
    a2enmod rewrite; \
    a2enconf frontaccounting

# The checkout is bind-mounted over /var/www/html, and FrontAccounting writes
# into it at runtime: company/<n>/{js_cache,pdf_files,backup}, tmp/, and the
# generated config files. Give www-data the host user's ids so those writes land
# as files you still own on the host. Skipped when they already match, because
# usermod refuses to assign an id the account already has.
ARG USER_UID=1000
ARG USER_GID=1000
RUN set -eux; \
    if [ "$(id -u www-data)" != "${USER_UID}" ] || [ "$(id -g www-data)" != "${USER_GID}" ]; then \
        groupmod -o -g "${USER_GID}" www-data; \
        usermod -o -u "${USER_UID}" -g "${USER_GID}" www-data; \
    fi

# phpenmod/phpdismod in the entrypoint need to know which version to act on, and
# docker/fa reads neither — so bake the build's choice into the environment.
ENV PHP_VERSION=${PHP_VERSION}

WORKDIR /var/www/html

EXPOSE 80

COPY docker-entrypoint.sh /usr/local/bin/fa-entrypoint
RUN chmod +x /usr/local/bin/fa-entrypoint

ENTRYPOINT ["fa-entrypoint"]
CMD ["apache2ctl", "-D", "FOREGROUND"]
