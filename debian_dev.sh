#!/bin/bash

# === Update & upgrade ===
apt update -y
apt upgrade -y

# === Install essentials ===
apt install -y lsb-release ca-certificates apt-transport-https software-properties-common gnupg curl unzip apache2 mariadb-server php unzip wget openssh-server

# === Add Sury repo for PHP 8.3 ===
wget -qO /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
apt update -y

# === Install PHP 8.3 and essential extensions ===
apt install -y php8.3 php8.3-cli php8.3-common libapache2-mod-php8.3 \
php8.3-mysql php8.3-xml php8.3-mbstring php8.3-curl php8.3-zip php8.3-gd php8.3-intl php8.3-bcmath php8.3-soap php8.3-readline

# === Ensure readfile() and other functions are not disabled ===
sed -i 's/disable_functions = .*/disable_functions = /' /etc/php/8.3/apache2/php.ini

# === Enable all default Apache modules ===
a2enmod rewrite
a2enmod ssl
a2enmod headers
a2enmod deflate
a2enmod mime
a2enmod setenvif
a2enmod filter
a2enmod dir
a2enmod env
a2enmod status
a2enmod auth_basic
a2enmod authn_core
a2enmod authz_core
a2enmod autoindex

systemctl reload apache2

# === Allow .htaccess overrides ===
sed -i '/<Directory \/var\/www\/html>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf

# === Set directory index preference ===
sed -i 's/DirectoryIndex .*/DirectoryIndex index.php index.html/' /etc/apache2/mods-enabled/dir.conf

# === Enable SSH root login & password auth ===
sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# === Download & install phpMyAdmin ===
mkdir -p /var/www/pma
wget https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-english.zip
unzip phpMyAdmin-5.2.1-english.zip
mv phpMyAdmin-5.2.1-english/* /var/www/pma/
rm -rf phpMyAdmin-5.2.1-english phpMyAdmin-5.2.1-english.zip

# === Add Apache config for /pma ===
cat > /etc/apache2/conf-available/pma.conf <<EOF
Alias /pma /var/www/pma

<Directory /var/www/pma>
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOF

a2enconf pma
systemctl reload apache2

# === phpMyAdmin auto-login as muser ===
cp /var/www/pma/config.sample.inc.php /var/www/pma/config.inc.php
cat >> /var/www/pma/config.inc.php <<EOF

\$cfg['Servers'][1]['auth_type'] = 'config';
\$cfg['Servers'][1]['user'] = 'muser';
\$cfg['Servers'][1]['password'] = 'muser';
EOF

chown www-data:www-data /var/www/pma/config.inc.php
chmod 640 /var/www/pma/config.inc.php

# === Permissions ===
chown -R www-data:www-data /var/www/pma
chmod -R 755 /var/www/pma

# === Install Composer globally ===
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php
php -r "unlink('composer-setup.php');"
mv composer.phar /usr/local/bin/composer

# === Create basic MariaDB dev user ===
mariadb -e "CREATE USER 'muser'@'localhost' IDENTIFIED BY 'muser'; GRANT ALL PRIVILEGES ON *.* TO 'muser'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;"

# === Set root password to 'root' ===
echo "root:root" | chpasswd

# === Restart SSH to apply settings ===
systemctl restart ssh

# === Reboot to finish ===
reboot
