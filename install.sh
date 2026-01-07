#!/bin/bash

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Update system
echo -e "${GREEN}Updating system...${NC}"
sudo apt update && sudo apt upgrade -y

# Install Apache, MySQL, PHP and required extensions
echo -e "${GREEN}Installing Apache, MySQL, PHP, and Certbot...${NC}"
sudo apt install apache2 mysql-server php php-mysql libapache2-mod-php wget unzip certbot python3-certbot-apache -y

# Enable Apache modules
sudo a2enmod rewrite
sudo a2enmod ssl

# Get the database name, username, and password from user input
echo -e "${YELLOW}Enter the MySQL database name (e.g., wordpress):${NC}"
read DB_NAME
echo -e "${YELLOW}Enter the MySQL username (e.g., wordpressuser):${NC}"
read DB_USER
echo -e "${YELLOW}Enter the MySQL password for $DB_USER:${NC}"
read -s DB_PASSWORD
echo ""

# Secure MySQL installation
echo -e "${GREEN}Securing MySQL installation...${NC}"
sudo mysql_secure_installation

# Login to MySQL and create a new database and user
echo -e "${GREEN}Creating MySQL database and user...${NC}"
sudo mysql -e "CREATE DATABASE $DB_NAME;"
sudo mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Ask user for IP or Domain setup
echo ""
echo -e "${YELLOW}How do you want to setup WordPress?${NC}"
echo "1) Setup on IP address (HTTP only)"
echo "2) Setup on Domain with SSL certificate (HTTPS)"
read -p "Enter your choice (1 or 2): " SETUP_CHOICE

if [ "$SETUP_CHOICE" == "2" ]; then
    # Domain setup
    echo -e "${YELLOW}Enter your domain name (e.g., example.com):${NC}"
    read DOMAIN_NAME
    
    echo ""
    echo -e "${YELLOW}Choose domain configuration:${NC}"
    echo "1) Setup on domain.com (without www)"
    echo "2) Setup on www.domain.com (with www, all variants will redirect here)"
    read -p "Enter your choice (1 or 2): " DOMAIN_CHOICE
    
    if [ "$DOMAIN_CHOICE" == "2" ]; then
        SITE_URL="www.$DOMAIN_NAME"
        REDIRECT_DOMAIN="$DOMAIN_NAME"
    else
        SITE_URL="$DOMAIN_NAME"
        REDIRECT_DOMAIN="www.$DOMAIN_NAME"
    fi
    
    echo ""
    echo -e "${RED}IMPORTANT: Before continuing, make sure you have:${NC}"
    echo -e "${RED}1. Pointed $DOMAIN_NAME A record to this server's IP${NC}"
    echo -e "${RED}2. Pointed www.$DOMAIN_NAME A record to this server's IP${NC}"
    echo ""
    echo -e "${YELLOW}You can verify DNS propagation using: dig $DOMAIN_NAME${NC}"
    echo ""
    read -p "Press Enter once DNS records are configured and propagated..."
    
    # Remove default Apache site
    sudo a2dissite 000-default.conf
    
    # Create Apache virtual host configuration
    echo -e "${GREEN}Creating Apache virtual host...${NC}"
    sudo tee /etc/apache2/sites-available/$DOMAIN_NAME.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerName $SITE_URL
    ServerAlias $REDIRECT_DOMAIN
    ServerAdmin webmaster@$DOMAIN_NAME
    DocumentRoot /var/www/html
    
    <Directory /var/www/html>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN_NAME-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN_NAME-access.log combined
