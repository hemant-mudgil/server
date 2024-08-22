#!/bin/bash

# Ask for passwords and usernames
echo "Please enter the new Ubuntu root password:"
read -s ubuntu_root_password

echo "Please enter the MySQL root password:"
read -s mysql_root_password

echo "Please enter the MySQL username:"
read mysql_username

echo "Please enter the MySQL password for user '$mysql_username':"
read -s mysql_password

# Update Ubuntu root password
echo "Changing the Ubuntu root password..."
echo "root:$ubuntu_root_password" | chpasswd

# Update system
apt update && apt upgrade -y

# Disable the firewall initially
ufw disable

# Set PHP version
php_version=8.3

# Install Apache, MySQL, PHP, and other LAMP stack components
apt install lsb-release ca-certificates apt-transport-https software-properties-common gnupg unzip curl apache2 mysql-server redis-server memcached php$php_version libapache2-mod-php$php_version php$php_version-mysql php$php_version-cli php$php_version-mbstring php$php_version-xml php$php_version-curl php$php_version-zip php$php_version-gd php$php_version-imagick php$php_version-mongodb php$php_version-redis php$php_version-memcached php$php_version-gettext -y

# Array of services to start and enable
services=("apache2" "mysql" "redis-server" "ssh")

# Loop through each service, start it, enable it, and check its status
for service in "${services[@]}"; do
    systemctl start $service
    systemctl enable $service
    #systemctl status $service || echo "$service failed to start."
done

# Remove the /etc/ssh/sshd_config.d/60-cloudimg-settings.conf file if it exists
if [ -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf ]; then
    rm /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
    echo "Removed /etc/ssh/sshd_config.d/60-cloudimg-settings.conf"
else
    echo "/etc/ssh/sshd_config.d/60-cloudimg-settings.conf does not exist"
fi

# Configure SSH settings
# Enable SSH password authentication
if grep -q '^PasswordAuthentication' /etc/ssh/sshd_config; then
    sed -i '/^PasswordAuthentication/c\PasswordAuthentication yes' /etc/ssh/sshd_config
else
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
fi

# Allow SSH login as root and enable password authentication
if grep -q '^PermitRootLogin' /etc/ssh/sshd_config; then
    sed -i '/^PermitRootLogin/c\PermitRootLogin yes' /etc/ssh/sshd_config
else
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
fi

# Set MaxAuthTries to 3
if grep -q '^MaxAuthTries' /etc/ssh/sshd_config; then
    sed -i '/^MaxAuthTries/c\MaxAuthTries 3' /etc/ssh/sshd_config
else
    echo 'MaxAuthTries 3' >> /etc/ssh/sshd_config
fi

# for mysql left ram consumption, you can remove this if you have plenty of ram
bash -c 'cat <<EOF >> /etc/mysql/my.cnf
[mysqld]
performance_schema = OFF
EOF'

# Restart SSH service
systemctl reload sshd

# Secure MySQL installation and set root password
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$mysql_root_password'; FLUSH PRIVILEGES;"

# Add new MySQL user
mysql -e "CREATE USER '$mysql_username'@'localhost' IDENTIFIED WITH mysql_native_password BY '$mysql_password'; GRANT ALL PRIVILEGES ON *.* TO '$mysql_username'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;"

# Enable mod_rewrite and mod_php
a2enmod rewrite
a2enmod php$php_version

# Set PHP file to be executed first
sed -i 's/index.php index.html/index.php index.html index.htm/g' /etc/apache2/mods-enabled/dir.conf

# Enable .htaccess support
sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
sed -i 's/DirectoryIndex .*/DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm/g' /etc/apache2/mods-enabled/dir.conf

# Set PHP memory limit to 256MB and execution time to 120 seconds
sed -i 's/memory_limit = .*/memory_limit = 256M/' /etc/php/$php_version/apache2/php.ini
sed -i 's/max_execution_time = .*/max_execution_time = 120/' /etc/php/$php_version/apache2/php.ini

# Set user and group ownership of HTML files to 'pc' user and group
chown -R pc:pc /var/www/html

# Adjust permissions of HTML files
chmod -R 755 /var/www/html

# Restart Apache server
systemctl restart apache2

# Install Python 3, pip, and necessary Python packages
apt install python3 python3-pip python3-venv -y
pip3 install numpy pandas matplotlib requests beautifulsoup4 flask django

# Install MongoDB
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor

echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list

apt update
apt install mongodb-org -y

systemctl start mongod

# Configure MongoDB to listen on all network interfaces and disable SSL encryption
sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf
sed -i '/#  ssl:/,+5 s/^/#/' /etc/mongod.conf

# Restart MongoDB service
systemctl restart mongod

# Install MongoDB Compass
wget https://downloads.mongodb.com/compass/mongodb-compass_1.26.1_amd64.deb
dpkg -i mongodb-compass_1.26.1_amd64.deb
rm mongodb-compass_1.26.1_amd64.deb

# Install Composer
EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
    >&2 echo 'ERROR: Invalid installer checksum'
    rm composer-setup.php
    exit 1
fi

php composer-setup.php --quiet
RESULT=$?
rm composer-setup.php
mv composer.phar /usr/local/bin/composer

# Set PHP garbage collection probability for clearing garbage periodically
sed -i 's/;gc_probability = .*/gc_probability = 1/' /etc/php/$php_version/apache2/php.ini
sed -i 's/;gc_divisor = .*/gc_divisor = 100/' /etc/php/$php_version/apache2/php.ini

# Download and set up phpMyAdmin
mkdir -p /var/www/html/pma && \
wget https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-english.zip && \
unzip phpMyAdmin-5.2.1-english.zip && \
mv phpMyAdmin-5.2.1-english/* /var/www/html/pma/ && \
rm -rf phpMyAdmin-5.2.1-english phpMyAdmin-5.2.1-english.zip

# Download and install Cloudflared package
CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
CLOUDFLARED_DEB="cloudflared-linux-amd64.deb"

echo "Downloading cloudflared package..."
if wget -O $CLOUDFLARED_DEB $CLOUDFLARED_URL; then
    echo "Download successful, installing cloudflared..."
    dpkg -i $CLOUDFLARED_DEB
    rm $CLOUDFLARED_DEB
else
    echo "Failed to download cloudflared package. Exiting."
    exit 1
fi

# Enable UFW and allow necessary services
ufw enable
ufw allow in "Apache"
ufw allow ssh
ufw allow ftp
ufw allow mail
ufw allow smtp
ufw allow 443/tcp  # For SSL/TLS traffic

# Install Fail2Ban
apt install fail2ban -y
systemctl enable fail2ban
systemctl start fail2ban

echo "Installation complete!"

reboot
