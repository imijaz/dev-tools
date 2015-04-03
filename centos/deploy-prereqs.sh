#!/usr/bin/env bash

# This will set a CentOS 6.6 box up to serve ozp applications (ozp-rest and front-end apps)

# - - - - - - - - - - - - - - -
# Installation
# - - - - - - - - - - - - - - -

# Add other repos
# Remi dependency on CEntOS 6
sudo rpm -Uvh http://dl.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm
sudo rpm -Uvh http://rpms.famillecollet.com/enterprise/remi-release-6.rpm

# elasticsearch
sudo rpm --import https://packages.elasticsearch.org/GPG-KEY-elasticsearch
# Add /etc/yum.repos.d/elasticsearch.repo containing (uncommented):

# [elasticsearch-1.4]
# name=Elasticsearch repository for 1.4.x packages
# baseurl=http://packages.elasticsearch.org/elasticsearch/1.4/centos
# gpgcheck=1
# gpgkey=http://packages.elasticsearch.org/GPG-KEY-elasticsearch
# enabled=1

# enable access to EPEL repo
sudo yum install epel-release

# remove old mysql
sudo yum remove mysql mysql-* -y

# Install packages
sudo yum --enablerepo=remi,remi-test install mysql mysql-server java-1.7.0-openjdk java-1.7.0-openjdk-devel tomcat elasticsearch nodejs npm nginx git -y

# Install newman (for adding test data)
sudo npm install -g newman


# - - - - - - - - - - - - - - -
# configure elastic search
# - - - - - - - - - - - - - - -
# change elastic search cluster name to ozpdemo04 in /etc/elasticsearch/elasticsearch.yml
# cluster.name: ozpdemo04
sudo sed -i '/#cluster.name: elasticsearch/c\cluster.name: ozpdemo04' /etc/elasticsearch/elasticsearch.yml

# create the temp directory used by elasticsearch and set permissiosn
sudo mkdir -p /usr/share/tomcat/temp
sudo chown -R tomcat /usr/share/tomcat/temp

# Start automatically on boot
sudo chkconfig --add elasticsearch

# Start elasticsearch service
sudo service elasticsearch start



# - - - - - - - - - - - - - - -
# configure MySQL 
# - - - - - - - - - - - - - - -
# set the root password ('password')
# remove Test database
# remove anonymous users
# disable root login remotely
sudo /etc/init.d/mysqld start

# TODO: this instead of mysql_secure_installation
DATABASE_PASS="password"
mysqladmin -u root password "$DATABASE_PASS"
mysql -u root -p"$DATABASE_PASS" -e "UPDATE mysql.user SET Password=PASSWORD('$DATABASE_PASS') WHERE User='root'"
mysql -u root -p"$DATABASE_PASS" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
mysql -u root -p"$DATABASE_PASS" -e "DELETE FROM mysql.user WHERE User=''"
mysql -u root -p"$DATABASE_PASS" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'"
mysql -u root -p"$DATABASE_PASS" -e "FLUSH PRIVILEGES"


/usr/bin/mysql_secure_installation

# start mysql on boot
sudo chkconfig --level 345 mysqld on

# create user ozp 
mysql -u root -ppassword -Bse "create user 'ozp'@'localhost' identified by 'ozp';"
# create ozp database
mysql -u root -ppassword -Bse "create database ozp;"
# grant ozp privs
mysql -u root -ppassword -Bse "grant all privileges on *.* to 'ozp'@'localhost';"


# - - - - - - - - - - - - - - -
# configure Tomcat 
# - - - - - - - - - - - - - - -

# TODO: start tomcat on boot

# create directory to hold images
sudo mkdir -p /usr/share/tomcat/images
sudo chown -R tomcat /usr/share/tomcat/images/

# increase tomcat memory from 128MB to 512MB in /etc/tomcat/tomcat.conf - look for JAVA_OPTS
# in the same file, append this to the same place (JAVA_OPTS): -XX:MaxPermSize=256m
# Line should read: JAVA_OPTS="-Xminf0.1 -Xmaxf0.3 -Xmx512m -XX:MaxPermSize=256m"
sudo sed -i '0,/^\(JAVA_OPTS=\).*/s//\1"-Xminf0.1 -Xmaxf0.3 -Xmx512m -XX:MaxPermSize=256m"/' /etc/tomcat/tomcat.conf

# add user 'tomcat' to /etc/tomcat/tomcat-users.xml (for logging into the tomcat web application manager)
sudo sed -i '/<tomcat-users>/a <user name="tomcat" password="password" roles="admin,manager-gui" />' tomcat-users.xml
# <user name="tomcat" password="password" roles="admin,manager-gui" />

