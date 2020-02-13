#!/bin/bash

clear

################################################################################################
#Insert information
################################################################################################
username=$1
password=$2
site=$3
server=$4
passmysql=$5

#read -p "Enter username : " username
#read -p "Enter password : " password
#read -p "Enter le nom de votre site : " site
#read -p "Enter ServerName (exemple.com) : " server
#read -p "Enter MySQl root password : " passmysql
################################################################################################
#Update system
################################################################################################

sudo -s

apt-get update -y
apt-get upgrade -y

###############################################################################################
#Install Apache2
###############################################################################################

apt-get install apache2 -y

###############################################################################################
#Install PHP 
###############################################################################################

apt-get install php-fpm php-mysql php-cli php-common php-mbstring php-gd php-intl php-xml php-zip php-imagick php-xsl php-curl php-imap php-zip php-soap php-bcmath php-redis -y
a2enmod proxy_fcgi setenvif headers rewrite expires deflate
a2enconf php7.2-fpm
systemctl restart apache2
systemctl reload apache2

###############################################################################################
#Add User
###############################################################################################

pass=$(perl -e 'print crypt($ARGV[0], "password")' $password)
useradd -m -p $pass $username
mkdir /home/$username/httpdocs
mkdir /home/$username/logs
chown $username:$username /home/$username/httpdocs

###############################################################################################
#Pool configuration
###############################################################################################

echo "[$site]
user = $username
group = $username
listen = /run/php/$site-php7.2-fpm.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 10
pm.start_servers = 5
pm.min_spare_servers = 2
pm.max_spare_servers = 5
pm.max_requests = 500" >> /etc/php/7.2/fpm/pool.d/$site.conf
service php7.2-fpm restart

###############################################################################################
#Apache2 configuration
###############################################################################################

echo "<VirtualHost *:80>
ServerName $server
ServerAlias www.$server
DocumentRoot /home/$username/httpdocs
ErrorLog /home/$username/logs/error.log
CustomLog /home/$username/logs/access.log combined
ProxyPassMatch \"^/(.*\.php(/.*)?)$\" \"unix:/var/run/php/$site-php7.2-fpm.sock|fcgi://localhost/home/$username/httpdocs\"
<Directory />
Options Indexes FollowSymLinks
AllowOverride All
Require all granted
</Directory>
</VirtualHost>" >> /etc/apache2/sites-available/$site.conf
a2ensite $site.conf
service apache2 restart

###############################################################################################
#Install and secure Mysql 
###############################################################################################

apt-get install mysql-server -y
mysql -u root <<-EOF
update mysql.user
    set authentication_string=PASSWORD('$passmysql'), plugin="mysql_native_password"
    where User='root' and Host='localhost';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
service mysql restart

###############################################################################################
#install certbot for SSL
###############################################################################################

add-apt-repository ppa:certbot/certbot -y
apt install python-certbot-apache -y
#certbot --apache -d $server -d www.$server
#certbot renew --dry-run

###############################################################################################
#Install ClamAV
###############################################################################################

apt-get install clamav clamav-daemon clamav-freshclam -y
systemctl stop clamav-freshclam
freshclam
systemctl start clamav-freshclam

###############################################################################################
#Install Fail2ban
###############################################################################################

apt-get install fail2ban
systemctl start fail2ban
systemctl enable fail2ban
echo "[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime  = 600" >> /etc/fail2ban/jail.local
systemctl restart fail2ban

###############################################################################################
#index.php
###############################################################################################

echo "<?php
phpinfo();
?>" >> /home/$username/httpdocs/index.php