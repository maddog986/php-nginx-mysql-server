#!/bin/bash

# disable output if no files
shopt -s nullglob

# Dockersize stuff
dockerize -template /etc/nginx/nginx.tmpl >/etc/nginx/nginx.conf
dockerize -template /etc/php7/conf.d/zzz_custom.tmpl >/etc/php7/conf.d/zzz_custom.ini

# set a MySQL Root password if not passed in
if [[ -z "${MYSQL_ROOT_PASSWORD}" ]]; then
    MYSQL_ROOT_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
fi

echo "Setting up MySQL... Root Password: $MYSQL_ROOT_PASSWORD"

# setup mysql
mysql_install_db --skip-test-db >/dev/null

# run setup script
/usr/bin/mysqld --bootstrap --verbose=0 --skip-name-resolve --skip-networking=0 <<EOF
USE mysql;
FLUSH PRIVILEGES;
DELETE FROM mysql.user;
GRANT ALL ON *.* TO 'root'@'%' identified by '$MYSQL_ROOT_PASSWORD' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

echo "done."

{
    # download phpmyadmin
    if [ -n "${PHPMYADMIN_VERSION}" ]; then
        echo "Downloading phpmyadmin from: https://files.phpmyadmin.net/phpMyAdmin/${PHPMYADMIN_VERSION}/phpMyAdmin-${PHPMYADMIN_VERSION}-english.tar.gz"
        curl -o /tmp/phpmyadmin.tar.gz -fSL "https://files.phpmyadmin.net/phpMyAdmin/${PHPMYADMIN_VERSION}/phpMyAdmin-${PHPMYADMIN_VERSION}-english.tar.gz"
        mkdir -p /tmp/phpmyadmin
        tar -xzf /tmp/phpmyadmin.tar.gz -C /tmp/phpmyadmin/
        mkdir -p /var/www/phpmyadmin/
        cp -rf /tmp/phpmyadmin/phpMyAdmin-${PHPMYADMIN_VERSION}-english/* /var/www/phpmyadmin/
        rm -rf /tmp/phpmyadmin /tmp/phpmyadmin.tar.gz
        echo "done."
    fi

    # download wordpress if a version is passed in
    if [ -n "${WORDPRESS_VERSION}" ]; then
        echo "Downloading WordPress from: https://wordpress.org/wordpress-$WORDPRESS_VERSION.tar.gz"
        curl -o /tmp/wordpress.tar.gz -fSL "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz"
        mkdir /tmp/wordpress
        tar -xzf /tmp/wordpress.tar.gz -C /tmp/wordpress/
        cp -rf /tmp/wordpress/wordpress/* /var/www/
        rm -rf /tmp/wordpress /tmp/wordpress.tar.gz
        echo "done."
    fi

    # download the site base, if passed in
    if [ -n "${BACKUP_SITE_DOWNLOAD}" ]; then
        echo "Downloading site from: $BACKUP_SITE_DOWNLOAD"

        # download using http authentication
        if [ -n "${BACKUP_USERNAME}" ]; then
            curl --user $BACKUP_USERNAME:$BACKUP_PASSWORD -o /tmp/site.zip -fSL "$BACKUP_SITE_DOWNLOAD"
        else
            curl -o /tmp/site.zip -fSL "$BACKUP_SITE_DOWNLOAD"
        fi

        mkdir -p /var/www
        mkdir -p /tmp/site

        unzip -o /tmp/site.zip -d /tmp/site/

        # exclude files from the backup unzip
        if [ -n "${BACKUP_EXCLUDE}" ]; then
            cd /tmp/site
            rm -rf ${BACKUP_EXCLUDE}
        fi

        cp -rf /tmp/site/* /var/www/
        rm -rf /tmp/site.zip /tmp/site
        echo "done."

        # tell nginx to reload config incase a conf is added
        nginx -s reload
    fi

    # fix permissions for folders
    chown -R nobody:nobody /var/www
    chown -R mysql:mysql /var/lib/mysql

    # get database creds from existing wp-config.php
    if [ -f /var/www/wp-config.php ]; then
        echo "Grabing WordPress variables for existing wp-config.php"

        MYSQL_DATABASE=$(cat /var/www/wp-config.php | grep DB_NAME | cut -d \' -f 4)
        MYSQL_USERNAME=$(cat /var/www/wp-config.php | grep DB_USER | cut -d \' -f 4)
        MYSQL_PASSWORD=$(cat /var/www/wp-config.php | grep DB_PASSWORD | cut -d \' -f 4)
        WORDPRESS_TBLPREFIX=$(cat /var/www/wp-config.php | grep "\$table_prefix" | cut -d \' -f 2)

    # new wordpress setup
    elif [ -f /var/www/wp-config-sample.php ]; then
        echo "Setting up new wp-config.php"

        MYSQL_DATABASE=${MYSQL_DATABASE:-wordpress}
        MYSQL_USERNAME=${MYSQL_USERNAME:-wordpress}
        WORDPRESS_TBLPREFIX=${WORDPRESS_TBLPREFIX:-wp_}

        # random database password if it isnt set
        if [[ -z "${MYSQL_PASSWORD}" ]]; then
            MYSQL_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
        fi

        # create the config file from sample
        mv /var/www/wp-config-sample.php /var/www/wp-config.php

        # change variables
        sed -i "/DB_NAME/s/'[^']*'/'$MYSQL_DATABASE'/2" /var/www/wp-config.php
        sed -i "/DB_USER/s/'[^']*'/'$MYSQL_USERNAME'/2" /var/www/wp-config.php
        sed -i "/DB_PASSWORD/s/'[^']*'/'$MYSQL_PASSWORD'/2" /var/www/wp-config.php
        sed -i "/DB_HOST/s/'[^']*'/'localhost:3306'/2" /var/www/wp-config.php

        # update salts
        for salt in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
            RND_SALT=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1)
            sed -i "/$salt/s/'[^']*'/'$RND_SALT'/2" /var/www/wp-config.php
        done

        echo "done."
    fi

    WEBSITE_HOSTNAME=${WEBSITE_HOSTNAME:-website.test}
    HTTP=${HTTP:-https}
    URL="$HTTP://$WEBSITE_HOSTNAME"

    # change require SSL for WordPress.
    if [ -f /var/www/wp-config.php ]; then
        if [ "$HTTP" == "https" ]; then
            sed -i "s/define('FORCE_SSL_ADMIN', false);/define('FORCE_SSL_ADMIN', true);/g" /var/www/wp-config.php
        else
            sed -i "s/define('FORCE_SSL_ADMIN', true);/define('FORCE_SSL_ADMIN', false);/g" /var/www/wp-config.php
        fi

        # change variables
        sed -i "/COOKIE_DOMAIN/s/'[^']*'/'$WEBSITE_HOSTNAME'/2" /var/www/wp-config.php
    fi

    echo "Waiting for MySQL to be ready..."

    # wait until mysql is up and running
    while !(mysqladmin -uroot -p"$MYSQL_ROOT_PASSWORD" ping --silent); do
        echo "."
        sleep 1
    done

    echo "MYSQL Server Ready."

    # create database if one was passed in
    if [ -n "${MYSQL_DATABASE}" ]; then
        echo "Creating Database: $MYSQL_DATABASE (Username: $MYSQL_USERNAME, Password: $MYSQL_PASSWORD)..."

        # make sure database is setup
        /usr/bin/mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\`;GRANT ALL ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USERNAME'@'%' identified by '$MYSQL_PASSWORD' WITH GRANT OPTION;FLUSH PRIVILEGES;"

        echo "Database Created: $MYSQL_DATABASE"
    fi

    # import the .sql scripts if any
    for f in /var/www/*.sql; do
        echo "Importing .SQL file: $f"
        /usr/bin/mysql -u"$MYSQL_USERNAME" -p"$MYSQL_PASSWORD" $MYSQL_DATABASE <"$f"
        echo "SQL File Imported: $f"
        sleep 1
        rm "$f"
    done

    # update wordpress database url
    if [ -n "${WORDPRESS_TBLPREFIX}" ]; then
        # update the site url
        /usr/bin/mysql -uroot -p"$MYSQL_ROOT_PASSWORD" $MYSQL_DATABASE <<EOF
    UPDATE ${WORDPRESS_TBLPREFIX}options
      SET option_value = '$URL'
      WHERE option_name in ('siteurl','home');

    UPDATE ${WORDPRESS_TBLPREFIX}options
      SET option_value = REPLACE(Option_value, CONCAT('http://', SUBSTRING_INDEX(SUBSTRING_INDEX(SUBSTRING_INDEX(SUBSTRING_INDEX(option_value, '/', 3), '://', -1), '/', 1), '?', 1)), '$URL')
      WHERE option_name = 'us_theme_options_css';

    UPDATE ${WORDPRESS_TBLPREFIX}options
      SET option_value = REPLACE(Option_value, CONCAT('https://', SUBSTRING_INDEX(SUBSTRING_INDEX(SUBSTRING_INDEX(SUBSTRING_INDEX(option_value, '/', 3), '://', -1), '/', 1), '?', 1)), '$URL')
      WHERE option_name = 'us_theme_options_css';
EOF
    fi

    echo "Scripts all done. Site should be ready: $URL"

} &

/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
