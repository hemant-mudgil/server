#!/bin/bash

# Prompt for passwords and usernames
echo "Please enter the new Ubuntu root password:"
read -s ubuntu_root_password

echo "Please enter the new username:"
read new_username

echo "Please enter the password for the new user '$new_username':"
read -s new_user_password

echo "Please enter the MySQL root password:"
read -s mysql_root_password

echo "Please enter the MySQL username:"
read mysql_username

echo "Please enter the MySQL password for user '$mysql_username':"
read -s mysql_password

# Update Ubuntu root password
echo "Changing the Ubuntu root password..."
echo "root:$ubuntu_root_password" | chpasswd

# Create a new user and set a password
echo "Creating a new user '$new_username'..."
useradd -m -s /bin/bash $new_username
echo "$new_username:$new_user_password" | chpasswd

# Add new user to the sudo group
usermod -aG sudo $new_username

# Update system
apt update && apt upgrade -y

# Disable the firewall initially
ufw disable

# Set PHP version
php_version=8.3

# Add the PHP repository
add-apt-repository ppa:ondrej/php -y
apt update

# Install Apache, MySQL, PHP, and other LAMP stack components
#apt install lsb-release ca-certificates apt-transport-https software-properties-common gnupg unzip curl apache2 mariadb-server redis-server memcached php$php_version libapache2-mod-php$php_version php$php_version-mysql php$php_version-cli php$php_version-mbstring php$php_version-xml php$php_version-curl php$php_version-zip php$php_version-gd php-imagick php-mongodb php-redis php-memcached gettext -y
apt install ssh lsb-release ca-certificates apt-transport-https software-properties-common gnupg unzip curl apache2 mariadb-server redis-server memcached php$php_version libapache2-mod-php$php_version php$php_version-mysql php$php_version-cli php$php_version-mbstring php$php_version-xml php$php_version-curl php$php_version-zip php$php_version-gd php-imagick php-mongodb php-redis php-memcached gettext -y

# Array of services to start and enable
services=("apache2" "mysql" "redis-server" "ssh")

# Loop through each service, start it, enable it, and check its status
for service in "${services[@]}"; do
    systemctl start $service
    systemctl enable $service
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

# Configure MySQL to use the native password authentication plugin
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$mysql_root_password'; FLUSH PRIVILEGES;"

# Add new MySQL user
mysql -e "CREATE USER '$mysql_username'@'localhost' IDENTIFIED WITH mysql_native_password BY '$mysql_password'; GRANT ALL PRIVILEGES ON *.* TO '$mysql_username'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;"

#php_version=$(php -v | grep -oP '^PHP \K[0-9]+\.[0-9]+');

# Define PHP configuration path
php_ini_path="/etc/php/$php_version"

# Function to update or uncomment and modify a configuration setting in a php.ini file
update_or_add_setting() {
    local file="$1"
    local setting="$2"
    local value="$3"

    # Check for commented-out settings and uncomment if found
    if grep -q "^;$setting" "$file"; then
        # Uncomment and update existing setting
        sed -i "s/^;$setting/$setting/" "$file"
        sed -i "s/^$setting.*/$setting = $value/" "$file"
    elif grep -q "^$setting" "$file"; then
        # Update existing setting
        sed -i "s/^$setting.*/$setting = $value/" "$file"
    else
        # Add new setting at the end of the file
        echo "$setting = $value" >> "$file"
    fi
}

# Array of settings to update
settings=(
    "memory_limit=1G"
    "max_execution_time=300"
    "max_input_time=300"
    "post_max_size=1G"
    "upload_max_filesize=1G"
    "default_socket_timeout=30"
    "gc_probability=1"
    "gc_divisor=100"
    "opcache.enable=1"
    "opcache.enable_cli=1"
    "opcache.memory_consumption=512"
    "opcache.interned_strings_buffer=64"
    "opcache.max_accelerated_files=10000"
    "opcache.revalidate_freq=2"
    "opcache.save_comments=1"
    "opcache.fast_shutdown=1"
    "session.gc_maxlifetime=1440"  # 24 minutes
    "session.gc_probability=1"
    "session.gc_divisor=100"
)

# Update or add PHP configuration settings for Apache and CLI
for conf_file in apache2/php.ini cli/php.ini; do
    for setting in "${settings[@]}"; do
        key=$(echo "$setting" | cut -d= -f1)
        value=$(echo "$setting" | cut -d= -f2-)
        update_or_add_setting "$php_ini_path/$conf_file" "$key" "$value"
    done
done

# Enable mod_rewrite and mod_php
a2enmod rewrite
a2enmod php$php_version

# Set PHP file to be executed first
sed -i 's/index.php index.html/index.php index.html index.htm/g' /etc/apache2/mods-enabled/dir.conf

# Enable .htaccess support
sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
sed -i 's/DirectoryIndex .*/DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm/g' /etc/apache2/mods-enabled/dir.conf

# Set user and group ownership of HTML files to the new user
chown -R $new_username:$new_username /var/www/html

# Adjust permissions of HTML files
chmod -R 755 /var/www/html

# Restart Apache server
systemctl restart apache2

# Install Python 3, pip, and necessary Python packages
apt install python3 python3-pip python3-venv -y
pip3 install numpy pandas matplotlib requests beautifulsoup4 flask django

# Install MongoDB
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
   sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg \
   --dearmor
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
sudo apt-get update
sudo apt-get install -y mongodb-org
sudo systemctl start mongod
sudo systemctl daemon-reload
sudo systemctl status mongod
sudo systemctl enable mongod

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

# Download and set up phpMyAdmin
mkdir -p /var/www/html/pma && \
wget https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-english.zip && \
unzip phpMyAdmin-5.2.1-english.zip && \
mv phpMyAdmin-5.2.1-english/* /var/www/html/pma && \
chown -R www-data:www-data /var/www/html/pma && \
chmod -R 755 /var/www/html/pma

rm -rf phpMyAdmin-5.2.1-english phpMyAdmin-5.2.1-english.zip

# Download and install Cloudflared
CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
wget $CLOUDFLARED_URL
dpkg -i cloudflared-linux-amd64.deb
rm cloudflared-linux-amd64.deb


# Enable mod_security and mod_ssl
a2enmod security2
a2enmod ssl

# Configure SSL and enable the default SSL site
a2ensite default-ssl

# Restart Apache server to apply changes
systemctl restart apache2

# Enable firewall, set default deny, and allow necessary ports
ufw default deny
ufw allow 22
ufw allow 80
ufw allow 443
ufw enable

# Enable Cloudflare Turnstile
# Please follow specific Cloudflare Turnstile installation instructions here

echo "Setup complete!"
reboot