# clone some stuff for setup files and whatnot
git clone https://github.com/ozone-development/dev-tools.git
git clone https://github.com/ozone-development/ozp-rest.git

# copy MarketplaceConfig.groovy to tomcat
sudo cp dev-tools/build-and-deploy/configs/ozp-rest/MarketplaceConfig.groovy /usr/share/tomcat/lib
sudo chown tomcat /usr/share/tomcat/lib/MarketplaceConfig.groovy

# copy OzoneConfig.properties to tomcat
sudo cp dev-tools/build-and-deploy/configs/ozp-rest/OzoneConfig.properties /usr/share/tomcat/lib
sudo chown tomcat /usr/share/tomcat/lib/OzoneConfig.properties

# copy the security plugin files to tomcat
sudo cp -r ozp-rest/grails-app/conf/ozone-security-beans /usr/share/tomcat/lib
sudo cp ozp-rest/grails-app/conf/SecurityContext.xml /usr/share/tomcat/lib
sudo cp ozp-rest/grails-app/conf/users.properties /usr/share/tomcat/lib

sudo chown -R tomcat /usr/share/tomcat/lib/ozone-security-beans
sudo chown tomcat /usr/share/tomcat/lib/SecurityContext.xml
sudo chown tomcat /usr/share/tomcat/lib/users.properties

# update /usr/share/tomcat/conf/server.xml, specifically the Connector for
# port 8443 (this assumes the password to the keystore file is 'password'):
sudo sed -i '/<Service name="Catalina">/a <Connector port="8443" protocol="HTTP/1.1" SSLEnabled="true" maxThreads="150" scheme="https" secure="true" clientAuth="false" sslProtocol="TLS" keystoreFile="/usr/share/tomcat/server.keystore" keystorePass="password" />' server.xml

# - - - - - - - - - - - - - - -
# configure nginx 
# - - - - - - - - - - - - - - -
# set up SSL for nginx reverse proxy
sudo mkdir /etc/nginx/ssl

# start nginx
sudo /etc/init.d/nginx start


# - - - - - - - - - - - - - - -
# configure ssl certs for tomcat and nginx
# - - - - - - - - - - - - - - -
# first, generate a private key
echo "openssl genrsa -des3 -out server.key 1024"
# generate a CSR (use ozpdev for CN)
echo "openssl req -new -key server.key -out server.csr"
# remove passphrase from the key
echo "cp server.key server.key.org"
echo "openssl rsa -in server.key.org -out server.key"
# generate a self-signed certificate
echo "openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt"
# now we need to generate a Java keystore for use with Tomcat using these certs
# convert the x509 cert and key to a pkcs12 file
echo "openssl pkcs12 -export -in server.crt -inkey server.key -out server.p12 -name ozpdev -CAfile ca.crt -caname root"
# convert the pkcs12 file into a Java keystore
echo "keytool -importkeystore -deststorepass password -destkeypass password -destkeystore server.keystore -srckeystore server.p12 -srcstoretype PKCS12 -srcstorepass password -alias ozpdev"
# copy keystore file to java place: 
echo "sudo cp server.keystore /usr/share/tomcat"
echo "sudo chown tomcat /usr/share/tomcat/server.keystore"
# copy other keys to nginx place
echo "sudo cp server.crt /etc/nginx/ssl/"
echo "sudo cp server.key /etc/nginx/ssl/"

sudo chown -R nginx /etc/nginx/ssl

# configure firewall as per
# https://www.digitalocean.com/community/tutorials/how-to-setup-a-basic-ip-tables-configuration-on-centos-6
sudo iptables -A INPUT -p tcp -m tcp --dport 8443 -j ACCEPT
sudo iptables -A INPUT -p tcp -m tcp --dport 7799 -j ACCEPT
sudo iptables -L -n
sudo iptables-save | sudo tee /etc/sysconfig/iptables
sudo service iptables restart

# TODO: the next time i tried this, i had to just stop iptables altogether :(

# make deployment directory
sudo mkdir /ozp-static-deployment
sudo mkdir /ozp-static-deployment/center
sudo mkdir /ozp-static-deployment/hud
sudo mkdir /ozp-static-deployment/webtop
sudo mkdir /ozp-static-deployment/demo_apps
sudo mkdir /ozp-static-deployment/iwc

# copy and modify nginx conf file
sudo cp static_nginx.conf /etc/nginx/conf.d/

sudo service nginx restart

