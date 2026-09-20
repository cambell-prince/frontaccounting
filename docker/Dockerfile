# FrontAccounting test/development image: Apache + mod_php.
#
# PHP_VERSION is chosen in docker/.env. FrontAccounting 2.4.x is written against
# PHP 5.4-7.x, so 7.4 is the newest version the code is actually known to run on
# and is the default here; .devcontainer builds on 7.4 too.
ARG PHP_VERSION=7.4
FROM php:${PHP_VERSION}-apache

ARG INSTALL_XDEBUG=true

# php:7.4-* images are built on Debian bullseye, whose LTS ended on 2026-08-31:
# deb.debian.org still serves the bullseye-security index but no longer serves
# the .deb files it points at, so a stock `apt-get install` here fails with a
# wall of 404s. Point at the archive instead, and at main alone — the archive
# has no Release file for bullseye-security, and an EOL suite has no further
# security updates to miss. Newer PHP_VERSIONs are built on bookworm or later
# and are left untouched.
RUN set -eux; \
    codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"; \
    case "$codename" in \
        buster|bullseye) \
            printf 'deb http://archive.debian.org/debian %s main\n' "$codename" \
                > /etc/apt/sources.list; \
            rm -f /etc/apt/sources.list.d/*.list; \
            printf 'Acquire::Check-Valid-Until "false";\n' \
                > /etc/apt/apt.conf.d/99archive; \
            ;; \
    esac

# mysqli is required (includes/db/connect_db_mysqli.inc), gd is used by the
# reporting/ PDF and chart code, gettext gives native _() instead of FA's slower
# PHP emulation, and zip keeps composer from falling back to unzipping by hand.
# The mariadb client is what `docker/fa mysql` and the db load/dump commands use.
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        default-mysql-client \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libzip-dev \
        unzip \
        ; \
    if [ "$(php -r 'echo PHP_VERSION_ID;')" -ge 70400 ]; then \
        docker-php-ext-configure gd --with-freetype --with-jpeg; \
    else \
        docker-php-ext-configure gd --with-freetype-dir=/usr --with-jpeg-dir=/usr; \
    fi; \
    docker-php-ext-install -j"$(nproc)" gd gettext mysqli pdo_mysql zip; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Pinned per PHP version: the 3.1 line is the last supporting PHP 7.2-7.4.
# The settings live in xdebug's own conf.d file rather than the general one
# because the entrypoint enables and disables the whole file as a unit — see
# docker-entrypoint.sh for why it has to be off rather than merely idle.
RUN set -eux; \
    if [ "${INSTALL_XDEBUG}" = "true" ]; then \
        if [ "$(php -r 'echo PHP_VERSION_ID;')" -lt 80000 ]; then \
            pecl install xdebug-3.1.6; \
        else \
            pecl install xdebug-3.3.2; \
        fi; \
        docker-php-ext-enable xdebug; \
        { \
            echo 'xdebug.mode = ${XDEBUG_MODE}'; \
            echo 'xdebug.client_host = host.docker.internal'; \
            echo 'xdebug.client_port = 9003'; \
            echo 'xdebug.start_with_request = trigger'; \
        } >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini; \
    fi

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY php.ini /usr/local/etc/php/conf.d/zz-frontaccounting.ini
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

WORKDIR /var/www/html

COPY docker-entrypoint.sh /usr/local/bin/fa-entrypoint
RUN chmod +x /usr/local/bin/fa-entrypoint

# Replaces the base image's ENTRYPOINT, so its CMD has to be restated.
ENTRYPOINT ["fa-entrypoint"]
CMD ["apache2-foreground"]
