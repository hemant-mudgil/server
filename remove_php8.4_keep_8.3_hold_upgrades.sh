#!/bin/bash

# Update the package list
sudo apt update

# Remove PHP 8.4 and its related packages
sudo apt purge -y php8.4 php8.4-*

# Ensure PHP 8.3 and Apache PHP module are installed
sudo apt install -y php8.3 libapache2-mod-php8.3 php8.3-common

# Set PHP 8.3 as the default version
sudo update-alternatives --set php /usr/bin/php8.3
sudo update-alternatives --set phpize /usr/bin/phpize8.3
sudo update-alternatives --set php-config /usr/bin/php-config8.3

# Put PHP 8.3 packages on hold to prevent upgrades
sudo apt-mark hold php8.3 php8.3-common libapache2-mod-php8.3 php8.3-cli

# Restart Apache to apply changes
sudo systemctl restart apache2

# Check PHP version
php -v

# Confirm the hold status
apt-mark showhold
