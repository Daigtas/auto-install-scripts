#!/bin/bash

language=$(echo $LANGUAGE | cut -d_ -f1)
os=$(cat /etc/os-release | grep ID | cut -d= -f2 | head -1)

curl_check ()
{
# changed curl to a wget for less errors
  echo "Checking for wget..."
  if command -v wget > /dev/null; then
    echo "Detected wget..."
  else
    echo "Installing wget..."
#removed the >/dev/null direction becouse the debian apt supports silent mode with an -qq switch
    if [ "${os}" = "debian" ]; then
        apt-get -qq update
        apt-get -qq -y install wget -y
    elif [ "${os}" = "ubuntu" ]; then 
        apt-get -qq update
        apt-get -qq install wget -y
    elif [ "${os}" = "centos" ]; then 
        yum -qq update
        yum -qq install wget
    fi

    if [ "$?" -ne "0" ]; then
      echo "Unable to install wget! Your base system has a problem; please check your default OS's package repositories because curl should work." >> /dev/stderr
      echo "Repository installation aborted." >> /dev/stderr
      exit 1
    fi
  fi
}

if [ "${os}" = "debian" ]; then 
    script="https://raw.githubusercontent.com/gameap/auto-install-scripts/master/debian/install-en.sh"
elif [ "${os}" = "ubuntu" ]; then 
    script="https://raw.githubusercontent.com/gameap/auto-install-scripts/master/debian/install-en.sh"
elif [ "${os}" = "centos" ]; then 
    echo "Support CentOS is coming soon"
    echo "Your operating system not supported"
    exit 1
else
    echo "Your operating system not supported"
    exit 1
fi

echo "Preparation for installation..."
curl_check

echo
echo
echo "Downloading installator for your operating system..."
# Changed curl to wget and the command gets a bit differend. 
# First cd to a dir then download the script and then rename to a needed script (gameap-install.sh).
# and ofcorse there is no file presence check used. I can add that one if you want to.
cd /tmp/ | wget -q $script | mv install-en.sh gameap-install.sh
chmod +x /tmp/gameap-install.sh

echo
echo
echo "Running..."
echo
echo
bash /tmp/gameap-install.sh $@
rm /tmp/gameap-install.sh
