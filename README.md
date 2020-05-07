# PHP/MySQL Development Web Server

Basic web server designed for DEVELOPMENT, not PRODUCTION.

This one container setups [MariaDB](https://mariadb.com/) (MySQL), [NGINX](https://www.nginx.com/), [PHP7](https://php.net), [PHPMyAdmin](https://github.com/phpmyadmin/phpmyadmin)

### Notes

\*.conf files within the root www folder will automatically be included in ngnix. These files can extend the site settings.

\*.sql files within the root are executed after mysql database setup. These files are used to restore a database to the server.

## Environment Variables:

- **WEBSITE_HOSTNAME**: The website URL, example: website.test
- **HTTP**: http or https. Default: http
- **MYSQL_ROOT_PASSWORD**: Root password for MySQL server. Optional. If not supplied, random password is created.
- **PHPMYADMIN_VERSION**: Version of PHPMyAdmin to install. Optional. If not supplied, its not installed.
- **WORDPRESS_VERSION**: Version of Wordpress to install to root www folder. If not supplied, its not installed.
- **WORDPRESS_TBLPREFIX**: Table prefix to use from wp_config.php. Used to automatically update the website url in the "options" table.
- **BACKUP_SITE_DOWNLOAD**: ZIP Folder to download and extract to /var/www folder.
- **BACKUP_USERNAME**: Optional. Username to connect to \$BACKUP_SITE_DOWNLOAD that is secured via http authentication.
- **BACKUP_PASSWORD**: Optional. Password to connect to \$BACKUP_SITE_DOWNLOAD that is secured via http authentication.
- **BACKUP_EXCLUDE**: Files to not extract from the site download zip.
- **MYSQL_DATABASE**: Database name to create in MySQL. If importing from a ZIP that contains wp_config.php, this is pulled from the config file.
- **MYSQL_USERNAME**: Username to create for the MySQL Database. If importing from a ZIP that contains wp_config.php, this is pulled from the config file.
- **MYSQL_PASSWORD**: Password to create for the MySQL Database. If importing from a ZIP that contains wp_config.php, this is pulled from the config file.
- **WORDPRESS_INSTALL_CLI**: Install WordPress via CLI. Addtional Options:
  - **WORDPRESS_TITLE**: The site Title. Optional.
  - **WORDPRESS_ADMIN_USERNAME**: Installs WordPress using CLI and setups the admin account username.
  - **WORDPRESS_ADMIN_PASSWORD**: Installs WordPress using CLI and setups the admin account username. WORDPRESS_SETUP_USERNAME is required.
  - **WORDPRESS_ADMIN_EMAIL**: Installs WordPress using CLI and setups the admin account username. WORDPRESS_SETUP_USERNAME is required.
  - **WORDPRESS_INSTALL_THEME**: Theme name to activate upon setup.
  - **WORDPRESS_INSTALL_PLUGIN**: Plugin name to activate upon setup.

### BACKUP_SITE_DOWNLOAD

The environment variable **BACKUP_SITE_DOWNLOAD** will download a zip from a web url and extract it to the /var/www root website folder. If there is a .SQL in the root, the file will execute against the MySQL server. Any \*.conf files will be imported into the nginx file.

## License

The MIT License (MIT)

Copyright (c) 2019 Drew Gauderman

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
