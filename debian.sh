#!/bin/bash


# Update package index
apt update -y
apt upgrade -y

apt install -y lsb-release ca-certificates apt-transport-https software-properties-common gnupg curl unzip
#apt install -y software-properties-common
#add-apt-repository ppa:ondrej/php

# Install Apache
apt install -y apache2

# Install MySQL
apt install -y mariadb-server

# Install Lighttpd
apt install -y lighttpd

# Install Lighttpd
apt install -y redis

# Install php 8.3 with extensions
apt install -y php php-common libapache2-mod-php php php-cli php-common php-mysql php-xml php-mbstring php-curl php-json php-mongodb

apt install python3
apt install build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev wget

# Install SSH server
apt install -y openssh-server




# Set default SSH password authentication
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config

php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php -r "if (hash_file('sha384', 'composer-setup.php') === 'dac665fdc30fdd8ec78b38b9800061b4150413ff2e3b6f88543c636f7cd84f6db9189d43a81e5503cda447da73c7e5b6') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
php composer-setup.php
php -r "unlink('composer-setup.php');"

mv composer.phar /usr/local/bin/composer

# Allow .htaccess overrides in Apache configuration
sudo sed -i '/<Directory \/var\/www\/html>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf

sudo sed -i 's/DirectoryIndex .*/DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm/g' /etc/apache2/mods-enabled/dir.conf

https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-english.zip
unzip phpMyAdmin-5.2.1-english.zip
mv phpMyAdmin-5.2.1-english /var/www/html/pma
rm phpMyAdmin-5.2.1-english.zip


# Set correct permissions for /var/www/html
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# Enable SSH password authentication
systemctl reload sshd
systemctl reload ssh


sudo ufw allow in "Apache"

mariadb -e "CREATE USER 'muser'@'localhost' IDENTIFIED BY 'muser'; GRANT ALL PRIVILEGES ON *.* TO 'muser'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;" && exit
