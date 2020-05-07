FROM alpine:latest

LABEL maintainer="Drew Gauderman <drew@hyak.co>" \
    Description="php/nginx/mysql/server for website development."

ENV HTTP http
ENV WEBSITE_HOSTNAME website.test
ENV PHP_EXPOSE Off
ENV PHP_POST_MAX_SIZE 8M
ENV PHP_UPLOAD_MAX_FILESIZE 50M
ENV PHP_DISPLAY_ERRORS On
ENV PHP_ERROR_REPORTING E_ALL
ENV PHP_TIMEZONE UTC

#ENV PHPMYADMIN_VERSION=
#ENV MYSQL_ROOT_PASSWORD=
#ENV MYSQL_DATABASE=
#ENV MYSQL_USERNAME=
#ENV MYSQL_PASSWORD=

#WORDPRESS_VERSION
#BACKUP_SITE_DOWNLOAD
#BACKUP_USERNAME
#BACKUP_PASSWORD
#BACKUP_EXCLUDE

# Configure nginx
COPY config/nginx.tmpl /etc/nginx/nginx.tmpl

# Configure PHP-FPM
COPY config/fpm-pool.conf /etc/php7/php-fpm.d/zzz_custom.conf
COPY config/php.tmpl /etc/php7/conf.d/zzz_custom.tmpl

# Configure supervisord
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Configure scripts
COPY config/docker-entrypoint.sh /etc/entrypoint.sh
RUN chmod +x /etc/entrypoint.sh;

# Configure Azure SSH
COPY config/sshd_config /etc/ssh/

# Configure mysql
COPY config/my.cnf /etc/my.cnf
RUN chmod 0444 /etc/my.cnf

# install required software
RUN set -ex;\
    apk add --no-cache \
    # common installs
    bash \
    supervisor \
    nginx \
    curl \
    unzip \
    mariadb \
    mariadb-client \
    openssh \
    openssl \
    openrc \
    # php install & extentions
    php7 \
    php7-common \
    php7-tokenizer \
    php7-fpm \
    php7-json \
    php7-xml \
    php7-simplexml \
    php7-dom \
    php7-exif \
    php7-fileinfo \
    php7-iconv \
    php7-ctype \
    php7-mbstring \
    php7-mysqli \
    php7-openssl \
    php7-imagick \
    php7-session \
    php7-pdo \
    php7-pdo_mysql \
    php7-curl \
    php7-gd \
    php7-zlib \
    php7-phar \
    php7-zip; \
    # azure ssh configure
    echo "root:Docker!" | chpasswd;\
    ssh-keygen -f /etc/ssh/ssh_host_rsa_key -N '' -t rsa;\
    # setup folders
    rm -rf /var/www /var/db && mkdir /var/db/ /var/www/;\
    # setup test file
    echo "<?php phpinfo();" > /var/www/index.php;\
    # ensure www-data user exists
    # addgroup -g 82 -S www-data; \
    adduser -u 82 -D -S -G www-data www-data;

# install Dockerize: https://github.com/jwilder/dockerize
ENV DOCKERIZE_VERSION v0.6.1
RUN wget https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && rm dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz

WORKDIR /var/www/

EXPOSE 80 2222 3306

ENTRYPOINT [ "/etc/entrypoint.sh" ]

# Configure a healthcheck to validate that everything is up & running
HEALTHCHECK --timeout=10s CMD curl --silent --fail http://127.0.0.1/fpm-ping
