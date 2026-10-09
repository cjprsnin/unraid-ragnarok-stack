FROM composer:2 AS composer
FROM php:8.2-apache
ARG FLUXCP_REF=master
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip libzip-dev libpng-dev libjpeg62-turbo-dev libfreetype6-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" pdo_mysql mysqli zip gd \
    && a2enmod rewrite headers \
    && rm -rf /var/lib/apt/lists/*
COPY --from=composer /usr/bin/composer /usr/local/bin/composer
WORKDIR /var/www/html
# Newer Git versions enforce safe.directory when the web image owns the workdir.
RUN git config --global --add safe.directory /var/www/html \
    && git clone https://github.com/rathena/FluxCP.git . \
    && git checkout "${FLUXCP_REF}" \
    && composer install --no-dev --prefer-dist --no-interaction --no-progress
COPY docker-entrypoint.sh /usr/local/bin/fluxcp-entrypoint
RUN chmod +x /usr/local/bin/fluxcp-entrypoint
EXPOSE 80
ENTRYPOINT ["/usr/local/bin/fluxcp-entrypoint"]
CMD ["apache2-foreground"]
