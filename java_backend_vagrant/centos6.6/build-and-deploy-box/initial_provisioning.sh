#!/usr/bin/env bash

HOMEDIR=/home/vagrant
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#			Install and configure build dependencies
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sudo yum update -y
# enable access to EPEL repo
sudo yum install epel-release -y

printf "\n******************\nfinished inital yum update\n******************\n"
# this should have been installed in the basebox but wasn't. without it, the
# virtualbox guest additions will fail to build, and shared folders won't work
sudo yum install kernel-headers kernel-devel -y
printf "\n*************\n finished installing kernel headers \n*************\n"
sudo yum install java-1.7.0-openjdk java-1.7.0-openjdk-devel git unzip vim -y
printf "\n**************\n finished installing java and such \n**************\n"
sudo yum install gcc-c++ -y
curl -s https://raw.githubusercontent.com/creationix/nvm/v0.30.1/install.sh | bash
source ${HOMEDIR}/.nvm/nvm.sh
nvm install 0.12
nvm alias default node
printf "\n**************\nfinished installing nodejs and npm\n**************\n"
# install sdkman
curl -s get.sdkman.io | bash
source ${HOMEDIR}/.sdkman/bin/sdkman-init.sh
# modify .sdkman/etc/config to set sdkman_auto_answer=true
# (see options here: http://sdkman.iot/)
printf "# make sdkman non-interactive, great for CI environments
sdkman_auto_answer=true
# do not perform automatic selfupdates
echo "sdkman_auto_selfupdate=false" > ${HOMEDIR}/.sdkman/etc/config

# use grails 2.3.7
sdk install grails 2.3.7
sdk use grails 2.3.7
sdk default grails 2.3.7

# if the above environment is not used for building (e.g. Jenkins), make sure
# these env vars are set:
# export GRAILS_HOME="${HOMEDIR}/.sdkman/grails/2.3.7"
# export PATH=$GRAILS_HOME/bin:$PATH
# export JAVA_HOME="/usr/lib/jvm/java-1.7.0-openjdk-1.7.0.75.x86_64"

printf "\n*****************\nfinished grails installation\n*****************\n"


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#			Install and configure deployment dependencies
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Add other repos
# Remi dependency on CentOS 6
sudo rpm -Uvh http://dl.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm
sudo rpm -Uvh http://rpms.famillecollet.com/enterprise/remi-release-6.rpm

# elasticsearch
sudo rpm --import https://packages.elasticsearch.org/GPG-KEY-elasticsearch
# Add /etc/yum.repos.d/elasticsearch.repo:
echo "[elasticsearch-1.4]
name=Elasticsearch repository for 1.4.x packages
baseurl=http://packages.elasticsearch.org/elasticsearch/1.4/centos
gpgcheck=1
gpgkey=http://packages.elasticsearch.org/GPG-KEY-elasticsearch
enabled=1" > ${HOMEDIR}/elasticsearch.repo
sudo mv ${HOMEDIR}/elasticsearch.repo /etc/yum.repos.d/


# remove old mysql
sudo yum remove mysql mysql-* -y

# Install packages
# sudo yum --enablerepo=remi,remi-test install mysql mysql-server java-1.7.0-openjdk java-1.7.0-openjdk-devel tomcat elasticsearch nodejs npm nginx git -y
sudo yum --enablerepo=remi,remi-test install mysql mysql-server tomcat elasticsearch nginx multitail -y

# Install newman (for adding test data)
npm install -g newman bower

printf "\n***************\nfinished deployment installation\n***************\n"

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

printf "\n*****************\nfinished elasticsearch config\n*****************\n"

# - - - - - - - - - - - - - - -
# configure MySQL
# - - - - - - - - - - - - - - -
# set the root password ('password')
# remove Test database
# remove anonymous users
# disable root login remotely
sudo /etc/init.d/mysqld start

