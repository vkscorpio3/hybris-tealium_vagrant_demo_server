#!/bin/bash
declare -x ADDON_DIR
declare -x CURRENT_HASH
declare -x LAST_HASH
declare -x INIT_TIME
declare -x NOW

declare -x DIR
declare -x EXTENSION_TAG
declare -x EXTENSION_INSERT
declare -x EXTENSION_ALREADY_ADDED
declare -x LOCAL_EXTENSION_FILE

declare -x MASTER_TAG_FILE
declare -x MASTER_TAG_BODY_TAG
declare -x MASTER_TAG_INSERT_BODY
declare -x MASTER_TAG_BODY_ALREADY_ADDED
declare -x MASTER_TAG_HEAD_TAG
declare -x MASTER_TAG_INSERT_HEAD
declare -x MASTER_TAG_HEAD_ALREADY_ADDED
declare -x MASTER_TAG_INSERT_INCLUDE
declare -x MASTER_TAG_INCLUDE_ALREADY_ADDED

ADDON_DIR="/home/vagrant/hybris/bin/custom/tealiumiqaddon/"
CURRENT_HASH=$(git ls-remote git://github.com/patrickmcwilliams/hybris-integration.git HEAD)

DIR="/home/vagrant/hybris/bin/platform/"
EXTENSION_TAG="\t<\/extensions>"
EXTENSION_INSERT="\t\t<extension dir=\"\${HYBRIS_BIN_DIR}\/custom\/tealiumiqaddon\"\/>"
EXTENSION_ALREADY_ADDED="\t\t<extension dir=\\\"\\\${HYBRIS_BIN_DIR}\/custom\/tealiumiqaddon\"\/>"
LOCAL_EXTENSION_FILE="/home/vagrant/hybris/config/localextensions.xml"


MASTER_TAG_FILE="/home/vagrant/hybris/bin/ext-template/yacceleratorstorefront/web/webroot/WEB-INF/tags/desktop/template/master.tag"

MASTER_TAG_INSERT_INCLUDE="<%@ taglib prefix=\"tealiumiqaddon\" tagdir=\"\/WEB-INF\/tags\/addons\/tealiumiqaddon\/shared\/analytics\" %>"
MASTER_TAG_INCLUDE_ALREADY_ADDED="<%@ taglib prefix=\\\"tealiumiqaddon\\\" tagdir=\\\"\/WEB-INF\/tags\/addons\/tealiumiqaddon\/shared\/analytics\\\" %>"

MASTER_TAG_BODY_TAG="<body[^\/]*>"
MASTER_TAG_INSERT_BODY="<tealiumiqaddon:tealium\/>"
MASTER_TAG_BODY_ALREADY_ADDED="<tealiumiqaddon:tealium\/>"

MASTER_TAG_HEAD_TAG="<head>"
MASTER_TAG_INSERT_HEAD="<tealiumiqaddon:sync\/>"
MASTER_TAG_HEAD_ALREADY_ADDED="<tealiumiqaddon:sync\/>"

get_package () {
  if [ "$(ls -A $DIR)" ]; then
    find $ADDON_DIR -type f -not -name 'project\.properties.*' | xargs rm -rf
    find $ADDON_DIR -type d -not -wholename '*tealiumiqaddon/' | xargs rm -rf
  fi
  cd $ADDON_DIR
  echo "[Unpacking curent addon from git repo]"
  curl -Ls https://github.com/patrickmcwilliams/hybris-integration/tarball/master | tar zx --strip=5 --skip-old-files
  echo "[Getting .git hash]"
  git ls-remote git://github.com/patrickmcwilliams/hybris-integration.git HEAD &> /home/vagrant/setup-config/git.hash
}

init_hybris () {
  > /home/vagrant/setup-config/build_status.log
  echo -e "[Initializing hybris DB]\n[This may take > 30 minutes]"
  stdbuf -oL ant initialize > /home/vagrant/setup-config/build_status.log 2>&1 &
  while [ "$(grep -E ".*BUILD SUCCESSFUL.*" /home/vagrant/setup-config/build_status.log)" == "" ]; do
    echo "[ hybris DB initialization in progress " $(date) "]"
    if [ "$(grep -E ".*BUILD FAILED.*" /home/vagrant/setup-config/build_status.log)" != "" ]; then
      echo "[ initializaion failed ]"
      break
    fi
    sleep 5m
  done
  if [ "$(grep -E ".*BUILD SUCCESSFUL.*" /home/vagrant/setup-config/build_status.log)" != "" ]; then
    echo "[ initializaion a success ]"
  fi
  date +%s &> /home/vagrant/setup-config/init.time
}

if [[ $EUID -ne 0 ]]; then
  echo "Run as sudo" 2>&1
  exit 1
else
  
# Create setup config directory to hold config files
  if [ ! -d "/home/vagrant/setup-config" ]; then
    mkdir /home/vagrant/setup-config
    chown vagrant:vagrant /home/vagrant/setup-config
  fi
# end setup config
  
# Update addon if first time or hash doesnt match
  if [ ! -e "/home/vagrant/setup-config/git.hash" ]; then
    echo "[Getting Addon from git]"
    get_package
  fi
  LAST_HASH=$(cat /home/vagrant/setup-config/git.hash)
  if [ "$CURRENT_HASH" != "$LAST_HASH" ]; then
    echo "[Updating Addon from git]"
    get_package
  fi
# end update addon
  
  cd $DIR
# init if first run or more than 30 days  
  if [ ! -e "/home/vagrant/setup-config/init.time" ]; then
    init_hybris
  fi
  INIT_TIME=$(cat /home/vagrant/setup-config/init.time)
  NOW=$(date +%s)
  if [ $[ $NOW - $INIT_TIME ]  -gt $[ 24*3600 ] ]; then
    init_hybris
  fi
# end init  

# edit localextions.xml to add tealiumiqaddon addon
  if ! grep -Pq "$EXTENSION_ALREADY_ADDED" $LOCAL_EXTENSION_FILE
  then
    echo "[ Added tealiumiqaddon to localextensions.xml ]"
    sed -i "s/$EXTENSION_TAG/$EXTENSION_INSERT\n$EXTENSION_TAG/" $LOCAL_EXTENSION_FILE
  fi
# end edit

# add tealium addon 
  > /home/vagrant/setup-config/build_status.log
  echo "[ Installing tealiumiqaddon addon ]"
  stdbuf -oL ant addoninstall -Daddonnames="tealiumiqaddon" -DaddonStorefront.yacceleratorstorefront="yacceleratorstorefront" > /home/vagrant/setup-config/build_status.log 2>&1 &
  while [ "$(grep -E ".*BUILD SUCCESSFUL.*" /home/vagrant/setup-config/build_status.log)" == "" ]; do
    echo "[ tealiumiqaddon addon in progress ]"
    if [ "$(grep -E ".*BUILD FAILED.*" /home/vagrant/setup-config/build_status.log)" != "" ]; then
      echo "[ addon installation failed ]"
      break
    fi
    sleep 2m
  done
  if [ "$(grep -E ".*BUILD SUCCESSFUL.*" /home/vagrant/setup-config/build_status.log)" != "" ]; then
    echo "[ addon installation a success ]"
  fi
# end add addon

# build system 
  > /home/vagrant/setup-config/build_status.log
  echo "[ Building hybris environment ]"
  stdbuf -oL ant all > /home/vagrant/setup-config/build_status.log 2>&1 &
  while [ "$(grep -E ".*BUILD SUCCESSFUL.*" /home/vagrant/setup-config/build_status.log)" == "" ]; do
    echo "[ hybris environment build in progress ]"
    if [ "$(grep -E ".*BUILD FAILED.*" /home/vagrant/setup-config/build_status.log)" != "" ]; then
      echo "[ build failed ]"
      break
    fi
    sleep 2m
  done
  if [ "$(grep -E ".*BUILD SUCCESSFUL.*" /home/vagrant/setup-config/build_status.log)" != "" ]; then
    echo "[ hybris environment build successful ]"
  fi
# end build

# start server
  > /home/vagrant/setup-config/server_status.log
  echo "[ Starting hybris server ]"
  stdbuf -oL ./hybrisserver.sh > /home/vagrant/setup-config/server_status.log 2>&1 &
  echo "[ Starting server ]"
  PROGRESS_BAR=0
  while [ "$(grep -E ".*Starting ProtocolHandler.*" /home/vagrant/setup-config/server_status.log)" == "" ]; do
    echo "[ Server startup in progress. May take more than 10 minutes ]"
    if [ "$(grep -E ".*BUILD FAILED.*" /home/vagrant/setup-config/server_status.log)" != "" ]; then
      echo "[ server startup failed ]"
      break
    fi
    sleep 2m
  done
  if [ "$(grep -E ".*BUILD SUCCESSFUL.*" /home/vagrant/setup-config/server_status.log)" != "" ]; then
    echo "[ hybris server started successfully ]"
  fi
  
# end start server  
  
# Edit master.tag to insert tealium code onto pages  
  if ! grep -Pq "$MASTER_TAG_INCLUDE_ALREADY_ADDED" $MASTER_TAG_FILE
  then
    echo "[ Added Tealium java package to master.tag ]"
    sed -i "1i $MASTER_TAG_INSERT_INCLUDE" $MASTER_TAG_FILE
  fi
  
  if ! grep -Pq "$MASTER_TAG_BODY_ALREADY_ADDED" $MASTER_TAG_FILE
  then
    echo "[ Added Tealium to Body ]"
    sed -i "s/\($MASTER_TAG_BODY_TAG\)/\1\n\t$MASTER_TAG_INSERT_BODY/" $MASTER_TAG_FILE
  fi
  
  if ! grep -Pq "$MASTER_TAG_HEAD_ALREADY_ADDED" $MASTER_TAG_FILE
  then
    echo "[ Added Tealium to Head ]"
    sed -i "s/$MASTER_TAG_HEAD_TAG/$MASTER_TAG_HEAD_TAG\n\t$MASTER_TAG_INSERT_HEAD/" $MASTER_TAG_FILE
  fi
# end edit  
fi