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
#Install Nginx
###############################################################################################

apt-get install nginx -y

###############################################################################################
#Install PHP 
###############################################################################################

apt-get install php-fpm php-mysql php-cli php-common php-mbstring php-gd php-intl php-xml php-zip php-imagick php-xsl php-curl php-imap php-zip php-soap php-bcmath php-redis -y
systemctl start php7.2-fpm
systemctl enable php7.2-fpm
systemctl reload nginx

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
systemctl restart php7.2-fpm

###############################################################################################
#Apache2 configuration
###############################################################################################

echo "server {
        listen 80;
        root /home/$username/httpdocs;
        index index.php index.html index.htm index.nginx-debian.html;
        server_name $server www.$server;
        error_log  /home/$username/logs/error.log warn;
        access_log  /home/$username/logs/access.log;

        location / {
                try_files $uri $uri/ =404;
        }

        location ~ \.php$ {
                include snippets/fastcgi-php.conf;
                fastcgi_pass unix:/var/run/php/$site-php7.2-fpm.sock;
        }

        location ~ /\.ht {
                deny all;
        }
}" >> /etc/nginx/sites-available/$site
ln -s /etc/nginx/sites-available/$site /etc/nginx/sites-enabled/
unlink /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

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
#Install certbot for SSL
###############################################################################################

add-apt-repository ppa:certbot/certbot -y
apt install python-certbot-nginx -y
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