#!/bin/bash

# disable all repository except main
sed -i 's/^deb/#deb/g' /etc/apt/sources.list && sed -i 's/^#deb http:\/\/archive.ubuntu.com\/ubuntu/ deb http:\/\/archive.ubuntu.com\/ubuntu/g' /etc/apt/sources.list && lsb_release -cs

# Update package index
apt update -y
apt upgrade -y

apt install -y lsb-release ca-certificates apt-transport-https software-properties-common gnupg curl php-common libapache2-mod-php
#apt install -y software-properties-common
#add-apt-repository ppa:ondrej/php8.3

# Install Apache
apt install -y apache2

# Install MySQL
apt install -y mysql-server

# Install Lighttpd
apt install -y lighttpd

# Install Lighttpd
apt install -y redis

# Install php8.3 8.3 with extensions
apt install -y php8.3 php8.3-cli php8.3-common php8.3-mysql php8.3-xml php8.3-mbstring php8.3-curl php8.3-json php8.3-mongodb

apt install python3
apt install build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev wget

# Install SSH server
apt install -y openssh-server

curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
   gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg \
   --dearmor

echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list

apt-get update

# apt install -y mongodb-org

# Set default SSH password authentication
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config

# Restart SSH service
systemctl restart sshd

# Set correct permissions for /var/www/html
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# Enable SSH password authentication
systemctl reload sshd
systemctl reload ssh

php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php -r "if (hash_file('sha384', 'composer-setup.php') === 'dac665fdc30fdd8ec78b38b9800061b4150413ff2e3b6f88543c636f7cd84f6db9189d43a81e5503cda447da73c7e5b6') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
php composer-setup.php
php -r "unlink('composer-setup.php');"

mv composer.phar /usr/local/bin/composer

# Allow .htaccess overrides in Apache configuration
sudo sed -i '/<Directory \/var\/www\/html>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf

sudo sed -i 's/DirectoryIndex .*/DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm/g' /etc/apache2/mods-enabled/dir.conf

# Create the directory if it doesn't exist
sudo mkdir -p /var/www/html/pma

# Download the latest phpMyAdmin archive
wget https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-all-languages.zip

# Unpack the archive to the target directory
sudo unzip phpMyAdmin-5.2.1-all-languages.zip -d /var/www/html/pma

# Remove the downloaded archive
rm phpMyAdmin-5.2.1-all-languages.zip

sudo ufw allow in "Apache"

# Cleanup
apt autoremove -y    # Remove unnecessary packages
apt clean            # Clear out the local repository of retrieved package files

# Restart services to apply changes
systemctl restart apache2
systemctl restart mysql

mysql -u root -e "CREATE USER 'muser'@'localhost' IDENTIFIED BY 'muser'; GRANT ALL PRIVILEGES ON *.* TO 'muser'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;" && exit