# do this instead of mysql_secure_installation
DATABASE_PASS="password"
mysqladmin -u root password "$DATABASE_PASS"
mysql -u root -p"$DATABASE_PASS" -e "UPDATE mysql.user SET Password=PASSWORD('$DATABASE_PASS') WHERE User='root'"
mysql -u root -p"$DATABASE_PASS" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
mysql -u root -p"$DATABASE_PASS" -e "DELETE FROM mysql.user WHERE User=''"
mysql -u root -p"$DATABASE_PASS" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'"
mysql -u root -p"$DATABASE_PASS" -e "FLUSH PRIVILEGES"

# start mysql on boot
sudo chkconfig --level 345 mysqld on

# create user ozp
mysql -u root -ppassword -Bse "create user 'ozp'@'localhost' identified by 'ozp';"
# create ozp database
mysql -u root -ppassword -Bse "create database ozp;"
# grant ozp privs
mysql -u root -ppassword -Bse "grant all privileges on *.* to 'ozp'@'localhost';"

printf "\n********************\nfinished mysql config\n********************\n"
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
sudo sed -i '/<tomcat-users>/a <user name="tomcat" password="password" roles="admin,manager-gui" />' /etc/tomcat/tomcat-users.xml
# <user name="tomcat" password="password" roles="admin,manager-gui" />

# update /usr/share/tomcat/conf/server.xml, specifically the Connector for
# port 8443 (this assumes the password to the keystore file is 'password'):
sudo sed -i '/<Service name="Catalina">/a <Connector port="8443" protocol="HTTP/1.1" SSLEnabled="true" maxThreads="150" scheme="https" secure="true" clientAuth="false" sslProtocol="TLS" keystoreFile="/usr/share/tomcat/server.keystore" keystorePass="password" />' /usr/share/tomcat/conf/server.xml

printf "\n********************\nfinished tomcat config\n********************\n"
# - - - - - - - - - - - - - - -
# configure nginx
# - - - - - - - - - - - - - - -
# set up SSL for nginx reverse proxy
sudo mkdir /etc/nginx/ssl

# start nginx
sudo /etc/init.d/nginx start

# to regenerate the ssl keys manually:

# first, generate a private key
# openssl genrsa -des3 -out server.key 1024

# generate a CSR (use ozpdev for CN)
# openssl req -new -key server.key -out server.csr

# remove passphrase from the key
# cp server.key server.key.org
# openssl rsa -in server.key.org -out server.key

# generate a self-signed certificate
# openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt

# now we need to generate a Java keystore for use with Tomcat using these certs
# convert the x509 cert and key to a pkcs12 file
# openssl pkcs12 -export -in server.crt -inkey server.key -out server.p12 -name ozpdev -CAfile ca.crt -caname root

# convert the pkcs12 file into a Java keystore
# keytool -importkeystore -deststorepass password -destkeypass password -destkeystore server.keystore -srckeystore server.p12 -srcstoretype PKCS12 -srcstorepass password -alias ozpdev

# copy keystore file to java place:
sudo cp /vagrant/configs/server.keystore /usr/share/tomcat
sudo chown tomcat /usr/share/tomcat/server.keystore
# copy other keys to nginx place
sudo cp /vagrant/configs/server.crt /etc/nginx/ssl/
sudo cp /vagrant/configs/server.key /etc/nginx/ssl/

sudo chown -R nginx /etc/nginx/ssl

# configure firewall as per
# https://www.digitalocean.com/community/tutorials/how-to-setup-a-basic-ip-tables-configuration-on-centos-6
sudo iptables -A INPUT -p tcp -m tcp --dport 8443 -j ACCEPT
sudo iptables -A INPUT -p tcp -m tcp --dport 7799 -j ACCEPT
sudo iptables -L -n
sudo iptables-save | sudo tee /etc/sysconfig/iptables
sudo service iptables restart

printf "\n******************\nfinished iptables config\n******************\n"

# TODO: the next time i tried this, i had to just stop iptables altogether :(


printf "\n****************\ninitial_provisioning completed\n****************\n"

