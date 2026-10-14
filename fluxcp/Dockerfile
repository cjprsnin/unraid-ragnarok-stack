FROM php:8.2-apache
ARG FLUXCP_REF=98cd4b8fd83228c11b36fb3d097b8e0f7c105a8d
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip libzip-dev libpng-dev libjpeg62-turbo-dev libfreetype6-dev libcurl4-openssl-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" pdo_mysql mysqli zip gd curl \
    && a2enmod rewrite headers \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /var/www/html
# rAthena's FluxCP repository does not include composer.json; its dependencies
# are not installed with Composer in the upstream master branch.
RUN git config --global --add safe.directory /var/www/html \
    && git clone https://github.com/rathena/FluxCP.git . \
    && git checkout "${FLUXCP_REF}" \
    && test -s /var/www/html/config/application.php \
    && test -s /var/www/html/config/servers.php \
    && test -d /var/www/html/data/schemas \
    && mkdir -p /usr/share/fluxcp-default-config /usr/share/fluxcp-default-data \
    && cp -a /var/www/html/config/. /usr/share/fluxcp-default-config/ \
    && cp -a /var/www/html/data/schemas /usr/share/fluxcp-default-data/schemas \
    && php -l /usr/share/fluxcp-default-config/application.php \
    && php -l /usr/share/fluxcp-default-config/servers.php
COPY docker-entrypoint.sh /usr/local/bin/fluxcp-entrypoint
COPY bootstrap-schemas.php /usr/local/bin/fluxcp-bootstrap-schemas.php
RUN chmod +x /usr/local/bin/fluxcp-entrypoint && php -l /usr/local/bin/fluxcp-bootstrap-schemas.php
EXPOSE 80
ENTRYPOINT ["/usr/local/bin/fluxcp-entrypoint"]
CMD ["apache2-foreground"]
