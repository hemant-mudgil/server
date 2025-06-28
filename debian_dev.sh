#!/bin/bash
set -e

# === Update & install lsb-release first ===
apt update -y
apt upgrade -y
apt install -y lsb-release curl wget gnupg ca-certificates apt-transport-https unzip


# === Remove bad PHP list if exists ===
rm -f /etc/apt/sources.list.d/php.list

# === Add Sury PHP 8.3 repo ===
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
wget -qO /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
apt update -y

# === Install Apache, MariaDB, SSH, PHP 8.3 & modules ===
apt install -y apache2 mariadb-server openssh-server \
php8.3 php8.3-cli php8.3-common libapache2-mod-php8.3 \
php8.3-mysql php8.3-xml php8.3-mbstring php8.3-curl \
php8.3-zip php8.3-gd php8.3-intl php8.3-bcmath php8.3-soap php8.3-readline

# === Enable all default Apache modules ===
a2enmod rewrite ssl headers deflate mime setenvif filter dir env status auth_basic authn_core authz_core autoindex
systemctl reload apache2

# === Allow .htaccess & fix directory index ===
sed -i '/<Directory \/var\/www\/html>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
sed -i 's/DirectoryIndex .*/DirectoryIndex index.php index.html/' /etc/apache2/mods-enabled/dir.conf

# === Enable SSH root login & password auth ===
sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config || true
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config || true

# === Ensure readfile() etc. not disabled ===
sed -i 's/disable_functions = .*/disable_functions = /' /etc/php/8.3/apache2/php.ini || true

# === phpMyAdmin ===
mkdir -p /var/www/pma
wget -q https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-english.zip
unzip -q phpMyAdmin-5.2.1-english.zip
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
systemctl reload apache2

# === phpMyAdmin auto-login ===
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

# === Composer ===
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php
php -r "unlink('composer-setup.php');"
mv composer.phar /usr/local/bin/composer


# === Install WP-CLI globally ===
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# Verify installation
wp --info


# === MariaDB dev user ===
mariadb -e "CREATE USER IF NOT EXISTS 'muser'@'localhost' IDENTIFIED BY 'muser'; GRANT ALL PRIVILEGES ON *.* TO 'muser'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;"

# === Root password ===
echo "root:root" | chpasswd

# === Restart SSH ===
systemctl restart ssh
