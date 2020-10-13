#!/bin/bash

# disable output if no files
shopt -s nullglob

WEBSITE_HOSTNAME=${WEBSITE_HOSTNAME:-website.test}
HTTP=${HTTP:-https}
URL="$HTTP://$WEBSITE_HOSTNAME"
MYSQL_HOST=${MYSQL_HOST:-localhost:3306}
WORDPRESS_TBLPREFIX=${WORDPRESS_TBLPREFIX:-wp_}
WORDPRESS_INSTALL=${WORDPRESS_INSTALL:-false}

# random database password if it isnt set
if [[ -z "${MYSQL_PASSWORD}" ]]; then
    MYSQL_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
fi

# setup wordpress cli regardless if we are using WordPress or not
if [ ! -f "/usr/local/bin/wp" ]; then
    # install wordpress-cli
    cd /tmp
    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp
fi

# download phpmyadmin if not already
if [ -n "${PHPMYADMIN_VERSION}" ] && [ ! -d "/var/phpmyadmin" ]; then
    echo "Downloading phpmyadmin from: https://files.phpmyadmin.net/phpMyAdmin/${PHPMYADMIN_VERSION}/phpMyAdmin-${PHPMYADMIN_VERSION}-english.tar.gz"
    curl -o /tmp/phpmyadmin.tar.gz -fSL "https://files.phpmyadmin.net/phpMyAdmin/${PHPMYADMIN_VERSION}/phpMyAdmin-${PHPMYADMIN_VERSION}-english.tar.gz"
    mkdir -p /tmp/phpmyadmin /var/phpmyadmin/ /var/phpmyadmin/tmp
    tar -xzf /tmp/phpmyadmin.tar.gz -C /tmp/phpmyadmin/
    cp -rf /tmp/phpmyadmin/phpMyAdmin-${PHPMYADMIN_VERSION}-english/* /var/phpmyadmin/
    rm -rf /tmp/phpmyadmin /tmp/phpmyadmin.tar.gz
    echo "done."

    # set blowfish_secret
    randomBlowfishSecret=$(openssl rand -base64 32)
    sed -e "s|cfg\['blowfish_secret'\] = ''|cfg['blowfish_secret'] = '$randomBlowfishSecret'|" /var/phpmyadmin/config.sample.inc.php >/var/phpmyadmin/config.inc.php

    # fix permissions for folders
    chown -R nobody:nobody /var/phpmyadmin
fi

# only run this code on first boot
if [ -f "/etc/nginx/nginx.tmpl" ]; then
    # Dockersize stuff
    dockerize -template /etc/nginx/nginx.tmpl >/etc/nginx/nginx.conf
    dockerize -template /etc/php7/conf.d/zzz_custom.tmpl >/etc/php7/conf.d/zzz_custom.ini

    # remove tmpl files
    rm /etc/nginx/nginx.tmpl /etc/php7/conf.d/zzz_custom.tmpl

    # set a MySQL Root password if not passed in
    if [[ -z "${MYSQL_ROOT_PASSWORD}" ]]; then
        MYSQL_ROOT_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
    fi

    echo "Setting up MySQL for first time... Root Password: $MYSQL_ROOT_PASSWORD"

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

    echo "done with firs time MySQL setup."

    {
        echo "Waiting for MySQL to be ready..."

        # wait until mysql is up and running
        while !(mysqladmin -uroot -p"$MYSQL_ROOT_PASSWORD" ping --silent); do
            echo "."
            sleep 1
        done

        echo "MYSQL Server Ready."

        if [ "${WORDPRESS_INSTALL}" = true ]; then
            WORDPRESS_VERSION=${WORDPRESS_VERSION:-latest}
        fi

        # download wordpress if a version is passed in
        if [ -n "${WORDPRESS_VERSION}" ]; then
            echo "Downloading WordPress $WORDPRESS_VERSION"
            wp core download --version=$WORDPRESS_VERSION --path=/var/www/ --force
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

            mkdir -p /var/www /tmp/site
            unzip -o /tmp/site.zip -d /tmp/site/

            # exclude files from the backup unzip
            if [ -n "${BACKUP_EXCLUDE}" ]; then
                cd /tmp/site
                rm -rf ${BACKUP_EXCLUDE}
            fi

            # move sql files to be imported into MySQL
            mv /tmp/site/*.sql /var/db/

            cp -rf /tmp/site/* /var/www/
            rm -rf /tmp/site.zip /tmp/site

            echo "done."
        fi

        # existing WordPress setup
        if [ -f /var/www/wp-config.php ]; then
            echo "Grabing WordPress variables for existing wp-config.php"

            MYSQL_DATABASE=$(wp config get DB_NAME --path=/var/www)
            MYSQL_USERNAME=$(wp config get DB_USER --path=/var/www)
            MYSQL_PASSWORD=$(wp config get DB_PASSWORD --path=/var/www)
            WORDPRESS_TBLPREFIX=$(wp config get table_prefix --path=/var/www)

            echo "done."

        # new wordpress setup
        elif [ -f /var/www/wp-config-sample.php ]; then
            echo "Setting up new wp-config.php"

            # create the config file from sample
            mv /var/www/wp-config-sample.php /var/www/wp-config.php

            MYSQL_DATABASE=${MYSQL_DATABASE:-wordpress}
            MYSQL_USERNAME=${MYSQL_USERNAME:-wordpress}

            # set config values
            wp config set DB_NAME $MYSQL_DATABASE --path=/var/www
            wp config set DB_USER $MYSQL_USERNAME --path=/var/www
            wp config set DB_PASSWORD $MYSQL_PASSWORD --path=/var/www
            wp config set DB_HOST $MYSQL_HOST --path=/var/www
            wp config set table_prefix $WORDPRESS_TBLPREFIX --path=/var/www
            wp config shuffle-salts --path=/var/www

            WORDPRESS_INSTALL=true

            echo "done."
        fi

        # if database isnt created yet, it needs to be installed
        if [ ! -d "/var/lib/mysql/$MYSQL_DATABASE" ] ; then
            WORDPRESS_INSTALL=true
        fi

        # create database if one was passed in
        if [ -n "${MYSQL_DATABASE}" ]; then
            echo "Setting up Database: $MYSQL_DATABASE (Username: $MYSQL_USERNAME, Password: $MYSQL_PASSWORD)..."

            # make sure database is setup
            /usr/bin/mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\`;GRANT ALL ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USERNAME'@'%' identified by '$MYSQL_PASSWORD' WITH GRANT OPTION;FLUSH PRIVILEGES;"

            echo "done."
        fi

        # import the .sql scripts if any
        for f in /var/db/*.sql; do
            echo "Importing .SQL file: $f"
            /usr/bin/mysql -u"$MYSQL_USERNAME" -p"$MYSQL_PASSWORD" $MYSQL_DATABASE <"$f"
            echo "SQL File Imported: $f"
            sleep 3
            rm "$f"
        done

        # import the cron scripts if any
        for f in /var/cron/*; do
            echo "Importing cron file: $f"
            crontab $f
            echo "done."
        done

        # install wordpress
        if [ "${WORDPRESS_INSTALL}" = true ]; then
            echo "Installing WordPress using WP CLI..."

            WORDPRESS_TITLE=${WORDPRESS_TITLE:-WordPress}
            WORDPRESS_ADMIN_USERNAME=${WORDPRESS_ADMIN_USERNAME:-admin}
            WORDPRESS_ADMIN_PASSWORD=${WORDPRESS_ADMIN_PASSWORD:-admin}
            WORDPRESS_ADMIN_EMAIL=${WORDPRESS_ADMIN_EMAIL:-"noemail@noemail.com"}

            wp core install --url=$WEBSITE_HOSTNAME --title=$WORDPRESS_TITLE --admin_user=$WORDPRESS_ADMIN_USERNAME --admin_password=$WORDPRESS_ADMIN_PASSWORD --admin_email=$WORDPRESS_ADMIN_EMAIL --skip-email --path=/var/www

            echo "done."
        fi

        # setup addtional WordPress stuff
        if [ -f /var/www/wp-config.php ]; then
            echo "Setting up wp-config..."

            if [ "$HTTP" == "https" ]; then
                wp config set FORCE_SSL_ADMIN true  --raw --path=/var/www
            else
                wp config set FORCE_SSL_ADMIN false  --raw --path=/var/www
            fi

            # remove port from website url
            COOKIE_DOMAIN="$(echo $WEBSITE_HOSTNAME | sed 's~:[[:digit:]]\+~~g')"

            wp config set COOKIE_DOMAIN $COOKIE_DOMAIN --path=/var/www

            wp option update siteurl "$URL" --path=/var/www
            wp option update home "$URL" --path=/var/www

            # make sure database is updated
            wp core update-db --path=/var/www

            if [ -n "${WORDPRESS_ADMIN_EMAIL}" ]; then
                wp option update admin_email $WORDPRESS_ADMIN_EMAIL --path=/var/www
            fi

            if [ -n "${WORDPRESS_INSTALL_THEME}" ]; then
                wp theme install $WORDPRESS_INSTALL_THEME --path=/var/www --activate
            fi

            if [ -n "${WORDPRESS_INSTALL_PLUGIN}" ]; then
                wp plugin install $WORDPRESS_INSTALL_PLUGIN --path=/var/www --activate
            fi

            if [ -n "${WORDPRESS_ACTIVATE_THEME}" ]; then
                wp theme activate $WORDPRESS_ACTIVATE_THEME --path=/var/www
            fi

            if [ -n "${WORDPRESS_ACTIVATE_PLUGIN}" ]; then
                wp plugin activate $WORDPRESS_ACTIVATE_PLUGIN --path=/var/www
            fi

            if [ -n "${WORDPRESS_DEACTIVATE_PLUGIN}" ]; then
                wp plugin deactivate $WORDPRESS_DEACTIVATE_PLUGIN --path=/var/www
            fi

            if [ -n "${FS_METHOD}" ]; then
                wp config set FS_METHOD $FS_METHOD --path=/var/www
            fi

            echo "done."
        fi

        # fix permissions for folders
        chown -R www-data:www-data /var/www
        chown -R mysql:mysql /var/lib/mysql
        chmod 777 /var/www

        chown -R www-data:www-data /var/lib/php7/session

        # tell nginx to reload config incase a conf is added
        nginx -s reload

        echo "Scripts all done. Site should be ready: $URL"

    } &

else
    echo "Scripts all done. Site should be ready: $URL"
fi

/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
