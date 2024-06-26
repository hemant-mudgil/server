#!/bin/bash

# Update and upgrade system packages
apt update -y && apt upgrade -y

# Install required packages
apt install -y lsb-release ca-certificates apt-transport-https software-properties-common gnupg curl unzip apache2 mariadb-server redis python3 build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev wget openssh-server php php-common libapache2-mod-php php-cli php-common php-mysql php-xml php-mbstring php-curl php-json php-mongodb memcached php-memcached

# Array of services to start and enable
services=("apache2" "mariadb" "redis-server" "ssh")

# Loop through each service, start it, enable it, and check its status
for service in "${services[@]}"; do
    sudo systemctl start $service
    sudo systemctl enable $service
    #sudo systemctl status $service
done

# Enable SSH password authentication
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config

# Download and install Composer
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" && \
php -r "if (hash_file('sha384', 'composer-setup.php') === 'dac665fdc30fdd8ec78b38b9800061b4150413ff2e3b6f88543c636f7cd84f6db9189d43a81e5503cda447da73c7e5b6') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;" && \
php composer-setup.php && \
php -r "unlink('composer-setup.php');"
mv composer.phar /usr/local/bin/composer

# Directory containing SSH configuration files
ssh_config_dir="/etc/ssh/sshd_config.d"

# Check if directory exists and contains files
if [ -d "$ssh_config_dir" ] && [ "$(ls -A $ssh_config_dir)" ]; then
    echo "Configuration files found in $ssh_config_dir. Deleting them..."
    sudo rm -f $ssh_config_dir/*
    echo "All configuration files in $ssh_config_dir have been deleted."
else
    echo "No configuration files found in $ssh_config_dir."
fi

# Allow .htaccess overrides in Apache configuration
sed -i '/<Directory \/var\/www\/html>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
sed -i 's/DirectoryIndex .*/DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm/g' /etc/apache2/mods-enabled/dir.conf

# Allow SSH login as root and enable password authentication
sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config

# Download and set up phpMyAdmin
mkdir -p /var/www/html/pma && \
wget https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-english.zip && \
unzip phpMyAdmin-5.2.1-english.zip && \
mv phpMyAdmin-5.2.1-english/* /var/www/html/pma/ && \
rm -rf phpMyAdmin-5.2.1-english phpMyAdmin-5.2.1-english.zip

# Set correct permissions for /var/www/html
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# Enable SSH password authentication
systemctl enable ssh
service ssh reload
#systemctl reload sshd

# Open port for Apache in UFW
ufw allow 'Apache'

# Create MariaDB user and grant privileges
mariadb -e "CREATE USER 'muser'@'localhost' IDENTIFIED BY 'muser'; GRANT ALL PRIVILEGES ON *.* TO 'muser'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;"

# Download cloudflared package
CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
CLOUDFLARED_DEB="cloudflared-linux-amd64.deb"

echo "Downloading cloudflared package..."
if wget -O $CLOUDFLARED_DEB $CLOUDFLARED_URL; then
    echo "Download successful, installing cloudflared..."
    sudo dpkg -i $CLOUDFLARED_DEB
    rm $CLOUDFLARED_DEB
else
    echo "Failed to download cloudflared package. Exiting."
    exit 1
fi

sudo ufw allow in "Apache"

# Prompt for setting root password
passwd

# Reboot the system
reboot
