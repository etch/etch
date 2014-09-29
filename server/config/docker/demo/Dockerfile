FROM debian:7
MAINTAINER Jason Heiss <jheiss@aput.net>

# A production etch server docker config should probably run the
# database in a separate container.
# Per https://downloads.mariadb.org/mariadb/repositories/
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get -y -q install python-software-properties
RUN apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0xcbcb082a1bb943db
RUN add-apt-repository 'deb http://sfo1.mirrors.digitalocean.com/mariadb/repo/10.0/debian wheezy main'

RUN apt-get update

# I can't figure out how to get bundler to use gem2.0
#RUN DEBIAN_FRONTEND=noninteractive apt-get -y -q install git ruby2.0 ruby2.0-dev make g++ libmariadbclient-dev libxml2-dev mariadb-server
#RUN gem2.0 install bundler
RUN DEBIAN_FRONTEND=noninteractive apt-get -y -q install git ruby ruby-dev make g++ libmariadbclient-dev libxml2-dev mariadb-server
RUN gem install bundler

# Install etch server
# FIXME: should check out a version tag or pull down a version tarball
RUN cd /tmp && git clone https://github.com/etch/etch.git && cd etch && git checkout 2337235b
RUN mv /tmp/etch/server /opt/etchserver
RUN mkdir -p /opt/etchserver/tmp/pids
RUN mv /tmp/etch/etchserver-demo /etc/etchserver
RUN rm -rf /tmp/etch

# Dockerize the unicorn config (log to stdout instead of files)
# Note that the Rails production.log still goes to disk, not sure what to do
# about that
RUN sed -i 's/^std/#std/' /opt/etchserver/config/unicorn.rb

# Productionize the Gemfile
RUN sed -i '/gem.*sqlite3/s/^/#/' /opt/etchserver/Gemfile
RUN sed -i '/gem.*unicorn/s/^# //' /opt/etchserver/Gemfile
RUN printf "gem 'mysql'\n" >> /opt/etchserver/Gemfile

# Install ruby and gems
RUN cd /opt/etchserver && bundle install
RUN cd /opt/etchserver && bundle install --deployment --binstubs

# Database
RUN service mysql start && mysql -u root -e "CREATE DATABASE etch"
RUN service mysql start && mysql -u root -e "GRANT ALL on etch.* to etch"
RUN printf "production:\n  adapter: mysql\n  database: etch\n  username: etch\n  host: localhost\n  socket: /var/run/mysqld/mysqld.sock\n" > /opt/etchserver/config/database.yml
RUN service mysql start && cd /opt/etchserver && RAILS_ENV=production bundle exec ./bin/rake db:migrate

# Assets
RUN cd /opt/etchserver && RAILS_ENV=production bundle exec ./bin/rake assets:precompile

# A production etch server docker config should generate a secret on
# initial startup (in the ENTRYPOINT) and save it.  This is good enough
# for demo purposes, but burns the secret into the docker image for the
# whole world to see.
RUN cd /opt/etchserver && secret=`rake secret` && sed -i "s/secret_key_base:.*/secret_key_base: $secret/" /opt/etchserver/config/secrets.yml

# Expose port
EXPOSE 8080

# Start unicorn
WORKDIR /opt/etchserver
ENTRYPOINT service mysql start && cat config/unicorn.rb && bundle exec ./bin/unicorn -E production -c ./config/unicorn.rb
