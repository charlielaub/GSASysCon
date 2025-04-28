#!/bin/bash 

echo;
echo "Auto-Installer script for GSASysCon"
echo "written by Charlie Laub, 2016-2025, version 1.0"
echo;

#test for internet connectivity
echo -n "Checking for internet connectivity..."
ping -c 1 github.com > /dev/null 2>&1
if [ $? -ne 0 ]; then
   echo "ERROR: No internet connection found!"
   echo "You must be connected to the internet to perform the installation of GSASysCon."
   echo "Please try again when you have internet access."
   echo; exit 1
else
   echo "found! Proceeding with the installation..."
fi

#test if script was run using sudo
#   ref: https://askubuntu.com/a/30157/8698
if ! [ $(id -u) = 0 ]; then
   echo; echo "ERROR: The install script must be run as root (e.g. sudo ./Install.sh)." >&2
   echo; exit 2
fi

#use apt-get to check for required packages and install any missing ones:
apt-get update
apt-get -y install gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-tools gstreamer1.0-alsa gstreamer1.0-pulseaudio ladspa-sdk build-essential

#get the name of the user account running the script with sudo
if [ $SUDO_USER ]; then
   real_user=$SUDO_USER
else
   real_user=$(whoami)
fi

#if the LADSPA_PATH is not found in the user's .profile file, add it
grep LADSPA_PATH /home/$real_user/.profile > /dev/null 2>&1
if [ $? -ne 0 ]; then
   echo "adding the LADSPA PATH to .profile of $real_user"
   echo 'export LADSPA_PATH=/usr/local/lib/ladspa:/usr/lib/ladspa' >> /home/$real_user/.profile
fi

#install ACDf LADSPA plugin
saved_path=$(pwd)
cd $(find ../LADSPA -type d -name "ACDf*")
make clean
make
make install
cd $saved_path

clear; echo; echo "The installation has finished."
echo; echo; read -p "Enter y or Y to run the first-test now, any other key to skip." user_input

if  [[ "$user_input" == "y" || "$user_input" == "Y"  ]]; then
   echo; echo; echo "INSTRUCTIONS: Press 1 to run the first-test system. The STATUS field should change from OFF to 0sec and"
   echo "   then update every 10 seconds with a new elapsed run time. You may press ENTER to refresh/update the run"
   echo "   time. Enter 1 again to stop the system. The status should return to OFF. Finally, enter x to exit."
   echo; echo; read -p "When you are ready to begin, press the Enter key."
   target=$(find . -name 'GSASysCon*'); eval $target --config_file=minimal_config.txt -r 10
fi   

clear; echo; echo "A reboot is required after the install process."

echo; echo; read -p "Enter y or Y to reboot now, or press any other key to return to the command line.  " user_input

if  [[ "$user_input" == "y" || "$user_input" == "Y"  ]]; then
   reboot
else
   echo
   echo "Please remember to perform a reboot later, before using GSASysCon."
   echo
fi  
