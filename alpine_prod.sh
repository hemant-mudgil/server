#!/bin/sh

# Prompt for passwords and usernames
echo "Please enter the new Alpine root password:"
read -s alpine_root_password

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

# Update Alpine root password
echo "Changing the Alpine root password..."
echo "root:$alpine_root_password" | chpasswd

# Create a new user and set a password
echo "Creating a new user '$new_username'..."
adduser -D -s /bin/sh $new_username
echo "$new_username:$new_user_password" | chpasswd

# Add new user to the wheel group (sudo equivalent in Alpine)
adduser $new_username wheel

# Update system and install necessary packages
apk update && apk upgrade

# Install required packages for LAMP stack
apk add apache2 mariadb mariadb-client php$php_version php$php_version-apache2 php$php_version-mysqli php$php_version-opcache php$php_version-session php$php_version-mbstring php$php_version-xml php$php_version-curl php$php_version-zip php$php_version-gd redis memcached gettext bash sudo

# Start and enable services
rc-update add apache2
rc-update add mariadb
rc-update add redis
rc-update add sshd

service apache2 start
service mariadb start
service redis start
service sshd start

# Secure MySQL installation (assuming it is a fresh install)
mysql_secure_installation <<EOF

y
$mysql_root_password
$mysql_root_password
y
y
y
y
EOF

# Configure MySQL to use the native password authentication plugin
mysql -u root -p"$mysql_root_password" -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$mysql_root_password'; FLUSH PRIVILEGES;"
mysql -u root -p"$mysql_root_password" -e "CREATE USER '$mysql_username'@'localhost' IDENTIFIED WITH mysql_native_password BY '$mysql_password'; GRANT ALL PRIVILEGES ON *.* TO '$mysql_username'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;"

# Configure PHP
# Set PHP memory limit to 1GB and execution time to 300 seconds
sed -i 's/memory_limit = .*/memory_limit = 1G/' /etc/php$php_version/php.ini
sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php$php_version/php.ini

# Enable OPCache and set optimal values
cat >> /etc/php$php_version/php.ini <<EOL

; Enable OPCache
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=512
opcache.interned_strings_buffer=64
opcache.max_accelerated_files=10000
opcache.revalidate_freq=2
opcache.save_comments=1
opcache.fast_shutdown=1
EOL

# Enable mod_rewrite in Apache
sed -i '/LoadModule rewrite_module/s/^#//' /etc/apache2/httpd.conf

# Set PHP file to be executed first
sed -i 's/index.html index.htm/index.php index.html index.htm/g' /etc/apache2/conf.d/dir.conf

# Enable .htaccess support
sed -i '/<Directory \/>/!b;n;c\    AllowOverride All' /etc/apache2/httpd.conf

# Set user and group ownership of HTML files to the new user
chown -R $new_username:$new_username /var/www/localhost/htdocs

# Adjust permissions of HTML files
chmod -R 755 /var/www/localhost/htdocs

# Restart Apache server
service apache2 restart

# Install Composer
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

# Install Python 3, pip, and necessary Python packages
apk add python3 py3-pip
pip3 install numpy pandas matplotlib requests beautifulsoup4 flask django

# Install MongoDB (Alpine does not have a direct package, so you may need to use a third-party or manual installation method)
# Assuming MongoDB is available via a third-party repository for Alpine:
# apk add mongodb mongodb-tools
# rc-update add mongodb
# service mongodb start

# Install Cloudflared (binary installation as there’s no package in Alpine)
CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
wget $CLOUDFLARED_URL -O /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared

# Enable mod_security and mod_ssl (requires additional modules and possible manual configuration in Alpine)
# For simplicity, these steps assume you can handle the module enablement in your specific use case.

# Enable firewall, set default deny, and allow necessary ports (using iptables in Alpine)
apk add iptables
iptables -P INPUT DROP
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
rc-update add iptables
service iptables save

# Enable SSH password authentication
sed -i '/^#PasswordAuthentication yes/s/^#//' /etc/ssh/sshd_config
sed -i '/^#PermitRootLogin yes/s/^#//' /etc/ssh/sshd_config
sed -i '/^#MaxAuthTries/c\MaxAuthTries 3' /etc/ssh/sshd_config
service sshd restart

echo "Setup complete!"
reboot
