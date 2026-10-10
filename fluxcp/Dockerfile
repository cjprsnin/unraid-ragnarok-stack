FROM php:8.2-apache
ARG FLUXCP_REF=master
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip libzip-dev libpng-dev libjpeg62-turbo-dev libfreetype6-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" pdo_mysql mysqli zip gd \
    && a2enmod rewrite headers \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /var/www/html
# rAthena's FluxCP repository does not include composer.json; its dependencies
# are not installed with Composer in the upstream master branch.
RUN git config --global --add safe.directory /var/www/html \
    && git clone https://github.com/rathena/FluxCP.git . \
    && git checkout "${FLUXCP_REF}" \
    && mkdir -p /usr/share/fluxcp-default-config \
    && cp -a /var/www/html/config/. /usr/share/fluxcp-default-config/
COPY docker-entrypoint.sh /usr/local/bin/fluxcp-entrypoint
RUN chmod +x /usr/local/bin/fluxcp-entrypoint
EXPOSE 80
ENTRYPOINT ["/usr/local/bin/fluxcp-entrypoint"]
CMD ["apache2-foreground"]
