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
php=$6
webserver=$7
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
#Install Webserver apache2 or nginx
###############################################################################################

if [[ "$webserver" == "apache2" ]]; then
apt-get install apache2 -y
fi
if [[ "$webserver" == "nginx" ]]; then
apt-get install nginx -y
fi

###############################################################################################
#Install PHP according to version
###############################################################################################
add-apt-repository ppa:ondrej/php -y

if [[ "$php" == "7.1" ]]; then
        apt-get install php7.1-fpm php7.1-mysql php7.1-cli php7.1-common php7.1-mbstring php7.1-gd php7.1-intl php7.1-xml php7.1-zip php7.1-imagick php7.1-xsl php7.1-curl php7.1-imap php7.1-zip php7.1-soap php7.1-bcmath php7.1-redis -y

fi
if [[ "$php" == "7.2" ]]; then
        apt-get install php7.2-fpm php7.2-mysql php7.2-cli php7.2-common php7.2-mbstring php7.2-gd php7.2-intl php7.2-xml php7.2-zip php7.2-imagick php7.2-xsl php7.2-curl php7.2-imap php7.2-zip php7.2-soap php7.2-bcmath php7.2-redis -y
fi
if [[ "$php" == "7.3" ]]; then
        apt-get install php7.3-fpm php7.3-mysql php7.3-cli php7.3-common php7.3-mbstring php7.3-gd php7.3-intl php7.3-xml php7.3-zip php7.3-imagick php7.3-xsl php7.3-curl php7.3-imap php7.3-zip php7.3-soap php7.3-bcmath php7.3-redis -y

fi
if [[ "$php" == "7.4" ]]; then
        apt-get install php7.4-fpm php7.4-mysql php7.4-cli php7.4-common php7.4-mbstring php7.4-gd php7.4-intl php7.4-xml php7.4-zip php7.4-imagick php7.4-xsl php7.4-curl php7.4-imap php7.4-zip php7.4-soap php7.4-bcmath php7.4-redis -y

fi
if [[ "$webserver" == "apache2" ]]; then
a2enmod proxy_fcgi setenvif headers rewrite expires deflate
a2enconf php$php-fpm
systemctl restart apache2
systemctl reload apache2
fi

if [[ "$webserver" == "nginx" ]]; then
systemctl start php$php-fpm
systemctl enable php$php-fpm
systemctl reload nginx
fi
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
listen = /run/php/$site-php$php-fpm.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 10
pm.start_servers = 5
pm.min_spare_servers = 2
pm.max_spare_servers = 5
pm.max_requests = 500" >> /etc/php/$php/fpm/pool.d/$site.conf
service php$php-fpm restart

###############################################################################################
#Configure Webserver
###############################################################################################

#######################     APACHE2        ####################################################

if [[ "$webserver" == "apache2" ]]; then
echo "<VirtualHost *:80>
ServerName $server
ServerAlias www.$server
DocumentRoot /home/$username/httpdocs
ErrorLog /home/$username/logs/error.log
CustomLog /home/$username/logs/access.log combined
ProxyPassMatch \"^/(.*\.php(/.*)?)$\" \"unix:/var/run/php/$site-php$php-fpm.sock|fcgi://localhost/home/$username/httpdocs\"
<Directory />
Options Indexes FollowSymLinks
AllowOverride All
Require all granted
</Directory>
</VirtualHost>" >> /etc/apache2/sites-available/$site.conf
a2ensite $site.conf
service apache2 restart
fi

########################      NGINX     ######################################################

if [[ "$webserver" == "nginx" ]]; then
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
                fastcgi_pass unix:/var/run/php/$site-php$php-fpm.sock;
        }

        location ~ /\.ht {
                deny all;
        }
}" >> /etc/nginx/sites-available/$site
ln -s /etc/nginx/sites-available/$site /etc/nginx/sites-enabled/
unlink /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx
fi

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
if [[ "$webserver" == "apache2" ]]; then
apt-get install python-certbot-apache -y
fi
if [[ "$webserver" == "nginx" ]]; then
apt-get install python-certbot-nginx -y
fi
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

apt-get install fail2ban -y
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
#Install Git Composer
###############################################################################################

apt-get install git composer -y

###############################################################################################
#index.php
###############################################################################################

su $username

echo "<?php
phpinfo();
?>" >> /home/$username/httpdocs/index.php