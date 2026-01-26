FROM php:8.5-fpm AS php-main

# Install system dependencies
RUN apt-get update && apt-get install -y \
    passwd libpq-dev \
    git \
    unzip \
    libzip-dev \
    libonig-dev \
    libfreetype6-dev libpng-dev libjpeg-dev libgpgme-dev libxml2-dev zlib1g-dev zip libicu-dev libxslt1-dev procps \
    libmariadb-dev default-mysql-client

RUN pecl channel-update pecl.php.net
RUN pecl install redis gnupg excimer

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-install mysqli pdo_mysql pdo_pgsql bcmath mbstring soap sockets pcntl intl zip \
    && docker-php-ext-enable pdo_mysql redis pcntl intl gnupg excimer

ADD docker/php/php.ini /usr/local/etc/php/conf.d/php_custom.ini

# Set working directory
WORKDIR /var/www/html

CMD ["php-fpm", "-F"]
ARG WWWGROUP=1000

RUN groupadd --force -g $WWWGROUP sail
RUN useradd -ms /bin/bash --no-user-group -g $WWWGROUP -u 1337 sail

FROM php-main AS development
# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set permissions
RUN chown -R www-data:www-data /var/www/html && chmod -R 775 /var/www/html
RUN mkdir /var/www/.cache
RUN chown -R www-data:www-data /var/www/.cache && chmod -R 775 /var/www/.cache

