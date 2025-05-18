FROM php:8.3-apache

ARG GLPI_VERSION=10.0.17

# Install required PHP extensions and system packages
RUN apt-get update && apt-get install -y \
    libpng-dev libjpeg62-turbo-dev libfreetype6-dev \
    libxml2-dev libonig-dev libzip-dev libicu-dev \
    libldap2-dev libssl-dev libbz2-dev \
    unzip curl build-essential rsync \
 && docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install \
    pdo pdo_mysql mysqli gd xml mbstring zip bcmath intl \
    exif ldap bz2 opcache \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Enable Apache rewrite module
RUN a2enmod rewrite

# Set Apache to listen on port 8080 (OpenShift-compatible)
RUN sed -i 's/Listen 80/Listen 8080/' /etc/apache2/ports.conf

# Redirect Apache logs to stdout/stderr for OpenShift logging
RUN ln -sf /dev/stderr /var/log/apache2/error.log && \
    ln -sf /dev/stdout /var/log/apache2/access.log

# Set working directory
WORKDIR /var/www

# Download and extract GLPI
RUN curl -L -o /tmp/glpi.tgz https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/glpi-${GLPI_VERSION}.tgz && \
    tar -xzf /tmp/glpi.tgz -C /var/www && \
    rm /tmp/glpi.tgz

# Create GLPI data directories and set permissions
RUN mkdir -p /var/lib/glpi/{_cache,_cron,_dumps,_graphs,_lock,_pictures,_plugins,_rss,_sessions,_tmp,_uploads} && \
    mkdir -p /var/log/glpi && \
    chown -R www-data:0 /var/lib/glpi /var/log/glpi && \
    chmod -R 775 /var/lib/glpi /var/log/glpi

# Create config directory
RUN mkdir -p /var/www/config && \
    echo "<?php \
define('GLPI_VAR_DIR', '/var/lib/glpi'); \
define('GLPI_LOG_DIR', '/var/log/glpi'); \
?>" > /var/www/config/local_define.php && \
    chown -R www-data:0 /var/www/config && \
    chmod -R 775 /var/www/config

# Configure downstream.php
RUN echo "<?php \
define('GLPI_CONFIG_DIR', '/var/www/config'); \
if (file_exists(GLPI_CONFIG_DIR . '/local_define.php')) { \
    require_once GLPI_CONFIG_DIR . '/local_define.php'; \
} \
?>" > /var/www/glpi/inc/downstream.php

# Set permissions for GLPI
RUN chown -R www-data:0 /var/www/glpi && \
    chmod -R 775 /var/www/glpi

# PHP configuration
RUN echo "memory_limit = 256M" > /usr/local/etc/php/conf.d/glpi.ini && \
    echo "upload_max_filesize = 20M" >> /usr/local/etc/php/conf.d/glpi.ini && \
    echo "post_max_size = 20M" >> /usr/local/etc/php/conf.d/glpi.ini && \
    echo "max_execution_time = 60" >> /usr/local/etc/php/conf.d/glpi.ini && \
    echo "session.cookie_httponly = On" >> /usr/local/etc/php/conf.d/glpi.ini

# Copy custom Apache vhost config
COPY glpi.conf /etc/apache2/sites-available/000-default.conf

# Set ServerName globally to suppress FQDN warning
RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf

# Ensure Apache runs as www-data with group 0 (OpenShift root group)
RUN sed -i 's/User www-data/User www-data/' /etc/apache2/apache2.conf && \
    sed -i 's/Group www-data/Group 0/' /etc/apache2/apache2.conf

EXPOSE 8080
