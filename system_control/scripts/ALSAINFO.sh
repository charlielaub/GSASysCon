#!/bin/bash 
PROG_INFO="written by Charlie Laub, 2016-2026, version 4.0"
DEFAULT_SAMPLE_RATE=44100   #if user does not supply a sample rate, use this
DEFAULT_FORMAT=S16LE   #if user does not supply format, use this
CHANNEL_MAX=29  #Gstreamer version 1.26 supports up to 29 audio channels
STD_SAMPLE_RATES='8000 11025 16000 22050 32000 44100 48000 88200 96000 176400 192000 352800 384000'
SUPPORTED_FORMATS='S16LE S16BE U16LE U16BE S24_32LE S24_32BE U24_32LE U24_32BE S32LE S32BE U32LE U32BE S24LE S24BE U24LE U24BE S20LE S20BE U20LE U20BE S18LE S18BE U18LE U18BE F32LE F32BE F64LE F64BE'

#an associative array maps Gstreamer format names to ALSA format names
#   This is used to check the equivalent ALSA format against what --dump-hw-params lists for the card
#Common audio formats:
#ALSA formats: 'S16_LE S16_BE U16_LE U16_BE S24_LE   S24_BE   S32_LE S32_BE FLOAT_LE FLOAT_BE'
#   GStreamer: 'S16LE  S16BE  U16LE  U16BE  S24_32LE S24_32BE S32LE  S32BE  F32LE    F32BE'
# NOTE: if there is NOT a match, compare the input to the full list of allowed Gstreamer formats and if it is a member then
#    prompt the user to decide to proceed or abort the remainder of the code.
declare -A GSTREAMER_TO_ALSA_FORMATS

GSTREAMER_TO_ALSA_FORMATS[S16LE]="S16_LE"
GSTREAMER_TO_ALSA_FORMATS[S16BE]="S16_BE"
GSTREAMER_TO_ALSA_FORMATS[U16LE]="U16_LE"
GSTREAMER_TO_ALSA_FORMATS[U16BE]="U16_BE"
GSTREAMER_TO_ALSA_FORMATS[S24_32LE]="S24_LE"
GSTREAMER_TO_ALSA_FORMATS[S24_32BE]="S24_BE"
GSTREAMER_TO_ALSA_FORMATS[S24LE]="S24_3LE"
GSTREAMER_TO_ALSA_FORMATS[S32LE]="S32_LE"
GSTREAMER_TO_ALSA_FORMATS[S32BE]="S32_BE"
GSTREAMER_TO_ALSA_FORMATS[F32LE]="FLOAT_LE"
GSTREAMER_TO_ALSA_FORMATS[F32BE]="FLOAT_BE"

                 
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
INFO[4]="Command line parameters are supplied as keyword-value pairs:"
INFO[5]="  mode=audio_mode (required): valid audio_mode values are play or record. Indicate which mode you wish to test."
INFO[6]="  device=device_name (required): the device_name is the alsa device to test, e.g. hw:1,0 or hw:CARD=DAC,DEV=0"
INFO[7]="  rate=sample_rate (optional): requested sample rate, e.g. 48000, 96000, etc. Default = 44100"
INFO[8]="  format=audio_format (optional): requested audio format, e.g. S16LE, S32LE, etc. Default = S16LE"
INFO[9]=" "
INFO[10]="NOTES:"
INFO[11]="  1. The actual sample rate may be the closest rate that is supported by the soundcard and not the requested rate."
INFO[12]="  2. Gstreamer supported audio formats: S8, U8, S16LE, S16BE, U16LE, U16BE, S24_32LE, S24_32BE, U24_32LE, U24_32BE, S32LE, S32BE, U32LE, U32BE, S24LE, S24BE, U24LE, U24BE, S20LE, S20BE, U20LE, U20BE, S18LE, S18BE, U18LE, U18BE, F32LE, F32BE, F64LE, F64BE"

#process the command line arguments in the form keyword=value:
declare -A ARGS
for arg in "$@"; do
  if [[ "$arg" == *=* ]]; then
    key="${arg%%=*}"
    value="${arg#*=}"
    ARGS["$key"]="$value"
  fi
done

