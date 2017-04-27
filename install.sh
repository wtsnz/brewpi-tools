#!/bin/bash

# Copyright 2013 BrewPi
# This file is part of BrewPi.

# BrewPi is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# BrewPi is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with BrewPi.  If not, see <http://www.gnu.org/licenses/>.

########################
### This script assumes a clean Raspbian install.
### Freeder, v1.0, Aug 2013
### Elco, Oct 2013
### Using a custom 'die' function shamelessly stolen from http://mywiki.wooledge.org/BashFAQ/101
### Using ideas even more shamelessly stolen from Elco and mdma. Thanks guys!
########################

############
### Init
###########

# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root: sudo ./install.sh" 1>&2
   exit 1
fi

############
### Functions to catch/display errors during setup
############
warn() {
  local fmt="$1"
  command shift 2>/dev/null
  echo -e "$fmt\n" "${@}"
  echo -e "\n*** ERROR ERROR ERROR ERROR ERROR ***\n----------------------------------\nSee above lines for error message\nSetup NOT completed\n"
}

die () {
  local st="$?"
  warn "$@"
  exit "$st"
}

############
### Create install log file
############
exec > >(tee -i install.log)
exec 2>&1

############
### Check for network connection
###########
echo -e "\nChecking for Internet connection..."
ping -c 3 github.com &> /dev/null
if [ $? -ne 0 ]; then
    echo "------------------------------------"
    echo "Could not ping github.com. Are you sure you have a working Internet connection?"
    echo "Installer will exit, because it needs to fetch code from github.com"
    exit 1    
fi
echo -e "Success!\n"

############
### Check whether installer is up-to-date
############
echo -e "\nChecking whether this script is up to date...\n"
unset CDPATH
myPath="$( cd "$( dirname "${BASH_SOURCE[0]}")" && pwd )"
bash "$myPath"/update-tools-repo.sh
if [ $? -ne 0 ]; then
    echo "The update script was not up-to-date, but it should have been updated. Please re-run install.sh."
    exit 1
fi


############
### Install required packages
############
echo -e "\n***** Installing/updating required packages... *****\n"
lastUpdate=$(stat -c %Y /var/lib/apt/lists)
nowTime=$(date +%s)
if [ $(($nowTime - $lastUpdate)) -gt 604800 ] ; then
    echo "last apt-get update was over a week ago. Running apt-get update before updating dependencies"
    sudo apt-get update||die
fi
sudo apt-get install -y apache2 libapache2-mod-php5 php5-cli php5-common php5-cgi php5 git-core build-essential python-dev python-pip pastebinit || die
echo -e "\n***** Installing/updating required python packages via pip... *****\n"
sudo pip install pyserial psutil simplejson configobj gitpython --upgrade
echo -e "\n***** Done processing BrewPi dependencies *****\n"


############
### Setup questions
############

free_percentage=$(df /home | grep -vE '^Filesystem|tmpfs|cdrom|none' | awk '{ print $5 }')
free=$(df /home | grep -vE '^Filesystem|tmpfs|cdrom|none' | awk '{ print $4 }')
free_readable=$(df -H /home | grep -vE '^Filesystem|tmpfs|cdrom|none' | awk '{ print $4 }')

if [ "$free" -le "512000" ]; then
    echo -e "\nDisk usage is $free_percentage, free disk space is $free_readable"
    echo "Not enough space to continue setup. Installing BrewPi requires at least 512mb free space"
    echo "Did you forget to expand your root partition? To do so run 'sudo raspi-config', expand your root partition and reboot"
    exit 1
else
    echo -e "\nDisk usage is $free_percentage, free disk space is $free_readable. Enough to install BrewPi\n"
fi


echo "To accept the default answer, just press Enter."
echo "The default is capitalized in a Yes/No question: [Y/n]"
echo "or shown between brackets for other questions: [default]"

date=$(date)
read -p "The time is currently set to $date. Is this correct? [Y/n]" choice
case "$choice" in
  n | N | no | NO | No )
    dpkg-reconfigure tzdata;;
  * )
esac