</VirtualHost>
EOF
    
    # Enable the new site
    sudo a2ensite $DOMAIN_NAME.conf
    
    # Reload Apache
    sudo systemctl reload apache2
    
    # Download WordPress
    echo -e "${GREEN}Downloading WordPress...${NC}"
    cd /var/www/html
    sudo rm -f index.html
    sudo wget https://wordpress.org/latest.tar.gz
    
    # Extract WordPress files directly into the /var/www/html directory
    echo -e "${GREEN}Extracting WordPress...${NC}"
    sudo tar -xvzf latest.tar.gz --strip-components=1
    sudo rm latest.tar.gz
    
    # Set correct permissions for WordPress files
    echo -e "${GREEN}Setting permissions...${NC}"
    sudo chown -R www-data:www-data /var/www/html
    sudo chmod -R 755 /var/www/html
    
    # Create wp-config.php from wp-config-sample.php
    echo -e "${GREEN}Creating wp-config.php...${NC}"
    sudo cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
    
    # Update wp-config.php with DB credentials
    echo -e "${GREEN}Updating wp-config.php with DB credentials...${NC}"
    sudo sed -i "s/database_name_here/$DB_NAME/" /var/www/html/wp-config.php
    sudo sed -i "s/username_here/$DB_USER/" /var/www/html/wp-config.php
    sudo sed -i "s/password_here/$DB_PASSWORD/" /var/www/html/wp-config.php
    
    # Obtain SSL certificate with Certbot
    echo -e "${GREEN}Obtaining SSL certificate from Let's Encrypt...${NC}"
    echo -e "${YELLOW}This may take a few moments...${NC}"
    
    if [ "$DOMAIN_CHOICE" == "2" ]; then
        # Redirect all to www version
        sudo certbot --apache -d $DOMAIN_NAME -d www.$DOMAIN_NAME --non-interactive --agree-tos --register-unsafely-without-email --redirect --preferred-challenges http
    else
        # Redirect all to non-www version
        sudo certbot --apache -d $DOMAIN_NAME -d www.$DOMAIN_NAME --non-interactive --agree-tos --register-unsafely-without-email --redirect --preferred-challenges http
    fi
    
    # Configure additional redirects in .htaccess
    echo -e "${GREEN}Configuring .htaccess for proper redirects...${NC}"
    sudo tee /var/www/html/.htaccess > /dev/null <<EOF
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /

# Force HTTPS and ${SITE_URL}
RewriteCond %{HTTPS} off [OR]
RewriteCond %{HTTP_HOST} !^${SITE_URL}$ [NC]
RewriteRule ^(.*)$ https://${SITE_URL}/\$1 [L,R=301]

# Standard WordPress rules
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
EOF
    
    sudo chown www-data:www-data /var/www/html/.htaccess
    
    # Restart Apache
    echo -e "${GREEN}Restarting Apache...${NC}"
    sudo systemctl restart apache2
    
    # Display success message
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}WordPress has been installed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${GREEN}Your WordPress site is now available at:${NC}"
    echo -e "${GREEN}https://$SITE_URL${NC}"
    echo ""
    echo -e "${YELLOW}SSL certificate has been installed and auto-renewal is configured.${NC}"
    echo -e "${YELLOW}All traffic will be redirected to: https://$SITE_URL${NC}"
    echo ""
    echo -e "${GREEN}Open your browser and visit https://$SITE_URL to finish the WordPress installation.${NC}"
    
else
    # IP setup (original functionality)
    # Download WordPress
    echo -e "${GREEN}Downloading WordPress...${NC}"
    cd /var/www/html
    sudo wget https://wordpress.org/latest.tar.gz
    
    # Extract WordPress files directly into the /var/www/html directory
    echo -e "${GREEN}Extracting WordPress...${NC}"
    sudo tar -xvzf latest.tar.gz --strip-components=1
    sudo rm latest.tar.gz
    
    # Set correct permissions for WordPress files
    echo -e "${GREEN}Setting permissions...${NC}"
    sudo chown -R www-data:www-data /var/www/html
    sudo chmod -R 755 /var/www/html
    
    # Create wp-config.php from wp-config-sample.php
    echo -e "${GREEN}Creating wp-config.php...${NC}"
    sudo cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
    
    # Update wp-config.php with DB credentials
    echo -e "${GREEN}Updating wp-config.php with DB credentials...${NC}"
    sudo sed -i "s/database_name_here/$DB_NAME/" /var/www/html/wp-config.php
    sudo sed -i "s/username_here/$DB_USER/" /var/www/html/wp-config.php
    sudo sed -i "s/password_here/$DB_PASSWORD/" /var/www/html/wp-config.php
    
    # Restart Apache to apply changes
    echo -e "${GREEN}Restarting Apache...${NC}"
    sudo systemctl restart apache2
    
    # Display success message with public IP
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}WordPress has been installed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # Get and display the EC2 instance public IP
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
    echo -e "${GREEN}Your server's public IP address is: $PUBLIC_IP${NC}"
    echo -e "${GREEN}Open your browser and visit http://$PUBLIC_IP to finish the WordPress installation.${NC}"
fi
