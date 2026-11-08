FROM php:8.2-apache
ARG FLUXCP_REF=98cd4b8fd83228c11b36fb3d097b8e0f7c105a8d
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip libzip-dev libpng-dev libjpeg62-turbo-dev libfreetype6-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" pdo_mysql mysqli zip gd \
    && a2enmod rewrite headers \
    && rm -rf /var/lib/apt/lists/*
# The stock php image ships without a php.ini, so PHP prints warnings and deprecations
# straight into FluxCP's pages (FluxCP installs no error handler of its own). Log errors
# to stderr instead of displaying them, and leave out E_DEPRECATED, which this FluxCP
# revision triggers on PHP 8 (for example trim(null)). FluxCP's DebugMode setting still
# turns full error display back on at runtime when you need it.
RUN printf '%s\n' 'display_errors=Off' 'log_errors=On' 'error_reporting=E_ALL & ~E_DEPRECATED' > "$PHP_INI_DIR/conf.d/zz-fluxcp.ini"
WORKDIR /var/www/html
# rAthena's FluxCP repository does not include composer.json; its dependencies
# are not installed with Composer in the upstream master branch.
RUN git config --global --add safe.directory /var/www/html \
    && git clone https://github.com/rathena/FluxCP.git . \
    && git checkout "${FLUXCP_REF}" \
    && test -s /var/www/html/config/application.php \
    && test -s /var/www/html/config/servers.php \
    && mkdir -p /usr/share/fluxcp-default-config \
    && cp -a /var/www/html/config/. /usr/share/fluxcp-default-config/ \
    && php -l /usr/share/fluxcp-default-config/application.php \
    && php -l /usr/share/fluxcp-default-config/servers.php
COPY docker-entrypoint.sh /usr/local/bin/fluxcp-entrypoint
RUN chmod +x /usr/local/bin/fluxcp-entrypoint
EXPOSE 80
ENTRYPOINT ["/usr/local/bin/fluxcp-entrypoint"]
CMD ["apache2-foreground"]
