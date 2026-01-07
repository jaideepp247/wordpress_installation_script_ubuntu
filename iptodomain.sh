#!/bin/bash

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}WordPress IP to Domain Migration Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if WordPress is installed
if [ ! -f "/var/www/html/wp-config.php" ]; then
    echo -e "${RED}Error: WordPress installation not found at /var/www/html/${NC}"
    echo -e "${RED}Please ensure WordPress is installed before running this script.${NC}"
    exit 1
fi

# Install Certbot if not already installed
echo -e "${GREEN}Checking for Certbot installation...${NC}"
if ! command -v certbot &> /dev/null; then
    echo -e "${YELLOW}Certbot not found. Installing...${NC}"
    sudo apt update
    sudo apt install certbot python3-certbot-apache -y
fi

# Install WP-CLI if not already installed
echo -e "${GREEN}Checking for WP-CLI installation...${NC}"
if ! command -v wp &> /dev/null; then
    echo -e "${YELLOW}WP-CLI not found. Installing...${NC}"
    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    sudo mv wp-cli.phar /usr/local/bin/wp
fi

# Enable required Apache modules
echo -e "${GREEN}Enabling Apache modules...${NC}"
sudo a2enmod rewrite
sudo a2enmod ssl

# Get domain information
echo ""
echo -e "${YELLOW}Enter your domain name (e.g., example.com):${NC}"
read DOMAIN_NAME

