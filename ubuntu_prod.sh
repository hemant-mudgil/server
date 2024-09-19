#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Exiting."
    exit 1
fi

# File to store the passwords and usernames
save_location="/root/credentials.txt"

# Function to generate a random password
generate_password() {
  local length=20
  local chars='A-Za-z0-9@#$'
  < /dev/urandom tr -dc "$chars" | head -c "$length"
}

# Default values
default_ubuntu_root_password=$(generate_password)
default_new_username="pc"
default_new_user_password=$(generate_password)
default_mysql_root_password=$(generate_password)
default_mysql_username="muser"
default_mysql_password=$(generate_password)

# Prompt for Ubuntu root password
echo "Please enter the new Ubuntu root password (default: $default_ubuntu_root_password):"
read -s ubuntu_root_password
ubuntu_root_password=${ubuntu_root_password:-$default_ubuntu_root_password}

# Prompt for new username
echo "Please enter the new username (default: $default_new_username):"
read new_username
new_username=${new_username:-$default_new_username}

# Prompt for new user password
echo "Please enter the password for the new user '$new_username' (default: $default_new_user_password):"
read -s new_user_password
new_user_password=${new_user_password:-$default_new_user_password}

# Prompt for MySQL root password
echo "Please enter the MySQL root password (default: $default_mysql_root_password):"
read -s mysql_root_password
mysql_root_password=${mysql_root_password:-$default_mysql_root_password}

# Prompt for MySQL username
echo "Please enter the MySQL username (default: $default_mysql_username):"
read mysql_username
mysql_username=${mysql_username:-$default_mysql_username}

# Prompt for MySQL user password
echo "Please enter the MySQL password for user '$mysql_username' (default: $default_mysql_password):"
read -s mysql_password
mysql_password=${mysql_password:-$default_mysql_password}

# Save all credentials to a JSON file
echo "Saving credentials to $save_location..."
cat <<EOL > "$save_location"
{
    "Ubuntu Root Password": "$ubuntu_root_password",
    "New Username": "$new_username",
    "New User Password": "$new_user_password",
    "MySQL Root Password": "$mysql_root_password",
    "MySQL Username": "$mysql_username",
    "MySQL User Password": "$mysql_password"
}
EOL

# Set permissions to protect the credentials file
chmod 600 "$save_location"

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

# Install necessary packages
apt install ssh nano sudo htop coreutils rsync wget lsb-release ca-certificates apt-transport-https software-properties-common gnupg ufw zip unzip curl python3 python3-pip python3-venv apache2 mariadb-server redis-server memcached libapache2-mod-security2 php$php_version libapache2-mod-php$php_version php$php_version-mysql php$php_version-cli php$php_version-mbstring php$php_version-xml php$php_version-curl php$php_version-zip php$php_version-gd php-imagick php-mongodb php-redis php-memcached libapache2-mpm-itk gettext -y

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

# Ensure MySQL is running
echo "Checking MySQL service status..."
if ! systemctl is-active --quiet mysql; then
    echo "MySQL is not running. Starting MySQL service..."
    systemctl start mysql
fi

# Configure MySQL to use the native password authentication plugin
#echo "Configuring MySQL root user..."
#mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$mysql_root_password'; FLUSH PRIVILEGES;"

# Add new MySQL user
#echo "Creating MySQL user '$mysql_username'..."
#mysql -e "CREATE USER '$mysql_username'@'localhost' IDENTIFIED WITH mysql_native_password BY '$mysql_password'; GRANT ALL PRIVILEGES ON *.* TO '$mysql_username'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;"

# Update root user password
echo "Configuring MariaDB root user..."
mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$mysql_root_password'); FLUSH PRIVILEGES;"

if [ $? -ne 0 ]; then
    echo "Failed to configure MariaDB root user. Please check MariaDB service and credentials."
    exit 1
fi

# Create new user and grant privileges
echo "Creating MariaDB user '$mysql_username'..."
mysql -e "CREATE USER '$mysql_username'@'localhost' IDENTIFIED BY '$mysql_password'; GRANT ALL PRIVILEGES ON *.* TO '$mysql_username'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;"

if [ $? -ne 0 ]; then
    echo "Failed to create MariaDB user. Please check MariaDB service and credentials."
    exit 1
fi

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
a2enmod mpm_itk
a2enmod php$php_version
a2enmod security2
a2enmod ssl
a2ensite default-ssl

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
# sudo systemctl status mongod
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

# Restart Apache server to apply changes
systemctl restart apache2

# Enable UFW and allow necessary services
ufw default deny
ufw allow in "Apache"
ufw allow ssh
ufw allow ftp
ufw allow mail
ufw allow smtp
ufw allow 443/tcp  # For SSL/TLS traffic
ufw enable

# Install Fail2Ban
apt install fail2ban -y
systemctl enable fail2ban
systemctl start fail2ban

echo "Installation complete!"

reboot
