#!/bin/bash

# Install updates
yum update -y

# Install Apache
yum install -y httpd

# Start Apache web server
service httpd start

# Configure Apache web server to at each system boot
chkconfig httpd on

# Add user to apache group
usermod -a -G apache ec2-user

# Change the group ownership of /var/www and its contents to the apache group. 
chown -R ec2-user:apache /var/www

# To add group write permissions, change the directory permissions of /var/www 
# and all of it's subdirectories and files
sudo chmod 2775 /var/www
find /var/www -type d -exec sudo chmod 2775 {} \;
find /var/www -type f -exec sudo chmod 0664 {} \;

# Create a HTML file in Apache document root
echo "<h1>Congratulations! This instance created using custom AMI!</h1>" > /var/www/html/index.html