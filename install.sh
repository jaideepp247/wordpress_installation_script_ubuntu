#!/bin/bash

# Update system
echo "Updating system..."
sudo apt update && sudo apt upgrade -y

# Install Apache, MySQL, PHP and required extensions
echo "Installing Apache, MySQL, and PHP..."
sudo apt install apache2 mysql-server php php-mysql libapache2-mod-php wget unzip -y

# Get the database name, username, and password from user input
echo "Enter the MySQL database name (e.g., wordpress):"
read DB_NAME

echo "Enter the MySQL username (e.g., wordpressuser):"
read DB_USER

echo "Enter the MySQL password for $DB_USER:"
read -s DB_PASSWORD

# Secure MySQL installation
echo "Securing MySQL installation..."
sudo mysql_secure_installation

# Login to MySQL and create a new database and user
echo "Creating MySQL database and user..."
sudo mysql -e "CREATE DATABASE $DB_NAME;"
sudo mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Download WordPress
echo "Downloading WordPress..."
cd /var/www/html
sudo wget https://wordpress.org/latest.tar.gz

# Extract WordPress files directly into the /var/www/html/wordpress directory
sudo tar -xvzf latest.tar.gz
sudo rm latest.tar.gz

# Set correct permissions for WordPress files
echo "Setting permissions..."
sudo chown -R www-data:www-data /var/www/html/wordpress
sudo chmod -R 755 /var/www/html/wordpress

# Create wp-config.php from wp-config-sample.php
echo "Creating wp-config.php..."
sudo cp /var/www/html/wordpress/wp-config-sample.php /var/www/html/wordpress/wp-config.php

# Update wp-config.php with DB credentials
echo "Updating wp-config.php with DB credentials..."
sudo sed -i "s/database_name_here/$DB_NAME/" /var/www/html/wordpress/wp-config.php
sudo sed -i "s/username_here/$DB_USER/" /var/www/html/wordpress/wp-config.php
sudo sed -i "s/password_here/$DB_PASSWORD/" /var/www/html/wordpress/wp-config.php

# Restart Apache to apply changes
echo "Restarting Apache..."
sudo systemctl restart apache2

# Display success message with public IP
echo "WordPress has been installed successfully!"
echo "You can now complete the setup by visiting your server's IP address."

# Get and display the EC2 instance public IP
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "Your server's public IP address is: $PUBLIC_IP"
echo "Open your browser and visit http://$PUBLIC_IP/wordpress to finish the WordPress installation."