############
### Now for the install!
############
echo -e "\n*** This script will first ask you where to install the brewpi python scripts and the web interface"
echo "Hitting 'enter' will accept the default option in [brackets] (recommended)."

echo -e "\nAny data in the following location will be ERASED during install!"
read -p "Where would you like to install BrewPi? [/home/brewpi]: " installPath
if [ -z "$installPath" ]; then
  installPath="/home/brewpi"
else
  case "$installPath" in
    y | Y | yes | YES| Yes )
        installPath="/home/brewpi";; # accept default when y/yes is answered
    * )
        ;;
  esac
fi
echo "Installing script in $installPath";

if [ -d "$installPath" ]; then
  if [ "$(ls -A ${installPath})" ]; then
    read -p "Install directory is NOT empty, are you SURE you want to use this path? [y/N] " yn
    case "$yn" in
        y | Y | yes | YES| Yes ) echo "Ok, we warned you!";;
        * ) exit;;
    esac
  fi
else
  if [ "$installPath" != "/home/brewpi" ]; then
    read -p "This path does not exist, would you like to create it? [Y/n] " yn
    if [ -z "$yn" ]; then
      yn="y"
    fi
    case "$yn" in
        y | Y | yes | YES| Yes ) echo "Creating directory..."; mkdir -p "$installPath";;
        * ) echo "Aborting..."; exit;;
    esac
  fi
fi

echo "Searching for default web install location..."
webPath=`grep DocumentRoot /etc/apache2/sites-enabled/000-default* |xargs |cut -d " " -f2`
echo "Found $webPath"


echo -e "\nAny data in the following location will be ERASED during install!"
read -p "Where would you like to copy the BrewPi web files to? [$webPath]: " webPathInput

if [ "$webPathInput" ]; then
    webPath=${webPathInput}
fi

echo "Installing web interface in $webPath";

if [ -d "$webPath" ]; then
  if [ "$(ls -A ${webPath})" ]; then
    read -p "Web directory is NOT empty, are you SURE you want to use this path? [y/N] " yn
    case "$yn" in
        y | Y | yes | YES| Yes ) echo "Ok, we warned you!";;
        * ) exit;;
    esac
  fi
else
  read -p "This path does not exist, would you like to create it? [Y/n] " yn
  if [ -z "$yn" ]; then
    yn="y"
  fi
  case "$yn" in
      y | Y | yes | YES| Yes ) echo "Creating directory..."; mkdir -p "$webPath";;
      * ) echo "Aborting..."; exit;;
  esac
fi

############
### Create/configure user accounts
############
echo -e "\n***** Creating and configuring user accounts... *****"
chown -R www-data:www-data "$webPath"||die
if id -u brewpi >/dev/null 2>&1; then
  echo "User 'brewpi' already exists, skipping..."
else
  useradd -G www-data,dialout brewpi||die
  echo -e "brewpi\nbrewpi\n" | passwd brewpi||die
fi
# add pi user to brewpi and www-data group
usermod -a -G www-data chip||die
usermod -a -G brewpi chip||die

echo -e "\n***** Checking install directories *****"

if [ -d "$installPath" ]; then
  echo "$installPath already exists"
else
  mkdir -p "$installPath"
fi

