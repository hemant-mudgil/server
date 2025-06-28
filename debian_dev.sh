#!/bin/bash

# === Update & upgrade ===
apt update -y
apt upgrade -y

# === Install essentials ===
apt install -y lsb-release curl wget gnupg ca-certificates apt-transport-https unzip apache2 mariadb-server openssh-server htop nano

# === Add Sury repo for PHP 8.3 ===
wget -qO /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
apt update -y

# === Install Python 3 ===
apt install -y python3 python3-pip

# === Install PHP 8.3 with all modules ===
apt install -y php8.3 php8.3-cli php8.3-common libapache2-mod-php8.3 \
php8.3-mysql php8.3-xml php8.3-mbstring php8.3-curl php8.3-zip php8.3-gd \
php8.3-intl php8.3-bcmath php8.3-soap php8.3-readline php8.3-opcache \
php8.3-imap php8.3-ldap php8.3-dev php8.3-fpm php8.3-phpdbg php8.3-sqlite3


# === Enable all useful Apache modules ===
a2enmod rewrite ssl headers deflate mime setenvif filter dir env status \
auth_basic authn_core authz_core autoindex proxy proxy_fcgi proxy_http \
expires cache cache_disk

# === Make sure readfile() etc are not disabled ===
sed -i 's/disable_functions = .*/disable_functions = /' /etc/php/8.3/apache2/php.ini

# === Allow .htaccess overrides ===
sed -i '/<Directory \/var\/www\/html>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf

# === Set directory index preference ===
sed -i 's/DirectoryIndex .*/DirectoryIndex index.php index.html/' /etc/apache2/mods-enabled/dir.conf

# === Enable SSH root login & password auth ===
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# === Create self-signed SSL cert ===
mkdir -p /etc/ssl/localcerts
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
 -keyout /etc/ssl/localcerts/apache-selfsigned.key \
 -out /etc/ssl/localcerts/apache-selfsigned.crt \
 -subj "/C=IN/ST=State/L=City/O=Dev/OU=Dev/CN=localhost"

# === Default SSL vhost ===
cat > /etc/apache2/sites-available/default-ssl.conf <<EOF
<IfModule mod_ssl.c>
<VirtualHost _default_:443>
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile      /etc/ssl/localcerts/apache-selfsigned.crt
    SSLCertificateKeyFile  /etc/ssl/localcerts/apache-selfsigned.key
</VirtualHost>
</IfModule>
EOF

a2ensite default-ssl

# === Download & install phpMyAdmin ===
mkdir -p /var/www/pma
wget https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-english.zip
unzip phpMyAdmin-5.2.1-english.zip
mv phpMyAdmin-5.2.1-english/* /var/www/pma/
rm -rf phpMyAdmin-5.2.1-english phpMyAdmin-5.2.1-english.zip

# === Apache config for /pma ===
cat > /etc/apache2/conf-available/pma.conf <<EOF
Alias /pma /var/www/pma

<Directory /var/www/pma>
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOF

a2enconf pma

# === phpMyAdmin auto-login as muser ===
cp /var/www/pma/config.sample.inc.php /var/www/pma/config.inc.php
cat >> /var/www/pma/config.inc.php <<EOF

\$cfg['Servers'][1]['auth_type'] = 'config';
\$cfg['Servers'][1]['user'] = 'muser';
\$cfg['Servers'][1]['password'] = 'muser';
EOF

chown www-data:www-data /var/www/pma/config.inc.php
chmod 640 /var/www/pma/config.inc.php
chown -R www-data:www-data /var/www/pma
chmod -R 755 /var/www/pma

# === Install Composer globally ===
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php
php -r "unlink('composer-setup.php');"
mv composer.phar /usr/local/bin/composer

# === Install WP-CLI globally ===
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# === Create MariaDB dev user ===
mariadb -e "CREATE USER 'muser'@'localhost' IDENTIFIED BY 'muser'; GRANT ALL PRIVILEGES ON *.* TO 'muser'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;"

# === Set root password to 'root' ===
echo "root:root" | chpasswd

# === Restart services ===
systemctl restart ssh
systemctl reload apache2
