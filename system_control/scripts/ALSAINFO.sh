#!/bin/bash 
PROG_INFO="written by Charlie Laub, 2016-2025, version 3.0"
DEFAULT_SAMPLE_RATE=44100   #if user does not supply a sample rate, use this
DEFAULT_FORMAT=S16LE   #if user does not supply format, use this
CHANNEL_MAX=29  #Gstreamer version 1.26 supports up to 29 audio channels
STD_SAMPLE_RATES=(8000 11025 16000 22050 32000 44100 48000 88200 96000 176400 192000 352800 384000)


function get_card_info1 {
  #get info via aplay -L (upper case L)
   output=$(aplay -L)
   readarray -t array <<<"$output"

   index=0
   for i in "${array[@]}"
   do
      if ( [[ "$2" == "" ]] && [[ "$i" == "$1"* ]] ) || ( [[ "$2" == "," ]] && [[ "$i" == "$1" ]] ); then
#      if [[ "$i" == "$1"* ]]; then
         echo "$i: ${array[index+1]}"
         device_count=$((device_count+1))
      fi
      index=$((index+1))
   done
}


function get_card_info2 {
  #get info via aplay -l (lower case L)
   output=$(aplay -l)
   readarray -t array <<<"$output"

   for i in "${array[@]}"
   do
      if [[ "$i" == "card $1:"* ]] ; then
        if [[ "$2" == "" ]] || ( [[ "$2" != "" ]] && [[ "$i" == *"device $2:"* ]] ); then
          echo "$i"
          device_count=$((device_count+1))
        fi
      fi
   done
}


function get_ALSA_description {
  user_input=$1
  device_count=0
  #test the user input for a colon
  if [[ $user_input != *":"* ]]; then
     #no colon was found - interpret the user input as a device name
     get_card_info1 "$user_input"
     return 0
  else
     #user specified device using the format hw:card,device
     colon_index=$(expr index $user_input ":")
     card_device=${user_input:colon_index}
     #get text up to comma, or end of string. This is the card
     comma_index=$(expr index $card_device ",")
     #if a comma is present, the device follows it
     if [ "$comma_index" -ne "0" ]; then
        device=${card_device:comma_index}
        length=$comma_index-1
        card=${card_device:0:length}
     else
        card=$card_device
        device=""
        echo -e "\033[0;36mWARNING: Found card in user input, but no device was provided"
        echo -e "   Probing for all devices of this card.\033[0m"
     fi
     #does the card begin wtih a number?
     if [[ $card =~ ^[0-9] ]]; then
        get_card_info2 "$card" "$device"
        echo
     else
        if [[ $user_input == *","* ]]; then
          get_card_info1 "$user_input" ","
        else
          get_card_info1 "$user_input"
        fi
     fi
  fi
  if [[ $device == '' ]] && [[ $device_count > 1 ]]; then
    echo -e "\033[0;36mPlease re-run this program including a device to obtain the Gstreamer channel use information\033[0m"
    return 1
  else
    return 0
  fi
}


INFO[1]="ALSAINFO.sh : $PROG_INFO"
INFO[2]="A program to determine valid modes and channel assignments for an ALSA card under GStreamer"
INFO[3]=" "
INFO[4]="Command line parameters:"
INFO[5]="  first command line parameter (required): alsa device to test, e.g. hw:1,0"
INFO[6]="  second command line parameter (optional): requested sample rate, e.g. 48000, 96000, etc. Default = 44100"
INFO[7]="  third command line parameter (optional): requested audio format, e.g. S16LE, S32LE, etc. Default = S16LE"
INFO[8]=" "
INFO[9]="NOTES:"
INFO[10]="  1. The actual sample rate may be the closest rate that is supported by the soundcard and not the requested rate."
INFO[11]="  2. Gstreamer supported audio formats: S8, U8, S16LE, S16BE, U16LE, U16BE, S24_32LE, S24_32BE, U24_32LE, U24_32BE, S32LE, S32BE, U32LE, U32BE, S24LE, S24BE, U24LE, U24BE, S20LE, S20BE, U20LE, U20BE, S18LE, S18BE, U18LE, U18BE, F32LE, F32BE, F64LE, F64BE"


