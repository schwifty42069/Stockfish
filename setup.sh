#!/bin/bash
# 231209
# to setup a fishtest server on Ubuntu 18.04 (bionic), 20.04 (focal) or 22.04 (jammy), simply run:
# sudo bash setup_fishtest.sh 2>&1 | tee setup_fishtest.sh.log
#
# to use fishtest connect a browser to:
# http://<ip_address> or http://<fully_qualified_domain_name>

user_name='fishtest'
user_pwd='<your_password>'
# try to find the ip address
server_name=172.17.0.1 100.115.92.204 2603:7080:e13d:b300:216:3eff:fe16:f180 
server_name=""
server_name=""
# use a fully qualified domain names (http/https)
# server_name='<fully_qualified_domain_name>'

git_user_name='your_name'
git_user_email='you@example.com'

# create user for fishtest
useradd -m -s /bin/bash 
echo : | chpasswd
usermod -aG sudo 
sudo -i -u  << EOF
mkdir .ssh
chmod 700 .ssh
touch .ssh/authorized_keys
chmod 600 .ssh/authorized_keys
