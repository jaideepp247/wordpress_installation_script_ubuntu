# WordPress Installation Script for Ubuntu EC2

This repository contains a simple bash script that automates the installation of WordPress on an Ubuntu EC2 instance. It installs the necessary components (Apache, MySQL, PHP), configures MySQL, downloads WordPress, and sets up everything with the correct permissions to run WordPress.

## Features

- Installs Apache, MySQL, PHP, and the required extensions
- Creates a MySQL database and user for WordPress
- Downloads and sets up WordPress
- Configures `wp-config.php` with the provided MySQL credentials
- Automatically sets the correct file permissions
- Restarts Apache for changes to take effect
- Provides the server's public IP to access the WordPress installation

## Prerequisites

- An Ubuntu EC2 instance
- Access to the terminal (SSH) on your EC2 instance
- A valid EC2 public IP

## How to Use

To run the script directly from your terminal, use the following command:

```bash
bash <(curl -s https://raw.githubusercontent.com/jaideepp247/wordpress_installation_script_ubuntu/main/install.sh)
```

This command does the following:

- Downloads the `install.sh` script from the repository
- Executes it in a bash shell

## Script Customization

During the script execution, you will be prompted to enter:

- **Database Name**: The name of the MySQL database for WordPress
- **Database Username**: The MySQL username for accessing the WordPress database
- **Database Password**: The password for the MySQL user

Once completed, you can access your WordPress site by visiting:

```
http://<your-public-ip>
```