#print help info when prompted by user:
if [[ $1 == "-h" ]] || [[ $1 == "--help" ]] || [ $# -eq 0 ]; then
   saveIFS=$IFS
   IFS=''
   echo
   for eachline in ${INFO[@]}
   do
      echo  $eachline
   done
   echo
   IFS=$saveIFS
   exit 0
else
   echo; echo ${INFO[1]}; echo
fi

if [[ "$1" == "" ]]; then
   echo "FATAL ERROR: an ALSA device must be supplied as the first parameter"
   exit
else
   echo "testing ALSA device: $1"
   ALSA_device=$1
fi
if [[ "$2" == "" ]]; then
   sample_rate=$DEFAULT_SAMPLE_RATE
   echo "No sample rate supplied - using the default sample rate of $sample_rate Hz"
else
   sample_rate=$2;
   echo "Using a sample rate of $sample_rate Hz"
fi
if [[ "$3" == "" ]]; then
   audio_format=$DEFAULT_FORMAT
   echo "No audio format supplied - using the default audio format of $audio_format"
else
   audio_format=$3
   echo "probing the device with an audio format of $audio_format"
fi



#Get description of the ALSA card/device provided by the user
echo; echo "ALSA info about $1 :"
get_ALSA_description $1
retval=$?
if [[ "$retval" != "0" ]]; then
  #get_ALSA_description returns 0 on success, 1 on failure or to indicate that
  #  the program should exit
  exit
fi


#Write the ALSA information on this device
{ output="$( { timeout 1 aplay -D $1 -q --dump-hw-params /dev/zero; } 2>&1 1>&3 3>&- )"; } 3>&1;
if [[ "$output" == *"busy"*  ]]; then 
   echo "CARD IS BUSY!"; 
   exit; 
fi;
if [[ "$output" == *"error"*  ]]; then 
   echo "Trying to open $1 generated an error. Please check the device name and try again."; 
   exit; 
fi;
output=${output#*--------------------}
output=${output%--------------------*}
echo "------------------------------------------------"
cat <<EOF
$output
EOF
echo "------------------------------------------------"
echo;echo;
echo "Now testing $1 for comptibilty with channel counts ranging from 2 to $CHANNEL_MAX:"

for (( num_channels=2; num_channels<=$CHANNEL_MAX; num_channels++ ))
do
   SOMETEXT=$(timeout 3 gst-launch-1.0 -vm audiotestsrc wave=silence ! audio/x-raw,channels=$num_channels,format=$audio_format,rate=$sample_rate ! audioconvert ! alsasink device="$ALSA_device" 2>/dev/null )

   SOMETEXT=$(echo "$SOMETEXT" | grep "GstAlsaSink:alsasink0.GstPad:sink: caps")
   SOMETEXT=${SOMETEXT//'\'/''}

   if [ "$?" -eq 0 ] && [[ "$SOMETEXT" != '' ]]; then
      reported_audio_format=$(echo $SOMETEXT | sed -n -e 's/^.*format=(string)//p')
      comma_position=$(expr index "$reported_audio_format" ',')
      if [ $comma_position -ne 0 ]; then
         reported_audio_format=${reported_audio_format:0:comma_position-1}
      fi

      reported_channels=$(echo $SOMETEXT | sed -n -e 's/^.*channels=(int)//p')
      comma_position=$(expr index "$reported_channels" ',')
      if [ $comma_position -ne 0 ]; then
         reported_channels=${reported_channels:0:comma_position-1}
      fi

      reported_rate=$(echo $SOMETEXT | sed -n -e 's/^.*rate=(int)//p')
      comma_position=$(expr index "$reported_rate" ',')
      if [ $comma_position -ne 0 ]; then
         reported_rate=${reported_rate:0:comma_position-1}
      fi

      if [[ "$reported_channels" != "$num_channels" ]]; then
         continue
      fi

      echo
      SOMETEXT=$(echo $SOMETEXT | sed -n -e 's/^.*bitmask//p')
      MODEMASK=${SOMETEXT:1:18}
      echo "This device will accept an audio stream consisting of $reported_channels channels of audio in the $reported_audio_format format"
      if [[ "$reported_audio_format" != "$audio_format" ]]; then
         echo "WARNING: the audio format was changed from $audio_format to: $reported_audio_format"
      fi

      if [[ "$reported_rate" != "$sample_rate" ]]; then
         echo "WARNING: the sample rate was changed from $audio_rate to: $reported_rate"
      fi
      echo "The bitmask for this mode is: $MODEMASK"
      if [[ "$MODEMASK" == "0x0000000000000000" ]]; then
         echo '   This device does not use channel assignments.'
         echo '   All output channels should have their bitmask set to -3 (NONE)'
      else
         for (( channel_enum=0; channel_enum<=$CHANNEL_MAX; channel_enum++ ))
         do
            channel_bin=$((2**channel_enum))
            printf -v channel_hex '%x' "$channel_bin"
            channel_hex="0x$channel_hex"
            if [ $(( $MODEMASK & $channel_hex )) -ne 0 ]; then
               echo "   channel $channel_enum is used in this mode. Its channel mask is: $channel_hex"
            fi
         done
      fi
   fi
done
echo
