#! /bin/sh

UPGRADE_PACKAGES=false
DATABASE_PASSWORD="pass"
DATE=`date --iso-8601=seconds`
SOURCE_DIRECTORY="$HOME/ckan"
VIRTUAL_ENVIRONMENT="/usr/lib/ckan/default"
RUN_TESTS=true
TEST_INI="/usr/lib/ckan/default/src/ckan/test-core.ini"
PLUGINS_ROOT="ckan-plugins"

if [ -f "config.sh" ]; then
	. config.sh
fi

echo "test: $TEST_VARIABLE"

#if [ ! -d "$PLUGINS_ROOT" ]; then
#	echo "Plugins root directory not found. Check working directory."
#	exit 1
#fi

if $UPGRADE_PACKAGES; then
	sudo apt-get -y update
	sudo apt-get -y upgrade
fi

# install requirements
sudo apt-get -qq update
sudo apt-get -qq -y install solr-jetty python-virtualenv

sudo service postgresql reload

mkdir -p $SOURCE_DIRECTORY/lib
mkdir -p $SOURCE_DIRECTORY/etc

sudo ln -sf $SOURCE_DIRECTORY/lib /usr/lib/ckan
sudo ln -sf $SOURCE_DIRECTORY/etc /etc/ckan

mkdir -p $VIRTUAL_ENVIRONMENT
virtualenv --no-site-packages $VIRTUAL_ENVIRONMENT
. $VIRTUAL_ENVIRONMENT/bin/activate

export PIP_USE_MIRRORS=true
pip install -qe 'git+https://github.com/okfn/ckan.git@ckan-2.1#egg=ckan'
pip install -qr $VIRTUAL_ENVIRONMENT/src/ckan/requirements.txt --download-cache=$HOME/cache

mkdir -p /etc/ckan/default

# Configure Solr (and Jetty)
sudo sh -c 'echo "NO_START=0\nJETTY_HOST=127.0.0.1\nJETTY_PORT=8983\nVERBOSE=yes\nJAVA_HOME=$JAVA_HOME" > /etc/default/jetty'

sudo cp /usr/lib/ckan/default/src/ckan/ckan/config/solr/schema-2.0.xml /etc/solr/conf/schema.xml

sudo service jetty restart

# Initialize postgres database
for username in ckan_default datastore_default ckan_test datastore_test; do
	if [ ! `sudo -u postgres psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='$username'"`  ]; then
		sudo -u postgres psql -c "CREATE USER $username WITH PASSWORD '$DATABASE_PASSWORD';"	
	fi
	sudo -u postgres psql -U postgres -d postgres -c "ALTER USER $username WITH PASSWORD '$DATABASE_PASSWORD';"
done

for database in ckan_test datastore_test; do
	if [ `sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$database'"` ]; then
		sudo -u postgres psql -c "DROP DATABASE $database;"
	fi
	sudo -u postgres psql -c "CREATE DATABASE $database WITH OWNER ckan_default;"
done

for plugin in ckan-plugins/*; do
	cd $plugin
	python setup.py develop
	cd -
done

cd /usr/lib/ckan/default/src/ckan/
paster db init -c $TEST_INI
cd -
EXIT_STATUS=0
#for plugin in ckan-plugins/*; do
#	nosetests --ckan --with-pylons=$plugin/test.ini $plugin/ckanext
#	NOSE_EXIT=$?
#	if [ "$NOSE_EXIT" != "0" ]; then
#		EXIT_STATUS=$NOSE_EXIT
#	fi
#done
deactivate

exit $EXIT_STATUS