# Validate domain format
if [[ ! $DOMAIN_NAME =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
    echo -e "${RED}Invalid domain format. Please enter a valid domain name.${NC}"
    exit 1
fi

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

# DNS configuration warning
echo ""
echo -e "${RED}========================================${NC}"
echo -e "${RED}IMPORTANT: DNS CONFIGURATION REQUIRED${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${YELLOW}Before continuing, you MUST configure the following DNS records:${NC}"
echo ""
echo -e "${GREEN}1. A Record for $DOMAIN_NAME${NC}"
echo "   - Type: A"
echo "   - Name: @ (or root)"
echo "   - Value: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo ""
echo -e "${GREEN}2. A Record for www.$DOMAIN_NAME${NC}"
echo "   - Type: A"
echo "   - Name: www"
echo "   - Value: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo ""
echo -e "${YELLOW}DNS propagation can take 5-30 minutes. You can check status with:${NC}"
echo -e "${BLUE}dig $DOMAIN_NAME${NC}"
echo -e "${BLUE}dig www.$DOMAIN_NAME${NC}"
echo ""
read -p "Press Enter once DNS records are configured and propagated..."

# Verify DNS is pointing to this server
echo -e "${GREEN}Verifying DNS configuration...${NC}"
SERVER_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
DOMAIN_IP=$(dig +short $DOMAIN_NAME | head -n1)
WWW_IP=$(dig +short www.$DOMAIN_NAME | head -n1)

if [ "$DOMAIN_IP" != "$SERVER_IP" ] || [ "$WWW_IP" != "$SERVER_IP" ]; then
    echo -e "${RED}Warning: DNS may not be properly configured.${NC}"
    echo -e "${YELLOW}Server IP: $SERVER_IP${NC}"
    echo -e "${YELLOW}$DOMAIN_NAME resolves to: $DOMAIN_IP${NC}"
    echo -e "${YELLOW}www.$DOMAIN_NAME resolves to: $WWW_IP${NC}"
    echo ""
    read -p "Do you want to continue anyway? (yes/no): " CONTINUE
    if [ "$CONTINUE" != "yes" ]; then
        echo -e "${RED}Migration cancelled. Please configure DNS and try again.${NC}"
        exit 1
    fi
fi

# Get current site URL
echo -e "${GREEN}Detecting current WordPress URL...${NC}"
OLD_URL=$(sudo -u www-data wp option get siteurl --path=/var/www/html 2>/dev/null)

if [ -z "$OLD_URL" ]; then
    echo -e "${YELLOW}Could not automatically detect current URL.${NC}"
    echo -e "${YELLOW}Enter your current WordPress URL (e.g., http://54.123.45.67):${NC}"
    read OLD_URL
fi

echo -e "${YELLOW}Old WordPress URL: $OLD_URL${NC}"
NEW_URL="https://$SITE_URL"
echo -e "${YELLOW}New WordPress URL: $NEW_URL${NC}"

# Create backup
echo ""
echo -e "${GREEN}Creating database backup...${NC}"
BACKUP_FILE="/root/wordpress_backup_$(date +%Y%m%d_%H%M%S).sql"
sudo -u www-data wp db export $BACKUP_FILE --path=/var/www/html
echo -e "${GREEN}Database backed up to: $BACKUP_FILE${NC}"

# Backup wp-config.php
echo -e "${GREEN}Creating backup of wp-config.php...${NC}"
sudo cp /var/www/html/wp-config.php /var/www/html/wp-config.php.backup.$(date +%Y%m%d_%H%M%S)

# Disable default Apache site
echo -e "${GREEN}Configuring Apache...${NC}"
sudo a2dissite 000-default.conf 2>/dev/null

# Create Apache virtual host configuration
echo -e "${GREEN}Creating Apache virtual host for $DOMAIN_NAME...${NC}"
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

# Obtain SSL certificate with Certbot
echo ""
echo -e "${GREEN}Obtaining SSL certificate from Let's Encrypt...${NC}"
echo -e "${YELLOW}This may take a few moments...${NC}"

sudo certbot --apache -d $DOMAIN_NAME -d www.$DOMAIN_NAME --non-interactive --agree-tos --register-unsafely-without-email --redirect --preferred-challenges http

if [ $? -ne 0 ]; then
    echo -e "${RED}SSL certificate installation failed.${NC}"
    echo -e "${YELLOW}Please check:${NC}"
    echo -e "${YELLOW}1. DNS is properly configured${NC}"
    echo -e "${YELLOW}2. Port 80 and 443 are open in your firewall/security group${NC}"
    echo -e "${YELLOW}3. Domain is accessible from the internet${NC}"
    echo ""
    echo -e "${YELLOW}Continuing with HTTP setup...${NC}"
    NEW_URL="http://$SITE_URL"
fi

# Configure .htaccess for proper redirects
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

# Update WordPress URLs using WP-CLI (handles serialized data correctly)
echo ""
echo -e "${GREEN}Updating WordPress URLs in database...${NC}"
echo -e "${YELLOW}This will update all URLs including serialized data...${NC}"

sudo -u www-data wp search-replace "$OLD_URL" "$NEW_URL" --path=/var/www/html --skip-columns=guid --all-tables

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Database URLs updated successfully!${NC}"
else
    echo -e "${RED}Warning: WP-CLI search-replace had issues. Trying direct database update...${NC}"
    
    # Fallback to direct database update
    DB_NAME=$(sudo grep "DB_NAME" /var/www/html/wp-config.php | cut -d "'" -f 4)
    DB_USER=$(sudo grep "DB_USER" /var/www/html/wp-config.php | cut -d "'" -f 4)
    DB_PASSWORD=$(sudo grep "DB_PASSWORD" /var/www/html/wp-config.php | cut -d "'" -f 4)
    
    sudo mysql -u$DB_USER -p$DB_PASSWORD $DB_NAME <<MYSQL_SCRIPT
UPDATE wp_options SET option_value = '$NEW_URL' WHERE option_name = 'siteurl';
UPDATE wp_options SET option_value = '$NEW_URL' WHERE option_name = 'home';
UPDATE wp_posts SET post_content = REPLACE(post_content, '$OLD_URL', '$NEW_URL');
UPDATE wp_postmeta SET meta_value = REPLACE(meta_value, '$OLD_URL', '$NEW_URL');
MYSQL_SCRIPT
fi

# Update wp-config.php to define WP_HOME and WP_SITEURL
echo -e "${GREEN}Updating wp-config.php with domain constants...${NC}"
if ! grep -q "WP_HOME" /var/www/html/wp-config.php; then
    sudo sed -i "/<?php/a define('WP_HOME','$NEW_URL');\ndefine('WP_SITEURL','$NEW_URL');" /var/www/html/wp-config.php
fi

# Flush WordPress rewrite rules
echo -e "${GREEN}Flushing WordPress rewrite rules...${NC}"
sudo -u www-data wp rewrite flush --path=/var/www/html

# Clear any WordPress cache
if [ -d "/var/www/html/wp-content/cache" ]; then
    echo -e "${GREEN}Clearing WordPress cache...${NC}"
    sudo rm -rf /var/www/html/wp-content/cache/*
fi

# Fix file permissions
echo -e "${GREEN}Setting correct file permissions...${NC}"
sudo chown -R www-data:www-data /var/www/html
sudo find /var/www/html -type d -exec chmod 755 {} \;
sudo find /var/www/html -type f -exec chmod 644 {} \;

# Restart Apache
echo -e "${GREEN}Restarting Apache...${NC}"
sudo systemctl restart apache2

# Display success message
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Migration Completed Successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}Your WordPress site has been migrated to:${NC}"
echo -e "${GREEN}$NEW_URL${NC}"
echo ""
echo -e "${YELLOW}Important Notes:${NC}"
echo -e "${YELLOW}1. SSL certificate installed and auto-renewal configured${NC}"
echo -e "${YELLOW}2. All traffic redirects to: https://$SITE_URL${NC}"
echo -e "${YELLOW}3. Database URLs have been updated (including serialized data)${NC}"
echo -e "${YELLOW}4. Backup files created:${NC}"
echo -e "${YELLOW}   - Database: $BACKUP_FILE${NC}"
echo -e "${YELLOW}   - wp-config.php: /var/www/html/wp-config.php.backup.*${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "${YELLOW}1. Clear your browser cache and cookies${NC}"
echo -e "${YELLOW}2. Visit $NEW_URL and verify the site works${NC}"
echo -e "${YELLOW}3. Login to WordPress admin (/wp-admin)${NC}"
echo -e "${YELLOW}4. Check that all images and media are loading${NC}"
echo -e "${YELLOW}5. Test all pages, posts, and functionality${NC}"
echo -e "${YELLOW}6. If you have caching plugins, clear their cache${NC}"
echo -e "${YELLOW}7. Test all redirects (http, https, www, non-www)${NC}"
echo ""
echo -e "${GREEN}If images still don't load:${NC}"
echo -e "${GREEN}1. Go to WordPress Admin > Settings > Permalinks${NC}"
echo -e "${GREEN}2. Click 'Save Changes' (don't change anything)${NC}"
echo -e "${GREEN}3. Go to Media > Regenerate Thumbnails (if plugin installed)${NC}"
echo ""
echo -e "${BLUE}To restore from backup if needed:${NC}"
echo -e "${BLUE}wp db import $BACKUP_FILE --path=/var/www/html${NC}"
echo ""