#begin output with the program version info:
clear; echo; echo ${INFO[1]};
#if no arguments were supplied, print the help info 
if [ $# -eq 0 ]; then
   saveIFS=$IFS
   IFS=''
   echo
   for eachline in ${INFO[@]}
   do
      echo $eachline
   done
   echo
   IFS=$saveIFS
   exit 0
fi
echo

MESSAGE='' #the output for the user will be built in this string

if [[ "${ARGS[device]}" == '' ]]; then
   echo "FATAL ERROR: an ALSA device must be supplied as a command line parameter in the format device=device_name"
   exit
else
   ALSA_device="${ARGS[device]}"
   MESSAGE+="testing ALSA device: $ALSA_device "
fi
if [[ "${ARGS[mode]}" == 'play' ]]; then
   ALSA_mode='aplay'
   MESSAGE+="in play mode "
elif [[ "${ARGS[mode]}" == 'record' ]]; then
   ALSA_mode='arecord'
   MESSAGE+="in record mode "
else
   echo "FATAL ERROR: No audio mode supplied. The play or record mode must be indicated via a command line parameter in the format mode=play or mode=record"
   exit
fi
if [[ "${ARGS[rate]}" == '' ]]; then
   sample_rate=$DEFAULT_SAMPLE_RATE
   echo "No sample rate supplied - using the default sample rate of $sample_rate Hz"
else
   sample_rate="${ARGS[rate]}";
   if [[ "$STD_SAMPLE_RATES" == *"$sample_rate"* ]]; then
      MESSAGE+="at $sample_rate Hz "
   else
      echo "A sample rate of $sample_rate is not supported. Please use one of the following sample rates:"
      echo "$STD_SAMPLE_RATES"
      exit
   fi 
fi
if [[ "${ARGS[format]}" == '' ]]; then
   audio_format=$DEFAULT_FORMAT
   echo "No audio format supplied - trying the default audio format of $audio_format"
else
   audio_format="${ARGS[format]}"
   if [[ "$SUPPORTED_FORMATS" == *"$audio_format"* ]]; then
   MESSAGE+="in $audio_format format"
   else
      echo -n "The audio format $audio_format is not recognized. Please use one of the following Gstsreamer formats: "
      echo "$SUPPORTED_FORMATS"
      echo; echo "NOTE that Gstreamer formats do not use the underscore character that is used by ALSA."
      echo
      exit
   fi 
fi
echo $MESSAGE #confirm the test conditions to the user

#Get description of the ALSA card/device provided by the user
echo
get_ALSA_description $ALSA_device
retval=$?
if [[ "$retval" != "0" ]]; then
  #get_ALSA_description returns 0 on success, 1 on failure or to indicate that
  #  the program should exit
  exit
fi


#Write the ALSA information on this device
{ output="$( { timeout 1 $ALSA_mode -D $ALSA_device -q --dump-hw-params /dev/zero; } 2>&1 1>&3 3>&- )"; } 3>&1;

supported_audio_formats=${output#*Available formats:}

if [[ "$output" == *"busy"*  ]]; then 
   echo "$ALSA_device is busy and may be in use by another audio process. Please try again."; 
   exit; 
fi;
if [[ "$output" == *"error"*  ]]; then 
   echo "Trying to open $ALSA_device generated an error. Please check the device name and try again."; 
   exit; 
fi;
echo "ALSA info about $ALSA_device :"
output=${output#*--------------------}
output=${output%--------------------*}
echo "------------------------------------------------"
cat <<EOF
$output
EOF
echo "------------------------------------------------"
echo;echo

#convert the Gsteramer format into the equivalent ALSA format before checking with the device's capabilities
equivalent_ALSA_format=${GSTREAMER_TO_ALSA_FORMATS[$audio_format]}
if [[ "$supported_audio_formats" == *"$equivalent_ALSA_format"* ]]; then
   echo "The Gstreamer format $audio_format is supported by the card (as ALSA format $equivalent_ALSA_format.)"
   else
   echo "ERROR: the format $audio_format is NOT supported by $ALSA_device"
   echo "The supported audio formats for this card as reported by ALSA are:" 
   echo '   '$supported_audio_formats
   echo "Please change the Gstreamer format to one that is supported by $ALSA_device and try again."
   echo; echo "CONVERTING BETWEEN AUDIO FORMAT NAMES:"
   printf "%s %-12s %-10s \n" '   ' ALSA GStreamer
   echo '   ------------------------'
   for i in "${!GSTREAMER_TO_ALSA_FORMATS[@]}"
   do
      printf "%s %-12s %-10s \n" '   ' ${GSTREAMER_TO_ALSA_FORMATS[${i}]} ${i}
   done | sort -k1
   echo
   exit
fi


echo "Now testing the ability of $ALSA_device to ${ARGS[mode]} from 2 to $CHANNEL_MAX channels of audio."
echo "   The following channel counts are supported:"

for (( num_channels=2; num_channels<=$CHANNEL_MAX; num_channels++ ))
do
  if [[ "$ALSA_mode" == "aplay" ]]; then
     #pipeline and parsing of output when using play mode:
      SOMETEXT=$(timeout 3 gst-launch-1.0 -vm audiotestsrc wave=silence ! audio/x-raw,channels=$num_channels,format=$audio_format,rate=$sample_rate ! audioconvert ! alsasink device="$ALSA_device" 2>/dev/null )
      SOMETEXT=$(echo "$SOMETEXT" | grep "GstAlsaSink:alsasink0.GstPad:sink: caps")
      SOMETEXT=${SOMETEXT//'\'/''}
   else
      # pipeline and parsing when using record mode:
      SOMETEXT=$(timeout 3 gst-launch-1.0 -vm alsasrc device="$ALSA_device" ! audio/x-raw,channels=$num_channels,format=$audio_format,rate=$sample_rate ! queue ! fakesink 2>/dev/null )
      SOMETEXT=$(echo "$SOMETEXT" | grep "GstAlsaSrc:alsasrc0.GstPad:src: caps")
      SOMETEXT=${SOMETEXT//'\'/''}
   fi

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
      echo "An audio stream consisting of $reported_channels channels of audio in the $reported_audio_format format is supported."
      if [[ "$reported_audio_format" != "$audio_format" ]]; then
         echo "WARNING: the audio format was changed from $audio_format to: $reported_audio_format"
      fi

      if [[ "$reported_rate" != "$sample_rate" ]]; then
         echo "WARNING: the sample rate was changed from $audio_rate to: $reported_rate"
      fi
      echo "The bitmask for this mode is: $MODEMASK"
      if [[ "$MODEMASK" == "0x0000000000000000" ]]; then
         echo '   This device assigns channels by order of appearance instead of channel number.'
         echo '   All channels should have their channel value set to -3'
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
