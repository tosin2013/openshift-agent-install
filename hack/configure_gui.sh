#!/bin/bash

# Install GNOME GUI
sudo yum groupinstall "Server with GUI" -y

# Enable EPEL repository 
#sudo yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm -y
sudo yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm -y

# Install xrdp and dependencies
sudo yum install tigervnc-server xrdp  firewalld -y

# Enable and start the xrdp service
sudo systemctl enable xrdp
sudo systemctl start xrdp

# Enable and start the firewalld service
sudo systemctl enable firewalld
sudo systemctl start firewalld

# Open firewall port for xrdp
sudo firewall-cmd --permanent --add-port=3389/tcp  
sudo firewall-cmd --reload

echo "GNOME GUI and xrdp have been installed and enabled."
echo "You can now connect to this system using Remote Desktop from another machine."

# optional 
curl -OL https://gist.githubusercontent.com/tosin2013/385054f345ff7129df6167631156fa2a/raw/b67866c8d0ec220c393ea83d2c7056f33c472e65/configure-sudo-user.sh
chmod +x configure-sudo-user.sh
./configure-sudo-user.sh