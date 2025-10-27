#!/bin/bash

#Install Nagios on Centos 7

sudo yum -y update
sudo yum -y install httpd httpd-tools php gcc glibc glibc-common gd gd-devel make net-snmp
sudo yum -y install wget unzip
sudo useradd nagios
sudo groupadd nagcmd
sudo usermod -G nagcmd nagios
sudo usermod -G nagcmd apache
sudo mkdir /root/nagios
cd /root/nagios
sudo wget https://assets.nagios.com/downloads/nagioscore/releases/nagios-4.3.4.tar.gz
sudo wget https://nagios-plugins.org/download/nagios-plugins-2.2.1.tar.gz
sudo tar -xvf  nagios-4.3.4.tar.gz
sudo tar -xvf nagios-plugins-2.2.1.tar.gz
cd nagios-4.3.4
./configure --with-command-group=nagcmd
make all
make install
make install-init
make install-commandmode
make install-config
make install-webconf
echo "Enter pasword for nagiosadmin user"
htpasswd -s -c /usr/local/nagios/etc/htpasswd.users nagiosadmin
systemctl start httpd.service
cd /root/nagios/nagios-plugins-2.2.1
./configure --with-nagios-user=nagios --with-nagios-group=nagios
make
make install
echo "checking configuration"
sleep 2s;
/usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg
sleep 3s;
systemctl enable nagios
systemctl enable httpd
systemctl start nagios.service
echo "Access Nagios on web Now"