dirName=$(date +%F-%k:%M:%S)
if [ "$(ls -A ${installPath})" ]; then
  echo "Script install directory is NOT empty, backing up to this users home dir and then deleting contents..."
    if ! [ -a ~/brewpi-backup/ ]; then
      mkdir -p ~/brewpi-backup
    fi
    mkdir -p ~/brewpi-backup/"$dirName"
    cp -R "$installPath" ~/brewpi-backup/"$dirName"/||die
    rm -rf "$installPath"/*||die
    find "$installPath"/ -name '.*' | xargs rm -rf||die
fi

if [ -d "$webPath" ]; then
  echo "$webPath already exists"
else
  mkdir -p "$webPath"
fi
if [ "$(ls -A ${webPath})" ]; then
  echo "Web directory is NOT empty, backing up to this users home dir and then deleting contents..."
  if ! [ -a ~/brewpi-backup/ ]; then
    mkdir -p ~/brewpi-backup
  fi
  if ! [ -a ~/brewpi-backup/"$dirName"/ ]; then
    mkdir -p ~/brewpi-backup/"$dirName"
  fi
  cp -R "$webPath" ~/brewpi-backup/"$dirName"/||die
  rm -rf "$webPath"/*||die
  find "$webPath"/ -name '.*' | xargs rm -rf||die
fi

chown -R www-data:www-data "$webPath"||die
chown -R brewpi:brewpi "$installPath"||die

############
### Set sticky bit! nom nom nom
############
find "$installPath" -type d -exec chmod g+rwxs {} \;||die
find "$webPath" -type d -exec chmod g+rwxs {} \;||die


############
### Clone BrewPi repositories
############
echo -e "\n***** Downloading most recent BrewPi codebase... *****"
cd "$installPath"
sudo -u brewpi git clone https://github.com/BrewPi/brewpi-script "$installPath"||die
cd "$webPath"
sudo -u www-data git clone https://github.com/BrewPi/brewpi-www "$webPath"||die

###########
### If non-default paths are used, update config files accordingly
##########
if [[ "$installPath" != "/home/brewpi" ]]; then
    echo -e "\n***** Using non-default path for the script dir, updating config files *****"
    echo "scriptPath = $installPath" >> "$installPath"/settings/config.cfg

    echo "<?php " >> "$webPath"/config_user.php
    echo "\$scriptPath = '$installPath';" >> "$webPath"/config_user.php
fi

if [[ "$webPath" != "/var/www" ]]; then
    echo -e "\n***** Using non-default path for the web dir, updating config files *****"
    echo "wwwPath = $webPath" >> "$installPath"/settings/config.cfg
fi


############
### Fix permissions
############
echo -e "\n***** Running fixPermissions.sh from the script repo. *****"
if [ -a "$installPath"/utils/fixPermissions.sh ]; then
   bash "$installPath"/utils/fixPermissions.sh
else
   echo "ERROR: Could not find fixPermissions.sh!"
fi

############
### Install CRON job
############
echo -e "\n***** Running updateCron.sh from the script repo. *****"
if [ -a "$installPath"/utils/updateCron.sh ]; then
   bash "$installPath"/utils/updateCron.sh
else
   echo "ERROR: Could not find updateCron.sh!"
fi

############
### Check for insecure SSH key
############
defaultKey="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDLNC9E7YjW0Q9btd9aUoAg++/wa06LtBMc1eGPTdu29t89+4onZk1gPGzDYMagHnuBjgBFr4BsZHtng6uCRw8fIftgWrwXxB6ozhD9TM515U9piGsA6H2zlYTlNW99UXLZVUlQzw+OzALOyqeVxhi/FAJzAI9jPLGLpLITeMv8V580g1oPZskuMbnE+oIogdY2TO9e55BWYvaXcfUFQAjF+C02Oo0BFrnkmaNU8v3qBsfQmldsI60+ZaOSnZ0Hkla3b6AnclTYeSQHx5YqiLIFp0e8A1ACfy9vH0qtqq+MchCwDckWrNxzLApOrfwdF4CSMix5RKt9AF+6HOpuI8ZX root@raspberrypi"

if grep -q "$defaultKey" /etc/ssh/ssh_host_rsa_key.pub; then
  echo "Replacing default SSH keys. You will need to remove the previous key from known hosts on any clients that have previously connected to this rpi."
  if rm -f /etc/ssh/ssh_host_* && dpkg-reconfigure openssh-server; then
     echo "Default SSH keys replaced."
  else
    echo "ERROR - Unable to replace SSH key. You probably want to take the time to do this on your own."
  fi
fi

echo -e "Done installing BrewPi!"

echo -e "\n* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *"
echo -e "Review the log above for any errors, otherwise, your initial environment install is complete!"
echo -e "\nYou are currently using the password 'brewpi' for the brewpi user. If you wish to change this, type 'sudo passwd brewpi' now, and follow the prompt"
echo -e "\nTo view your BrewPi web interface, enter http://`/sbin/ifconfig|egrep -A 1 'eth|wlan'|awk -F"[Bcast:]" '/inet addr/ {print $4}'` into your web browser"
echo -e "\nHappy Brewing!"



