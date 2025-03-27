#!/bin/bash
#..............................................................................#
#          GSASysCon: the Gsreamer Streaming Audio System Controller           #
                              VERSION_NUMBER=3.15
#..............................................................................#
#                                                                              #
#     Copyright (C) 2017 - 2025 by Charlie Laub                                #
#                                                                              #
#     This program is free software: you can redistribute it and/or modify     #
#     it under the terms of the GNU General Public License as published by     #
#     the Free Software Foundation, either version 3 of the License, or        #
#     (at your option) any later version.                                      #
#                                                                              #
#     This program is distributed in the hope that it will be useful,          #
#     but WITHOUT ANY WARRANTY; without even the implied warranty of           #
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            #
#     GNU General Public License for more details.                             #
#                                                                              #
#     You should have received a copy of the GNU General Public License        #
#     along with this program.  If not, see <http://www.gnu.org/licenses/>     #
#                                                                              #
#..............................................................................#
#                                                                              #
#     HELP AND USAGE INFO: invoke using -h or --help for usage information     #
#                                                                              #
#..............................................................................#

DEBUG_MODE=""  #set this variable to any non empty string to enable debug mode
               #  in debug mode the screen is not cleared and additional output
               #  is generated on the clients in the ~/gstreamer directory
               #debug mode can be toggled on/off from the UI using the D option 

#function definitions ---------------------------------------------------------

function commit_to_log {
  #add contents of passed parameter to log file, preceeeded by a time stamp
  #collect this message into the MESSAGE_COLLECTOR
  if [ "$COLLECT_MESSAGES" = true ]; then
    MESSAGE_COLLECTOR+="\n $1"
  fi
  if [[ "$1" == "" ]]; then
    TEXT=""
  else
    TEXT=$(date +"%b-%d-%Y %T")" : $1"
  fi
  echo -e "$TEXT" >> $LOGFILE_PATH/$LOG_FILENAME #append to log file on disk
  message="" #clear message string
} #end function 'commit_to_log'


function dB_to_volume {
  #converts integral dB levels between -30 and +10dB to volume level
  #return -1 upon failure
  local i=0;
  local db;
  local str
  local DBvalues=(-30 -29 -28 -27 -26 -25 -24 -23 -22 -21 -20 -19 -18 -17 -16 -15 -14 -13 -12 -11 -10 -9 -8 -7 -6 -5 -4 -3 -2 -1 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)
  local volume_level=(0.03162 0.03548 0.03981 0.04467 0.05012 0.05623 0.06310 0.07079 0.07943 0.08913 0.10000 0.11220 0.12589 0.14125 0.15849 0.17783 0.19953 0.22387 0.25119 0.28184 0.31623 0.35481 0.39811 0.44668 0.50119 0.56234 0.63096 0.70795 0.79433 0.89125 1.00000 1.12202 1.25893 1.41254 1.58489 1.77828 1.99526 2.23872 2.51188 2.81838 3.16228 3.548134 3.981072 4.466836 5.011872 5.623413 6.309573 7.079458 7.943282 8.912509 10.000000)
  #remove leading and trailing whitespace:
  db=`expr "$1" : "^\ *\(.*[^ ]\)\ *$"`
  #if the dB value begins with a '+' remove it:
  if [[ ${dB:0:1} == '+' ]]; then
    dB=${dB:1} # Strip off leading '+'
  fi
  for str in "${DBvalues[@]}"; do
  if [ "$str" = "$db" ]; then
    echo ${volume_level[$i]}
    return
  else
    ((i++))                                                                     
  fi
  done
  echo "-1"
}


function strindex {
#return position of substring $2 in string $1 or -1 if not found 
  x="${1%%$2*}"
  [[ $x = $1 ]] && echo -1 || echo ${#x}
}


function separate_field_identifier_from_field_contents {
#from a string in the format of 'field_identifier field_separator field_contents'
#  extract the field_identifier and field_contents into their respective variables.
#  Takes two arguments: (1) the field-separator and (2) the variable holding the 
#  string. If an error is encountered the function will return with return code 1.

  STR=$2
  STRLEN=${#STR}
  field_separator=$1
  field_separator_position=$(strindex "$STR" "$field_separator")
  if [ $field_separator_position = "-1" ]; then 
    return 1; 
  fi
  #extract the field identifier
  field_identifier=${STR:0:$field_separator_position}
  #remove any leading and trailing whitespace:
  field_identifier=`expr "$field_identifier" : "^\ *\(.*[^ ]\)\ *$"`
  #get field_contents
  field_contents=${STR:$field_separator_position+1:$STRLEN}
  #remove any comments
  comment_identifier_position=$(strindex "$field_contents" "#")
  if [ $comment_identifier_position != "-1" ]; then 
    #remove the comment
    field_contents=${field_contents:0:$comment_identifier_position}
  fi
  #remove leading and trailing whitespace:
  field_contents=`expr "$field_contents" : "^\ *\(.*[^ ]\)\ *$"`
  return 0
  #done!
}



function get_from_caps {
#takes two arguments: (1) the field-identifier and (2) the variable holding the
#  caps string. Before exiting, the function echos the extracted field_contents.
#  If an error is encountered the function will return with return code 1.
  STR=$2
  STRLEN=${#STR}
  field_separator=$1
  field_separator_position=$(strindex "$STR" "$field_separator")
  if [ $field_separator_position = "-1" ]; then 
  #no field separator found in the input so echo empty string
    return 1; 
  fi
  #extract the test up to and including the field identifier
  position=$field_separator_position+${#field_separator}
  field_identifier=${STR:0:$position}
  #get field_contents
  field_contents=${STR:$position:$STRLEN}
  #remove the equals sign from the field contents
  STR=$field_contents
  STRLEN=${#STR}
  field_separator="="
  field_separator_position=$(strindex "$STR" "$field_separator")
  if [ $field_separator_position = "-1" ]; then 
    #no field separator found in the input so echo empty string
    return 1;
  fi
  #extract the test up to and including the field identifier
  position=$field_separator_position+${#field_separator}
  field_identifier=${STR:0:$position}
  #get field_contents
  field_contents=${STR:$position:$STRLEN}
  #remove any text following the first comma
  comment_identifier_position=$(strindex "$field_contents" ",")
  if [ $comment_identifier_position != "-1" ]; then 
    #remove text after comma
    field_contents=${field_contents:0:$comment_identifier_position}
  fi
  #remove leading and trailing whitespace:
  field_contents=`expr "$field_contents" : "^\ *\(.*[^ ]\)\ *$"`
  return 0
  #done!
}



function valid_dotted_quad() {
#function will return 0 if IP address is valid IPv4 address, non-zero otherwise
  local ERROR=0
  oldIFS=$IFS
  IFS=.
  set -f
  set -- $1
  if [ $# -eq 4 ]
  then
    for seg
    do
      case $seg in
          ""|*[!0-9]*) ERROR=1;break ;; ## Segment empty or non-numeric char
          *) [ $seg -gt 255 ] && ERROR=2 ;;
      esac
    done
  else
    ERROR=3 ## Not 4 segments
  fi
  IFS=$oldIFS
  set +f
  echo $ERROR
}


function validate_client_IP {
#validate IPv4 address, and convert hostname to IP address when applicable
  local ADDRESS="$1"
  local resolved_IP
  #check if the supplied string indicates local-playback
  if [[ "$ADDRESS" == "local_playback" ]] || [[ "$ADDRESS" == "LOCAL_PLAYBACK" ]]; then
    #set LOCAL_CLIENT_INDEX to this CLIENT_INDEX
    if [[ $LOCAL_CLIENT_INDEX == "" ]]; then
      LOCAL_CLIENT_INDEX=$CLIENT_INDEX
      #set IP to -1 for this client
      IP[CLIENT_INDEX]=-1
    else
      message+=" ERROR: only one local playback client may been declared per system."
      commit_to_log "$message"
      error_flag=1
    fi
    return
  fi
  message=""
  #validate the address
  if [ $(valid_dotted_quad "$ADDRESS") -ne 0 ]; then
    #not an IP adress but it might be a hostname. Do a DNS lookup on it
    resolved_IP=""
    resolved_IP=$(dig +short $ADDRESS)
    if (( ${#resolved_IP} > 0 )); then
        message="$ADDRESS was resolved to address $resolved_IP."
        ADDRESS=$resolved_IP
    else
        message="ERROR: $ADDRESS is not a valid dotted quad IPv4 address"
        if [[ "$IO_MODE" == "preamp" ]]; then
          message+=" or LOCAL_PLAYBACK."
        else
          message+="."
        fi   
        error_flag=1
        commit_to_log "$message"
        return
    fi
  fi
  #now that we have a valid IP address, try to reach it
  ping -c 1 -w 2 "$ADDRESS" &>/dev/null
  if [ $? -ne 0 ] ; then
    #address not reachable, so set IP to -2 to flag this condition
    IP[CLIENT_INDEX]=-2
    message+=" WARNING: the client at $ADDRESS could not be reached."
    commit_to_log "$message"
    return
  fi
  #address is valid and reachable
  IP[CLIENT_INDEX]="$ADDRESS"
}



function process_volume_control_info {
#field_identifier is passed as $1
#field_contents is passed as $2
  case $1 in 
    VOLUME_CONTROL)
      #a volume control is specified using a string comprised of the following:
      #   type:ID where
      #      type is either 'card' or 'device' and
      #      ID identifies the control of that type, e.g. card number or device name. 
      #   the '>' character follows and then 
      #   the name of the scontrol on that card/device that the volume control should vary, and 
      #   optionally the '>' character followd by an action specifier 
      # Multiple cards and controls may be listed, each separated by a semicolon, e.g.:
      #  VOLUME_CONTROL = type:ID>control_name>action; type:ID>... etc.
      #The action specifier format is:
      #  the ! (not) or % (only) permission control character preceding either the 
      #    mute, unmute, toggle, or volume action keywords
      #  examples: 
      #    !mute (perform all actions except mute) 
      #    %volume (only perform volume control actions)
      local control_name
      local control_info
      local action
      local control_can_mute
      local max_level
      local each_control
      local -a VOLUME_CONTROLS
      local CONTROLS_ARE_VALID="true"
      #set muting flag:
      #  0 = muting not available
      #  1 = muting performed via mute/unmute
      #  2 = muting performed via toggle
      MUTING_IS_AVAILABLE=0 #init to 0 and re-check at end of function
      message="" #clear out any existing messages

      #parse by semicolons into VOLUME_CONTROLS array
      IFS=';' read -r -a VOLUME_CONTROLS <<< "$2"

      #validate controls and check availability of muting      
      for each_control in "${VOLUME_CONTROLS[@]}"
      do
        #extract whereis_control, control_name, and action
        IFS='>' read control_info control_name action <<< $each_control
        #remove leading and trailing whitespaces from variables:
        control_info=`expr "$control_info" : "^\ *\(.*[^ ]\)\ *$"`
        control_name=`expr "$control_name" : "^\ *\(.*[^ ]\)\ *$"`
        action=`expr "$action" : "^\ *\(.*[^ ]\)\ *$"`
        if [ ${#action} -gt 1 ]; then
          #separate the action string into its components
          permission_control=${action:0:1}
          action=${action:1}
        else
          #no specific action info was provided, so set action=ALL for this control
          action="ALL"
          permission_control=""
        fi
        #separate control_info into type and ID
        IFS=':' read ctl_type ctl_ID <<< "$control_info"
        if [[ "${ctl_type:0:1}" == "c" ]] || [[ "${ctl_type:0:1}" == "C" ]]; then
          #the ctl_type is an ALSA card, so reset ctl_type to '-c'
          ctl_type="-c"
        elif [[ "${ctl_type:0:1}" == "d" ]] || [[ "${ctl_type:0:1}" == "D" ]]; then
          #the ctl_type is an ALSA device, so reset ctl_type to '-D'
          ctl_type="-D"
        else
          #ERROR: card/device keyword was not found. Create error message
          message+="WARNING: the type of volume card/device was not properly provided!"
          continue
        fi
        #try to get the control information using amixer
        amixer sget $ctl_type $ctl_ID $control_name >/dev/null 2>&1
        #test the return code to see if the control exists
        if [ $? -ne 0 ]; then
          message+="WARNING: no ALSA control named $control_name was found for the card/device specified"
          continue
        fi
        #control exists. 
        #Check if control can be muted
        local caps
        local has_muting=1
        caps=$( amixer $ctl_type $ctl_ID sget $control_name | grep Capabilities )
        #controls with muting capability include the word 'switch' in the list of capabilities
        if [[ ! $caps == *"switch"* ]]; then
          #message+="WARNING: MUTING/UNMUTING is not available for control $control_name"
          has_muting=0
        fi
        #get the volume control's upper limit and save in array
        max_level=$( amixer $ctl_type $ctl_ID sget $control_name | grep Limits | cut -f2- -d- )
        #Add this control to the appropriate arrays according to the intended action:
        case $action in
          ALL)
            VOL_CTL_TYPE+=("$ctl_type") 
            VOL_CTL_ID+=("$ctl_ID")
            VOL_CTL_NAME+=("$control_name")
            VOL_CTL_MAX_LEVEL+=("$max_level")
            if [ $has_muting -gt 0 ]; then 
              MUTE_CTL_TYPE+=("$ctl_type")
              MUTE_CTL_ID+=("$ctl_ID")
              MUTE_CTL_NAME+=("$control_name")
              UNMUTE_CTL_TYPE+=("$ctl_type")
              UNMUTE_CTL_ID+=("$ctl_ID")
              UNMUTE_CTL_NAME+=("$control_name")
            fi
          ;;
          mute)
            if [[ $permission_control == "%" ]]; then
              if [ $has_muting -gt 0 ]; then 
                MUTE_CTL_TYPE+=("$ctl_type")
                MUTE_CTL_ID+=("$ctl_ID")
                MUTE_CTL_NAME+=("$control_name")
              fi
            elif  [[ $permission_control == "!" ]]; then
              VOL_CTL_TYPE+=("$ctl_type") 
              VOL_CTL_ID+=("$ctl_ID")
              VOL_CTL_NAME+=("$control_name")
              VOL_CTL_MAX_LEVEL+=("$max_level")
              if [ $has_muting -gt 0 ]; then 
              UNMUTE_CTL_TYPE+=("$ctl_type")
              UNMUTE_CTL_ID+=("$ctl_ID")
              UNMUTE_CTL_NAME+=("$control_name")
              fi
            fi
          ;;
          unmute)
            if [[ $permission_control == "%" ]]; then
              if [ $has_muting -gt 0 ]; then 
                UNMUTE_CTL_TYPE+=("$ctl_type")
                UNMUTE_CTL_ID+=("$ctl_ID")
                UNMUTE_CTL_NAME+=("$control_name")
              fi
            elif  [[ $permission_control == "!" ]]; then
              VOL_CTL_TYPE+=("$ctl_type") 
              VOL_CTL_ID+=("$ctl_ID")
              VOL_CTL_NAME+=("$control_name")
              VOL_CTL_MAX_LEVEL+=("$max_level")
              if [ $has_muting -gt 0 ]; then 
                MUTE_CTL_TYPE+=("$ctl_type")
                MUTE_CTL_ID+=("$ctl_ID")
                MUTE_CTL_NAME+=("$control_name")
              fi
            fi
          ;;
          muting | toggle )
            if [[ $permission_control == "%" ]]; then
              if [ $has_muting -gt 0 ]; then 
                MUTE_CTL_TYPE+=("$ctl_type")
                MUTE_CTL_ID+=("$ctl_ID")
                MUTE_CTL_NAME+=("$control_name")
                UNMUTE_CTL_TYPE+=("$ctl_type")
                UNMUTE_CTL_ID+=("$ctl_ID")
                UNMUTE_CTL_NAME+=("$control_name")
              fi
            elif  [[ $permission_control == "!" ]]; then
              VOL_CTL_TYPE+=("$ctl_type") 
              VOL_CTL_ID+=("$ctl_ID")
              VOL_CTL_NAME+=("$control_name")
              VOL_CTL_MAX_LEVEL+=("$max_level")
            fi
          ;;
          volume)
            if [[ $permission_control == "%" ]]; then
              VOL_CTL_TYPE+=("$ctl_type") 
              VOL_CTL_ID+=("$ctl_ID")
              VOL_CTL_NAME+=("$control_name")
              VOL_CTL_MAX_LEVEL+=("$max_level")
            elif  [[ $permission_control == "!" ]]; then
              if [ $has_muting -gt 0 ]; then 
                MUTE_CTL_TYPE+=("$ctl_type")
                MUTE_CTL_ID+=("$ctl_ID")
                MUTE_CTL_NAME+=("$control_name")
                UNMUTE_CTL_TYPE+=("$ctl_type")
                UNMUTE_CTL_ID+=("$ctl_ID")
                UNMUTE_CTL_NAME+=("$control_name")
              fi
            fi
          ;;
        esac

      done #for loop over each_control
      
      #There must be at least 1 volume control to enable VOLUME CONTROL
      if [ ${#VOL_CTL_TYPE[@]} -eq 0 ]; then
        message+="VOLUME CONTROL will not be available."
      fi
      #There must be at least 1 mute and 1 unmute control for muting to work
      if [ ${#MUTE_CTL_TYPE[@]} -gt 0 ] && [ ${#UNMUTE_CTL_TYPE[@]} -gt 0 ]; then
        MUTING_IS_AVAILABLE=1
        if [[ "$action" == "toggle" ]]; then MUTING_IS_AVAILABLE=2; fi
      else
        message+="MUTING will not be available as part of volume control."
      fi
      #write any messages to the logfile
      if [[ $message != "" ]]; then
        commit_to_log $message
      fi
      ;;
    VOLUME_CONTROL_TIMEOUT)
      VOLUME_CONTROL_TIMEOUT=$2
      ;;
    VOLUME_CONTROL_STYLE)
      #Get volume control style. If num columns is not specified set a default of 50
      IFS=',' read -r VOLUME_CONTROL_STYLE VOLUME_CONTROL_COLS <<< "$2"
      if [[ "$VOLUME_CONTROL_COLS" == "" ]]; then VOLUME_CONTROL_COLS=50; fi
      ;;
  esac
}


function is_valid_mixing_expression {
  local value
  value=$1
  # check if value is a decimal number between -1 and 1, exclusive of these limits
  if [[ "$value" =~ ^[-+]?0(\.[0-9]+)?$ ]]
  then
      # value lies between -1 and 1.0 and is valid for gstreamer mixing expressions
      return 0
  else
    #now check if value equals -1 or 1 as whole number or decimal with any number of trailing zeros
    if [[ "$value" =~ ^[-+]?1(\.[0]*)?$ ]]; then
      # yes, value is valid for gstreamer mixing expressions
      return 0
    else
      # no, value is outside of -1 to 1 and/or not valid for gstreamer mixing expression
      return 1
    fi
  fi
}


function process_server_mixing_expressions {
  #convert user supplied mixing expressions into gstreamer audiomixmatrix format
  #perform checks for proper formatting.
  #the mixmatrix_string is produced, or set to an empty string if errors are found  
  local mask_string
  local all_mix_expressions
  local -a channel_mix_expression
  field_identifier=""
  field_contents=""
  all_mix_expressions=$*
  if [[ "$all_mix_expressions" =~ [A-Za-z]+ ]]; then
    message+=" ERROR in user-suppiled mixing expression: $all_mix_expressions"
    commit_to_log "$message"
    error_flag=1
    mixmatrix_string=''
    return 1
  fi
  IFS=' ' read -r -a channel_mix_expression <<< "$all_mix_expressions"
  num_output_channels=${#channel_mix_expression[@]}
  # calculate the mask value from the number of channels
  #   NOTE: this determines the numbering of input channels. This numbering should be used when referencing
  #     server channels at the client side, with the first being channel 0, then channel 1, channel 2, etc.  
  mask_string=$((2**$num_output_channels-1))
  # create the beginning of the mixmatrix string
  mixmatrix_string='audiomixmatrix in-channels=2 out-channels='$num_output_channels' channel-mask='$mask_string' matrix="<<(double)'
  # assemble it channel by channel, checking each for validity
  for (( channel=0; channel<$num_output_channels; channel++ )); do
    IFS=',' read -r -a mix_expression <<< "${channel_mix_expression[$channel]}"
# ADD CHECK HERE: ${#mix_expression[@]} should always be equal to num_input_channels, which should be added as a global variable !
#   At the end of the function set num_input_channels = num_output_channels so that subsequent calls will function???
#   Or add an input parameter to the SERVER_CHANNEL_MIXING format where the user can give the number of input channels?
#   Or just compare the number of input channels within each mixing expression to make sure they are constant?
    if ! ( is_valid_mixing_expression "${mix_expression[0]}" && is_valid_mixing_expression "${mix_expression[1]}" ); then
      message+=' ERROR - '"${channel_mix_expression[$channel]}"' IS AN INVALID MIXING EXPRESSION!'
      commit_to_log "$message"
      error_flag=1
      mixmatrix_string=''
      return 1
    fi
    if [ "$channel" -eq 0 ];
    then
      mixmatrix_string+="${mix_expression[0]}"', (double)'"${mix_expression[1]}"'>'
    else
      mixmatrix_string+=', <'"${mix_expression[0]}"','"${mix_expression[1]}"'>'
    fi
  done
  # append the end of the mixmatrix string
  mixmatrix_string+='>" ! audio/x-raw,channels='"$num_output_channels"' !'
} #end function process_server_mixing_expressions


function get_system_or_stream_parameter {
#pass a string containing a line of text as argument
#these parameters must be declared before any client definitions
#any parameter definitions here will override the default values
#  assigned in the function 'build_system_configuration_from_file'
  field_identifier=""
  field_contents=""
  separate_field_identifier_from_field_contents "=" "$1"
  case $field_identifier in 
    SERVER_RTBIN_PARAMETERS)
      SERVER_RTPBIN_PARAMS=$field_contents   #string for all rtbin params
      ;;
    CLIENT_RTBIN_PARAMETERS)
      CLIENT_RTPBIN_PARAMS[0]=$field_contents   #string for all rtbin params
      ;;
    STREAM_BITS)
      STREAM_BITS[0]=$field_contents
      ;;
    STREAM_RATE)
      STREAM_RATE[0]=$field_contents
      ;;
    SINK_FORMAT)
      SINK_FORMAT[0]=$field_contents
      ;;
    PATH)
      INFO_PATH[0]=$field_contents
      ;;
    CLIENT_INTERLEAVE_BUFFER)
      INTERLEAVE_BUFFER[0]=$(( $field_contents*1000000 )) #multiply by 10^6 to convert millisec to nanosec
      ;;
    SERVER_INTERLEAVE_BUFFER)
      SERVER_BUFFER=$(( $field_contents*1000000 )) #multiply by 10^6 to convert millisec to nanosec
      ;;
    RESAMPLER_QUALITY)
      RESAMPLER_QUALITY=$field_contents
      ;;
    VOLUME*)
      if [[ "$IO_MODE" == "preamp" ]]; then
        process_volume_control_info $field_identifier $field_contents
      fi
      ;;
    GAIN_ADJUST_DB)
      GAIN_ADJUST=$field_contents
      ;;
    SERVER_CHANNEL_MIXING)
      # this functionality is used to create new channels from existing ones on the server, e.g. mono=L+R
      # format: SERVER_CHANNEL_MIXING = mix_expression0 mix_expression1 ... mix_expression_N 
      # input is assumed to be 2 channels
      # each mix_expression has the format value1,value2 with no space between the comma and each value 
      # the mix_expression weighting values can range from -1 to 1 only
      # each mix_expression is the amount of each input channel sent to output channel 1..N
      # multiple mix_expressions are separated by one or more spaces and must not contain a space internally
      # once server channel mixing has been used, channels are referenced in order of their appearance in the 
      #    list of mixing expressions, with the first being channel 0, the second channel 1, etc.
      process_server_mixing_expressions "$field_contents"
      ;;
  esac
}

function get_client_parameter {
#pass a string containing a line of text as argument
  field_identifier=""
  field_contents=""
  IFS=''
  separate_field_identifier_from_field_contents "=" "$1"
  case $field_identifier in
    ACCESS)
      ACCESS[CLIENT_INDEX]=$field_contents
      ;;
    CLIENT_SINK)
      #process client sink and append code to existing CLIENT_SINK_CODE, if any
      SINK_INDEX=$((SINK_INDEX+1)) #increment the SINK_INDEX 
      CLIENT_SINK_CODE="$CLIENT_SINK_CODE   "'audiointerleave name=output'$SINK_INDEX' latency='"${INTERLEAVE_BUFFER[CLIENT_INDEX]}"' ! '
      #add the user-supplied sink info to the sink code
      CLIENT_SINK_CODE+="$field_contents"
      ;;
    CLIENT_RTBIN_PARAMETERS)
      CLIENT_RTPBIN_PARAMS[CLIENT_INDEX]=$field_contents   #units of millisec
      ;;
    CLIENT_INTERLEAVE_BUFFER)
      INTERLEAVE_BUFFER[CLIENT_INDEX]=$(( $field_contents*1000000 )) #multiply by 10^6 to convert millisec to nanosec
      ;;
    PATH)
      INFO_PATH[CLIENT_INDEX]=$field_contents
      ;;
    OTHER_COMMAND_BEFORE_LAUNCH)
      OTHER_COMMAND_BEFORE_LAUNCH[CLIENT_INDEX]=$field_contents
      ;;
    OTHER_COMMAND_AFTER_LAUNCH)
      OTHER_COMMAND_AFTER_LAUNCH[CLIENT_INDEX]=$field_contents
      ;;
    LOCAL_SCRIPT_BEFORE_LAUNCH)
      LOCAL_SCRIPT_BEFORE_LAUNCH[CLIENT_INDEX]=$field_contents
      ;;
    LOCAL_SCRIPT_AFTER_LAUNCH)
      LOCAL_SCRIPT_AFTER_LAUNCH[CLIENT_INDEX]=$field_contents
      ;;
    OTHER_COMMAND_BEFORE_TERMINATE)
      OTHER_COMMAND_BEFORE_TERMINATE[CLIENT_INDEX]=$field_contents
      ;;
    OTHER_COMMAND_AFTER_TERMINATE)
      OTHER_COMMAND_AFTER_TERMINATE[CLIENT_INDEX]=$field_contents
      ;;
    LOCAL_SCRIPT_BEFORE_TERMINATE)
      LOCAL_SCRIPT_BEFORE_TERMINATE[CLIENT_INDEX]=$field_contents
      ;;
    LOCAL_SCRIPT_AFTER_TERMINATE)
      LOCAL_SCRIPT_AFTER_TERMINATE[CLIENT_INDEX]=$field_contents
      ;;
    STREAM_BITS)
      STREAM_BITS[CLIENT_INDEX]=$field_contents
      ;;
    STREAM_RATE)
      STREAM_RATE[CLIENT_INDEX]=$field_contents
      ;;
    SINK_FORMAT)
      SINK_FORMAT[CLIENT_INDEX]=$field_contents
      ;;
    RESAMPLER_QUALITY)
      RESAMPLER_QUALITY=$field_contents
      ;;
    SYNCHRONIZED_PLAYBACK)
      #by default SYNCHRONIZED_PLAYBACK is disabled
      #the only acceptable values in the input file are true and false
      if [[ "$field_contents" == "true" ]]; then
        SYNCHRONIZED_PLAYBACK[CLIENT_INDEX]="enable"
      fi
      ;;
  esac
}


function sync_files_between_FD_and_RAM_FS {
  #synchronizes files between the RAM FS and files on the fixed disk
  #this function may be passed a file pathname as a parameter
  #  only the file specified as a parameter is synchronized
  #  if no parameter is given, all files in the current directory will be synchronized

  if [[ $RAM_FS_ROOT == "" ]]; then
    #no RAM FS ROOT dir was provided, so all file operations are taking place on the fixed disk
    #therefore no need to synchronize RAM FS copy to FD version 
    return; 
  fi
  #First, assume we will do all files in the current dir
  local target="*"
  local THIS_DIR=$(pwd) #start with full path to the current system directory
  THIS_DIR=$(basename $THIS_DIR) #then extract the current system directory
  #if a parameter was passed it is the filename to sync. revise target and THIS_DIR 
  if [ "$#" -gt 0 ]; then
    target=$(basename "$1")
    THIS_DIR=$(basename $(cd $(dirname "$1") && pwd -P))
  fi
  #cp -u SOURCE DESTINATION: copy the file only if source is newer than destination 
  local FILES_ON_FD
  local COPY_DESTINATION
  FILES_ON_FD=$FD_FS_ROOT'/'$SYSTEMS_rPATH'/'$THIS_DIR'/'$target
  COPY_DESTINATION=$RAM_FS_ROOT'/'$SYSTEMS_rPATH'/'$THIS_DIR
  cp -u "$FILES_ON_FD" "$COPY_DESTINATION"
}


function replace_placeholders_in_client_code {   
   #THIS CODE IS RUN ONCE FOR EACH CLIENT AFTER ALL ITS ROUTES HAVE BEEN PROCESSED
   #NOTE: for streaming clients, CLIENT_CODE will be run on the client but
   #      for local-playback clients the CLIENT_CODE is run on the server
   #Based on how many times each channel is used create tees, and then replace placeholders sources for this client 
   #channel i: the server input channel used by the client and 
   #channel_position: the position of channel i in the RTP stream sent from server to client

   channel_position=-1 
   for i in ${!SOURCE_USAGE[@]}; do 
      if [[ ${IP[CLIENT_INDEX]} == '-2' ]]; then continue; fi #the IP address is invalid
      if [[ ${IP[CLIENT_INDEX]} == '-1' ]]; then
         channel_position=$i #for the local-playback client, use the server-side channel number directly
      else
         ((channel_position++)) #for streaming clients, use the order of appearance
      fi
      #build a list of server input channels used by this client, in increasing order
      CLIENT_CHANNEL_USE[CLIENT_INDEX]+="$i "   
      counter="${SOURCE_USAGE[i]}"
      #increment the global count for server channel i by the counter.
      if [[ "$counter" == "" ]]; then 
         echo "this source not used!"  #this statement should never run 
         continue
      else
        if [[ ${IP[CLIENT_INDEX]} == '-1' ]]; then
          #for local clients, add the total channel use to the GLOBAL_SOURCE_USAGE
          GLOBAL_SOURCE_USAGE[i]=$((GLOBAL_SOURCE_USAGE[i]+counter))
        else
          #for streaming clients, add just increment the GLOBAL_SOURCE_USAGE
          # if/when counter is non-zero, this indicates the channel is used by  
          #  the streaming client, so increment its GLOBAL_SOURCE_USAGE by ONE 
          GLOBAL_SOURCE_USAGE[i]=$((GLOBAL_SOURCE_USAGE[i]+1))
        fi
      fi
      #for local clients, placeholders will be replaced in the function 
      #   build_gstreamer_pipeline so skip remaining code
      if [[ ${IP[CLIENT_INDEX]} == '-1' ]]; then
       continue
      fi
      #code continues for streaming clients...  
      if [ $counter -lt 2 ]; then
         #this channel only used once by the client
         #replace placeholder with deinterleaved src channel
         CLIENT_CODE="${CLIENT_CODE//"SOURCE_FOR_CH$i"/"input.src_$channel_position"}" #removed: ' ! queue'   
      else 
        #prepend to client code a tee of deinterleaved src (removed queue ! just prior to tee) 
        CLIENT_CODE=" input.src_$channel_position"' ! tee name=input_ch'"$channel_position  $CLIENT_CODE"   
        #replace placeholder with teed deinterleave src + queue
        CLIENT_CODE="${CLIENT_CODE//"SOURCE_FOR_CH$i"/"input_ch$channel_position"'. ! queue'}"   
      fi
   done
} #end function replace_placeholders_in_client_code


function consolidate_existing_client_code {
  # consolidates ROUTE >> CLIENT_CODE + CLIENT_SINK_CODE >> GST_CLIENT_CODE
  #    This function is called at EOF and at the declaration of each new client
  #    Any outstanding (non-empty) ROUTE_CODE must be copied into the CLIENT_CODE string, and placeholders replaced
  #    Variables are reset to empty string upon completion

   if [[ "$ROUTE_CODE" != "" ]]; then
      #append the remaining ROUTE_CODE into CLIENT_CODE
      CLIENT_CODE+="    $ROUTE_CODE"
      #reset ROUTE_CODE to empty string
      ROUTE_CODE=""
      READ_ROUTE_INFO="false"
   fi
   if [[ "$CLIENT_CODE" == "" ]]; then
      #if CLIENT_CODE is empty, no ROUTEs were declared and client is invalid. Return an error
      message="No ROUTEs were declared for client ${IP[CLIENT_INDEX]}. Aborting system launch."
      error_flag=1
      return
   fi
   #replace placeholders
   replace_placeholders_in_client_code  
   #copy CLIENT_SINK_CODE and CLIENT_CODE into GST_CLIENT_CODE[] for this client
   GST_CLIENT_CODE[CLIENT_INDEX]="$CLIENT_SINK_CODE   $CLIENT_CODE"
   #reset CLIENT_CODE to empty string
   CLIENT_CODE=""
} #end function consolidate_existing_client_code


function process_input_mixing_expression {   
   local expression=$1
   local subexpression

   #if the first character of the output_ch_expression is not a + or - prepend a +
   if [[ ${expression:0:1} != '+' ]] && [[ ${expression:0:1} != '-' ]]; then
      expression="+${expression}"
   fi

   #get the number of + and - characters in the channel_expression
   plus_index="${expression//[^+]}"
   plus_index="${#plus_index}"
   minus_index="${expression//[^-]}"
   minus_index="${#minus_index}"
   subexpression_count=$(( $plus_index + $minus_index ))
   if [ "$subexpression_count" -gt 1 ]; then
      #the channel_expression consists of one or more subexpressions
      #create a MIXER to process the mix expression and prepend this to the ROUTE_END_CODE specified by the user
      ROUTE_CODE='   audiomixer name=mixer'"$MIXER_INDEX latency=${INTERLEAVE_BUFFER[CLIENT_INDEX]} ! "$ROUTE_END_CODE
      #set the target for this route to the mixer that was just created
      target='mixer'"$MIXER_INDEX"'.'
      ((MIXER_INDEX++))
   else
      #expression is a single channel - no mixer is needed. The target is just the ROUTE_END_CODE specified by the user
      ROUTE_CODE=""
      target=$ROUTE_END_CODE
   fi

   if [ -n "$subexpression" ]; then unset subexpression; fi   
   counter=0
   #split the channel_expression into an array of subexpressions
   while [ 1 -eq 1 ]
   do
      #find position of first + and first - in string, if any, starting with the second character
      plus_index=$(strindex "${expression:1}" '+')
      minus_index=$(strindex "${expression:1}" '-')
      if (( $plus_index > 0 )) && (( $minus_index > 0 )); then
         #if there are both + and - the string will be split at the one that comes first
         split_point="$(( plus_index < minus_index ? plus_index : minus_index ))"
      elif (( $plus_index > 0 )); then
         #plusses only, so split the string at the first one
         split_point=$plus_index
      elif (( $minus_index > 0 )); then
         #minuses only, so split the string at the first one
         split_point=$minus_index
      else 
         #no other + or - were found after the second character, so
         #only a single subexpression remains
         subexpression[$counter]=$expression
         break; 
      fi
      split_point=$((split_point+1))

      #split off the part of what remains of the mixing expression, up to the split point
      subexpression[$counter]=${expression:0:$split_point}
      expression=${expression:$split_point}
      ((counter++))
   done

   #create gstreamer code from each subexpression, using placeholders for source channels.
   for (( counter=0 ; counter < subexpression_count ; counter++ ))
   do
      #parse the subexpression into scalar and channel_id components and then gstreamer elements
      #prepend code to existing ROUTE_CODE so that ROUTE_END_CODE remains at end of ROUTE_CODE string
      expression=${subexpression[counter]}
      if [[ $expression != *'*'* ]]; then
         channel_id="${expression:1}"
         if [[ "${expression:0:1}" = "+" ]]; then
            scalar=""
            ROUTE_CODE=" SOURCE_FOR_CH$channel_id ! $target$ROUTE_CODE"
            if [[ ${ROUTE_START:0:1} == [0-9] ]]; then ((SOURCE_USAGE[$channel_id]++)); fi
         else
            scalar="-1.0"
            ROUTE_CODE=" SOURCE_FOR_CH$channel_id ! audioamplify amplification=$scalar ! $target$ROUTE_CODE"
            if [[ ${ROUTE_START:0:1} == [0-9] ]]; then ((SOURCE_USAGE[$channel_id]++)); fi
         fi
         channel_id=${expression:1}
      else
         oldIFS=$IFS
         IFS="*"
         read scalar channel_id <<< "$expression"
         IFS=$oldIFS
         if [[ "${scalar:0:1}" == "+" ]]; then
            scalar="${scalar:1}"
         fi
         ROUTE_CODE=" SOURCE_FOR_CH$channel_id ! audioamplify amplification=$scalar ! $target$ROUTE_CODE"
         if [[ ${ROUTE_START:0:1} == [0-9] ]]; then ((SOURCE_USAGE[$channel_id]++)); fi
      fi
   done
} #end function process_input_mixing_expression



function pre_process_file {
#pre-processing performs several functions while reading in the system_configuration file from disk
#  * route cloning
#  * user variable substitutions
#  * mathematical computations where indicated
#  this function takes one parameter, the name of the file to pre-process.
#  the function may be recursively called if the INSERT_FROM_FILE command is found

  #test if the file with name $1 exists. Throw error if DNE
  cat $1 > /dev/null
  if ! [ $? -eq 0 ]; then
    message="ERROR: the file $1 was not found"
    error_flag=1
    return
  fi  

  local user_route_elements=""
  local route_and_clones
  local capture_multiline_variable=false
  local multiline_variable_contents
  local MLV_name
  local preprocessing_clients=false
  local -a tokens
  local var_name
  local separator_char=' '
  local num_tokens
  local pattern
  all_MLV_names=$separator_char #initialize with a separator character
  all_SLV_names=$separator_char #initialize with a separator character

  while IFS='' read -r ONE_LINE || [[ -n "$ONE_LINE" ]]; do
    #check for and remove any comments on the line (comments begin with a '#')
    comment_identifier_position=$(strindex "$ONE_LINE" "#")
    if [ $comment_identifier_position != "-1" ]; then 
      #remove the comment
      ONE_LINE=${ONE_LINE:0:$comment_identifier_position}
    fi
    #remove any leading and trailing whitespace
    ONE_LINE=`expr "$ONE_LINE" : "^\ *\(.*[^ ]\)\ *$"`
    if [[ "$ONE_LINE" == "" ]] || [[ "$ONE_LINE" =~ ^[[:blank:]]+$ ]]; then 
      #if ONE_LINE is now blank, just skip to the next line
      continue
    fi
    #convert tabs to space characters
    ONE_LINE=${ONE_LINE//$'\t'/ }

    if [[ $preprocessing_clients == 'true' ]]; then
      #In this mode, we perform multi-line variable replacement and parameter substitution
      #  Single-line variable replacement is performed in the function build_system_configuration_from_file
      #    only after all other pre-processing has been completed
      #Check if line is a multi-line variable name and optional parameter-value pairs
      #split ONE_LINE into tokens
      tokens=() #clear the tokens array
      IFS=' '; read -a tokens <<< "$ONE_LINE"
      #remove all remaining whitespaces, tabs, etc. from tokens
      num_tokens=${#tokens[@]}
      for (( i=0; i<$num_tokens; i++ )); do
        tokens[$i]=${tokens[$i]//[[:blank:]]/}
      done      
      #check first token for membership of all_MLV_names
      pattern="$separator_char${tokens[0]}$separator_char"
      if [[ $all_MLV_names =~ $pattern ]]; then
        #line starts with a user-variable name. Replace var name with var contents
        var_name=${BASH_REMATCH[0]}
        var_name=${var_name//$separator_char} #remove the separation characters
        ONE_LINE=${multiline_variables[$var_name]}
        #check for additional tokens in the form of parameter=value and
        # perform subsitution within ONE_LINE
        num_tokens=${#tokens[@]}
        for (( i=1; i<$num_tokens; i++ )); do
          # perform subsitution of user-supplied parameter values, if any, within ONE_LINE
          field_identifier=""
          field_contents=""
          separate_field_identifier_from_field_contents "=" "${tokens[$i]}"
          # perform subsitution
          ONE_LINE=${ONE_LINE//$field_identifier/$field_contents}
        done
        # perform subsitution of the MLV's default values, if any, within ONE_LINE
        tokens=()  #clear the tokens array
        #if defaults exist, parse them into tokens
        if [ ${multiline_defaults[$var_name]+_} ]; then
          IFS=' '; read -a tokens <<< "${multiline_defaults[$var_name]}"
        fi
        num_tokens=${#tokens[@]}
        #loop over the tokens
        for (( i=0; i<$num_tokens; i++ )); do
          #parse the token into field identifier and field contents
          field_identifier=""
          field_contents=""
          separate_field_identifier_from_field_contents "=" "${tokens[$i]}"
          # perform subsitution
          ONE_LINE=${ONE_LINE//$field_identifier/$field_contents}
        done
      fi
    fi #end of if [[ $preprocessing_clients == 'true' ]]

    #parse the line into field identifier and field contents
    field_identifier=""
    field_contents=""
    separate_field_identifier_from_field_contents "=" "$ONE_LINE"

    if [[ $preprocessing_clients == 'false' ]]; then
      #In this mode, check for user-defined multiline variables, and file insertion directives
      #  NOTE that definition of user variables or file replcement statements are not 
      #    permitted after the first client definition appears in the system config file
      #
      #USAGE NOTES: user single-line variables are defined via the statement:
      #  DEFINE_VARIABLE var_name = var_value
      #multiline variable contents are defined between lines that contain the statements:
      #  DEFINE_MULTILINE_VARIABLE var_name
      #and
      #  END_MULTILINE_VARIABLE
      #any value or lines so defined are substituted later in place of var_name

      if [[ $ONE_LINE == 'END_MULTILINE_VARIABLE'* ]]; then
        capture_multiline_variable=false
        #pushback new associative array key,value pair:
        multiline_variables[$MLV_name]=${multiline_variable_contents%??} #removes trailing newline
        multiline_variable_contents=""
        continue;
      fi
      #if the code is capturing a multiline user variable, copy the line into the var
      #  and append a newline
      if [[ $capture_multiline_variable == "true" ]]; then
        if [[ $ONE_LINE == 'DEFAULT_VALUES'* ]]; then
          multiline_defaults[$MLV_name]=$ONE_LINE
        else
          multiline_variable_contents+="$ONE_LINE\n"
        fi
        continue;
      fi
      #check if this is the start of the def of a multiline user var
      if [[ $ONE_LINE == 'DEFINE_MULTILINE_VARIABLE'* ]]; then
        field_identifier=${ONE_LINE#*_VARIABLE}
        #remove all whitespaces, tabs, etc:
        field_identifier=${field_identifier//[[:blank:]]/}
        MLV_name="$field_identifier"
        all_MLV_names="$all_MLV_names$MLV_name$separator_char" #add trailing separator_char after each var name
        capture_multiline_variable=true 
        continue;
      fi
      #check if this is a single line user var
      if [[ $field_identifier == 'DEFINE_VARIABLE'* ]]; then
        field_identifier=${field_identifier#*_VARIABLE}
        #remove leading and trailing whitespace:
        field_identifier=`expr "$field_identifier" : "^\ *\(.*[^ ]\)\ *$"`
        #pushback new associative array key,value pair:
        singleline_variables[$field_identifier]=$field_contents
        all_SLV_names+="$field_identifier$separator_char" #add trailing separator_char after each var name
        continue
      fi
      
      if [[ $ONE_LINE == *'INSERT_FROM_FILE'* ]]; then
        field_contents=${ONE_LINE#*_FROM_FILE}
        #remove leading and trailing whitespace:
        field_contents=`expr "$field_contents" : "^\ *\(.*[^ ]\)\ *$"`
        if [ ${field_contents:0:1} = "~" ]; then
          #oops, first character is the tilde. Need to expand it.
          #replace the tilde with the HOME path for the user
          field_contents=${HOME}${field_contents:1}
        fi
        #check if a complete path was specified. If not prepend the FILTER_DEFS_PATH
        if ! [ ${field_contents:0:1} = "/" ]; then
          field_contents=$FILTER_DEFS_PATH'/'$field_contents
        fi
        if ! [ -f "$field_contents" ]; then
          echo "File to insert could not be found!"
          error_flag="ERROR: File to insert could not be found! Aborting system launch."
          message="ERROR: File to insert could not be found! Aborting system launch."
          commit_to_log "$message"
          return
        fi
        pre_process_file "$field_contents"
        if [[ $error_flag != "" ]]; then
          #an error was found, abort any further processing and return to the calling function 
          return 
        fi     
        continue
      fi
    fi  #end of if [[ $preprocessing_clients == 'false' ]]  

    if [[ $field_identifier == "ROUTE" ]] || [[ $field_identifier == "END" ]] || [[ $field_identifier == "CLIENT_SINK" ]]; then
      #these signal the end of a route, so perform cloning on the existing route if needed
      if [ "${#route_and_clones[@]}" -gt 1 ]; then
        # perform_route_cloning:
        for clone in "${route_and_clones[@]}"
        do
          pre_processed_sys_config+="ROUTE = $clone\n$user_route_elements"
        done
      fi
      unset route_and_clones
      user_route_elements=""
      IFS=';' read -a route_and_clones <<< "$field_contents"
      if [ "${#route_and_clones[@]}" -gt 1 ]; then
        #found a route and one or more clones
        continue
      else
        #found a single route
        pre_processed_sys_config+="$ONE_LINE\n"
        continue
      fi
    fi
  
    if [ "${#route_and_clones[@]}" -eq 0 ]; then
      #a non-route related line was found
      pre_processed_sys_config+="$ONE_LINE\n"
      if [[ $ONE_LINE == *'CLIENT'* ]]; then
        preprocessing_clients=true #all subsequent lines are related to system clients
      fi
      continue
    fi
  
    if [ "${#route_and_clones[@]}" -gt 1 ]; then
      #found a user element associated with the route and its clone(s)
      user_route_elements+="$ONE_LINE\n"
    else
      #found a user element used in a single route
      pre_processed_sys_config+="$ONE_LINE\n"
    fi
   
  done < $1

  #perform any remaining route cloning tasks
  if [ "${#route_and_clones[@]}" -gt 1 ]; then
    # perform_route_cloning:
    for clone in "${route_and_clones[@]}"
    do
      pre_processed_sys_config+="ROUTE = $clone\n$user_route_elements"
    done
  fi

  user_route_elements=""
  unset route_and_clones

} #end function pre_process_file




function do_awk_math(){ awk "BEGIN{printf $1}"; }




function perform_math_operations {
  #check if the pre_processed_sys_config contains any math operators
  #  if not, return
  if ! [[ $pre_processed_sys_config == *'*'* ]]; then
    return
  fi
  #math operators found!  
  #first, make a copy of the pre_processed_sys_config
  local temp_string
  temp_string=$pre_processed_sys_config
  local -a tokens
  local num_tokens
  local NEW_LINE
  local result

  pre_processed_sys_config="" #clear var and then rebuild it
  #check each line for math operations and peform them
  while IFS='\n' read -r ONE_LINE || [[ -n "$ONE_LINE" ]]; do
    #check if the lines contains the multiplication operator
    NEW_LINE=$ONE_LINE
    if [[ $ONE_LINE == *'*'* ]]; then 
      #operator found, so split line into tokens
      IFS=' '; read -a tokens <<< "$ONE_LINE"
      #loop over tokens. If token contains the math operator perform math operation.
      #  NOTE that there could be more than one math operator per line
      num_tokens=${#tokens[@]}
      for (( i=0; i<$num_tokens; i++ )); do
        #does the part of the token before the operator contain an equals sign
        #  and a math operator?
        if ! [[ ${tokens[$i]} == *"="* && ${tokens[$i]} == *"*"* ]]; then
          continue
        fi 
        #  If so split into part before and part part after with operator 
        field_identifier=""
        field_contents=""
        separate_field_identifier_from_field_contents "=" "${tokens[$i]}"
        #check if there are any letters in the formula. If so, abort
        if [[ "$field_contents" =~ [a-zA-Z] ]]; then
          error_flag="ERROR: attempting to perform math but enountered one or more characters "
          error_flag+="as part of the expression >$field_contents< within the line >$ONE_LINE<."
          return
        fi
        #use awk to calculate the part with the oprator. specify output precision
        result=$( do_awk_math "$field_contents" )
        #re-combine awk output with part before equals sign and equals sign
        #  and set token equal to the new string
        tokens[$i]="$field_identifier"'='"$result"
      done
      #done with loop over tokens. reconstruct the line by looping over and 
      #  concatenating tokens separated by a space character
      NEW_LINE=""
      for (( i=0; i<$num_tokens; i++ )); do
        NEW_LINE+="${tokens[$i]} "
      done
      tokens=()  #clear the tokens array
    fi
    #add NEW_LINE to the pre_processed_sys_config string
    pre_processed_sys_config+="$NEW_LINE\n"
  done < <(echo -e "$temp_string")

} #end function perform_math_operations




function process_system_configuration {
  #read line Source: http://stackoverflow.com/questions/10929453/read-a-file-line-by-line-assigning-the-value-to-a-variable
  while IFS='\n' read -r ONE_LINE || [[ -n "$ONE_LINE" ]]; do
    #check for and remove any comments on the line (comments begin with a '#')
    comment_identifier_position=$(strindex "$ONE_LINE" "#")
    if [ $comment_identifier_position != "-1" ]; then 
      #remove the comment
      ONE_LINE=${ONE_LINE:0:$comment_identifier_position}
    fi
    if [[ $ONE_LINE = "" ]]; then 
      #if ONE_LINE is now blank, just skip to the next line
      continue;
    fi
    #parse the line info field identifier and field contents
    field_identifier=""
    field_contents=""
    separate_field_identifier_from_field_contents "=" "$ONE_LINE"
    
    if [[ $IO_MODE == "preamp" ]]; then
      if [[ $field_identifier = "SYSTEM_INPUT" ]]; then
        SYSTEM_INPUT=$field_contents
        continue;
      fi
    fi
    
    if [[ $field_identifier == "CLIENT" ]]; then
      #CLIENT begins a new client description
      #first, save the ip address provided with the CLIENT keyword
      client_ip_address=$field_contents
      #complete the code for the previous client before moving on to the new client
      if [ $CLIENT_INDEX -ge 0 ]; then 
         consolidate_existing_client_code
        if [[ $error_flag != "" ]]; then return; fi #if an error was found, abort any further processing and return to the calling function
      fi
      #begin new client:
      #increment CLIENT_INDEX and initialize/reset some variables
      ((CLIENT_INDEX++))
      #initialize some parameters to their default values
      SYNCHRONIZED_PLAYBACK[CLIENT_INDEX]=${SYNCHRONIZED_PLAYBACK[0]}
      CLIENT_RTPBIN_PARAMS[CLIENT_INDEX]=${CLIENT_RTPBIN_PARAMS[0]}
      STREAM_BITS[CLIENT_INDEX]=${STREAM_BITS[0]}
      STREAM_RATE[CLIENT_INDEX]=${STREAM_RATE[0]}
      SINK_FORMAT[CLIENT_INDEX]=${SINK_FORMAT[0]}
      INFO_PATH[CLIENT_INDEX]=${INFO_PATH[0]}
      INTERLEAVE_BUFFER[CLIENT_INDEX]=${INTERLEAVE_BUFFER[0]}
      ROUTE_CODE=""
      CLIENT_CODE=""
      CLIENT_SINK_CODE=""
      SINK_INDEX=-1 #reset the sink index to -1 to indicate no existing sinks
      unset SINK_CONNECTIONS #clear the SINK_CONNECTIONS counter
      unset SOURCE_USAGE #clear any existing info regarding the previous client's SOURCE_USAGE
      #validate the ip address for this client:
      #  for a valid and reachable client, put the validated value into IP[CLIENT_INDEX]
      #  if the client is not reachable, the value -2 has been assigned to the IP address
      validate_client_IP "$client_ip_address" 
      #if the IP address was found to be invalid, abort any further processing 
      if [[ "$error_flag" != "" ]]; then 
        return  
      fi
      continue
    fi #done initializing new client

    #process a ROUTE command or termiante an existing ROUTE
    if [[ $READ_ROUTE_INFO == "true" ]]; then
      #check if the current route should be terminated
      if [[ $field_identifier == "ROUTE" ]] || [[ $field_identifier == "CLIENT" ]] || [[ $field_identifier == "CLIENT_SINK" ]]; then
        #a new ROUTE has been decleared, or a client parameter was found
        #append the remaining ROUTE_CODE into CLIENT_CODE
        CLIENT_CODE+="    $ROUTE_CODE" # <<=== NEEDS TO BE REPEATED FOR ROUTE DUPLICATIONS
        #reset ROUTE_CODE to empty string
        ROUTE_CODE=""
        READ_ROUTE_INFO="false"
      fi
    fi
    if [[ $field_identifier == "ROUTE" ]] && [[ $field_contents != "END" ]]; then
      #begin constructing a new ROUTE
      READ_ROUTE_INFO="true"
      #decompose the field contents into its parameters
      IFS=',' read ROUTE_START ROUTE_END CH_MASK <<< "$field_contents"
      #check if ROUTE_END refers to a sink or tee. 
      if [[ ${ROUTE_END:0:1} == [0-9] ]]; then
        #the route ends at a sink
        #sink connections keeps track of how many audio channels have been directed to the sink with index ROUTE_END
        #This is done so that connections can be made in sequential order
        #if the sink connections counter has not yet been used for this sink, initialize it now
        if [[ ${SINK_CONNECTIONS[ROUTE_END]} == '' ]]; then SINK_CONNECTIONS[ROUTE_END]=0; fi
        #if channel mask >= 0 convert it to hexadecimal format, otherwise cast as int
        if (( CH_MASK < 0 )); then
          CH_MASK="(int)$CH_MASK"
        else
          CH_MASK="(bitmask)0x$(printf "%x" $((2**$CH_MASK)))"
        fi
        #because the route ends at a sink, we need to convert the audio to the sink format and assign the sink channel
        ROUTE_END_CODE="audioconvert ! 'audio/x-raw,format=${SINK_FORMAT[CLIENT_INDEX]},channel-mask=$CH_MASK' ! output$SINK_INDEX"'.sink_'"${SINK_CONNECTIONS[ROUTE_END]}"
        #increment the sink connections counter for the sink specified by ROUTE_END
        (( SINK_CONNECTIONS[ROUTE_END]++ ))
      else
        #the route ends at a tee. Declare the tee as part of the route end code
        ROUTE_END_CODE='tee name='"$ROUTE_END"
      fi
      #check if route_start refers to an input channel or tee
      if [[ ${ROUTE_START:0:1} == [0-9] ]] || [[ ${ROUTE_START:0:1} == '+' ]] || [[ ${ROUTE_START:0:1} == '-' ]]; then
          #the route starts at an input channel or mixing expression. 
          process_input_mixing_expression "$ROUTE_START"
      else
          #the route starts at a user tee. The name of the tee is contained in ROUTE_START. 
          ROUTE_CODE=" $ROUTE_START"'. ! queue ! '$ROUTE_END_CODE
      fi
      #done processing the ROUTE statement, skip to read next line from file
      continue;
    fi
    #if we get here we are reading in a user-supplied route element. 
    #do a check for proper use of DELAY 
    if [[ $field_identifier == "DELAY" ]] || [[ $field_identifier == "delay" ]]; then
      if [[ $READ_ROUTE_INFO != "true" ]]; then
        #error: there must be a ROUTE declared before using the DELAY statement
        error_flag="ERROR: no ROUTE declared before using the DELAY statement."
        return
      fi  
      #convert DELAY with delay in micro-seconds to Gstreamer audioecho element
      #  with the delay time expressed in nanoseconds and all-enabling channel-mask
      ONE_LINE='audioecho surround-delay=true surround-mask=268435455 delay='$field_contents'000'
    fi    
    if [[ $READ_ROUTE_INFO == "true" ]]; then
      #Because the ROUTE_END is included
      #  when the ROUTE_CODE is first constructed, if there are subsequent user-supplied ladspa elements, etc.
      #  they must be inserted into the exisiting ROUTE_CODE just before the ROUTE_END
      #calculate the insert point as p = ROUTE_CODE length - ROUTE_END_CODE length
      p=$(( ${#ROUTE_CODE} - ${#ROUTE_END_CODE} ))
      #remove any leading and trailing whitespace from the user-supplied element:
      ONE_LINE=`expr "$ONE_LINE" : "^\ *\(.*[^ ]\)\ *$"`
      #insert the user-supplied code into the existing route code
      ROUTE_CODE="${ROUTE_CODE:0:p}$ONE_LINE ! ${ROUTE_CODE:p}"
      continue;
    fi
    #done processing ROUTE related info

    #not CLIENT or ROUTE related info, so must be either a system or client parameter
    if [[ $CLIENT_INDEX == -1 ]]; then
      IFS=''
      get_system_or_stream_parameter "$ONE_LINE"
    else
      IFS=''
      get_client_parameter "$ONE_LINE"
    fi
  done < <(echo -e "$pre_processed_sys_config")

} #end function process_system_configuration


function build_system_configuration_from_file {
  #this function builds the system_configuration arrays from file
#  local SINK_CONNECTIONS
  local field_identifier
  local field_contents
  local client_ip_address

  #unset all system_configuration arrays that are not empty
  unset GST_CLIENT_CODE
  unset IP
  unset AUDIO
  unset CLIENT_CHANNEL_USE
  unset ACCESS
  unset CLIENT_SINK
  unset CLIENT_RTPBIN_PARAMS
  unset INTERLEAVE_BUFFER
  unset OTHER_COMMAND_BEFORE_LAUNCH
  unset OTHER_COMMAND_AFTER_LAUNCH
  unset LOCAL_SCRIPT_BEFORE_LAUNCH
  unset LOCAL_SCRIPT_AFTER_LAUNCH
  unset OTHER_COMMAND_BEFORE_TERMINATE
  unset OTHER_COMMAND_AFTER_TERMINATE
  unset LOCAL_SCRIPT_BEFORE_TERMINATE
  unset LOCAL_SCRIPT_AFTER_TERMINATE
  unset STREAM_BITS
  unset STREAM_RATE
  unset SINK_FORMAT
  unset INFO_PATH
  unset GLOBAL_SOURCE_USAGE
  unset SYNCHRONIZED_PLAYBACK
  
  #initialize some parameters to hard defaults
  SYNCHRONIZED_PLAYBACK[0]="disable" #client playback sync via RTCP
  INFO_PATH[0]="$CLIENT_INFO_PATH"
  STREAM_RATE[0]=44100  #default to CD rate
  STREAM_BITS[0]=16     #default to CD bit depth
  INTERLEAVE_BUFFER[0]=100000000  #client-side audiointerleave and audiomixer latency (in nanosec)
  SERVER_BUFFER=100000000   #initialize the default server (audiointerlave) buffer to 30msec (30 000 000 nsec)
  CLIENT_RTPBIN_PARAMS[0]=""   #clear the parameter string
  MIXER_INDEX=0   #reset the index used for distinguishing mixers
  RESAMPLER_QUALITY=10   #set the quality to maximum. Valid values are 0..10
  SINK_FORMAT[0]='S16LE'   #the default client audio output format
  SERVER_RTPBIN_PARAMS=""
  if [[ $IO_MODE == "preamp" ]]; then
    SYSTEM_INPUT=""
    unset VOL_CTL_TYPE 
    unset VOL_CTL_ID
    unset VOL_CTL_NAME
    unset VOL_CTL_MAX_LEVEL
    unset MUTE_CTL_TYPE
    unset MUTE_CTL_ID
    unset MUTE_CTL_NAME
    unset UNMUTE_CTL_TYPE
    unset UNMUTE_CTL_ID
    unset UNMUTE_CTL_NAME
    VOLUME_CONTROL_STYLE="graphical"
    VOLUME_CONTROL_COLS="50"
    VOLUME_CONTROL_TIMEOUT=0
  else
    SYSTEM_INPUT=$AUDIO_SOURCE
  fi
  LOCAL_CLIENT_INDEX=""
  GAIN_ADJUST=""
  mixmatrix_string=''

  #reset the client counter to zero:
  CLIENT_INDEX=-1 #need to initialize to -1 because BASH arrays are zero-offset
  
  #clear the following arrays that are populated during file pre-processing
  pre_processed_sys_config=""
  unset multiline_variables 
  unset multiline_defaults 
  unset singleline_variables 
  #redeclare the arrays empty, with global scope
  declare -gA multiline_variables #declare here to be global in scope
  declare -gA multiline_defaults #declare here to be global in scope
  declare -gA singleline_variables #declare here to be global in scope

  #read in and pre-process the system configuration file. Abort on error
  pre_process_file "system_configuration"
  if [[ $error_flag != "" ]]; then
    #an error was found, abort any further processing and return to the calling function 
    return 
  fi     

  #only after all file pre-processing has been completed is the replacement of all 
  #  single-line variables, if any, performed
  for var_name in "${!singleline_variables[@]}"; do
    field_contents=${singleline_variables[$var_name]};       
    pre_processed_sys_config=${pre_processed_sys_config/$var_name/$field_contents} #replace var name with value
  done

  #perform any math operations present in the system_configuration
  #  at this time only multiplication is supported, and when in the form:
  #  parameter=value1*value2
  perform_math_operations
  if [[ $error_flag != "" ]]; then
    #an error was found, abort any further processing and return to the calling function 
    return 
  fi     

  #process the system configuration file. 
  process_system_configuration
  if [[ $error_flag != "" ]]; then
    #an error was found, abort any further processing and return to the calling function 
    return 
  fi     

  #complete the code for the last client in the system
  consolidate_existing_client_code

  #clear the contents of the pre_processed_sys_config variable
  pre_processed_sys_config=""
  
  #if operating in PREAMP mode, check that a system input was provided
  if [[ $IO_MODE == "preamp" ]] && [[ "SYSTEM_INPUT" == "" ]]; then
    message="ERROR: a SYSTEM_INPUT was not specified for system $system_name. This is required when in preamp mode. Aborting launch."
    error_flag=1
    return
  fi
}



function get_RTPC_port_numbers {
  local col1
  local col2
  local col3
  local col4
  local col5
  local col6
  local col7
  local ports_in_use

  #determine which dynamic ports are currently in use on the server
  oldIFS=$IFS
  IFS=$'
  '
  ss_output=($(ss -nltup sport gt :32767))
  IFS=$oldIFS
  LINE_NUM=1
  while [ $LINE_NUM -lt ${#ss_output[@]} ]
  do
     IFS=" " read col1 col2 col3 col4 col5 col6 col7 <<< ${ss_output[$LINE_NUM]}
     ports_in_use+=$(echo ${col5//*:})' '
     (( LINE_NUM++ ))
  done 
  
  #populate the RTPC_RX_PORT_NUM array
  #store the numbers of N available ports, one for each of N clients in the system
  unset RTPC_RX_PORT_NUM
  #start at port 32768, the beginning of the dynamic port range under Linux
  trial_port_num=32768
  CLIENT_INDEX=0
  for ((CLIENT_INDEX=0; CLIENT_INDEX < ${#IP[@]}; CLIENT_INDEX++))
  do
    #get next highest available/unused port number
    while [[ "$ports_in_use" == *"$trial_port_num"* ]]
    do
      (( trial_port_num++ ))
    done
    #copy the port into the RTPC_RX_PORT_NUM array
    RTPC_RX_PORT_NUM[CLIENT_INDEX]=$trial_port_num
    (( trial_port_num++ ))
  done
}



function build_gstreamer_pipeline {
  #build the gstreamer pipeline for the server and local client (if any)

  #synchronize all files in the system directory between fixed disk and RAM_FS (if used)
  sync_files_between_FD_and_RAM_FS system_configuration


  #import the contents of the config file
  build_system_configuration_from_file
  #test to see if an error was found
  if [[ $error_flag != "" ]]; then
    #an error ocurred - abort any further processing and return to the calling function 
    return; 
  fi  
 
  local CLIENT_CONNECTIONS #keeps track of how many channels have been connected to an audiointerleave
  local LOCAL_CLIENT_CODE #variable to hold code so that sub-string replacements can be performed on it
  local BITS
  local VOLUME_LEVEL

  #calculate the number of streaming clients for this system
  NUM_STREAMING_CLIENTS=0
  for ((CLIENT_INDEX=0; CLIENT_INDEX < ${#IP[@]}; CLIENT_INDEX++))
  do
    if [[ ${IP[CLIENT_INDEX]} == "-1" ]]; then
      continue
    else
      (( NUM_STREAMING_CLIENTS++ ))
    fi
  done   
  
  #begin to form the gstreamer command arguments to create the server-side pipeline
  unset GST_SERVER_CODE #clear out any previous pipeline elements

  #if this system contains streaming clients...
  if [ $NUM_STREAMING_CLIENTS -gt 0 ]; then
    #compile a list of ports that are available for RTPC data returning from clients
    get_RTPC_port_numbers
    #declare the use of rtpbin
    GST_SERVER_CODE+=(' rtpbin name=server_rtpbin '$SERVER_RTPBIN_PARAMS' ') 
    #rtcp-sync-send-time=false 
  fi  

  #add the AUDIO_SOURCE
  GST_SERVER_CODE+=( $SYSTEM_INPUT' !'  )
  #employ queue on main audio input
  GST_SERVER_CODE+=('queue !') 

  #determine gain adjustment for this system
  VOLUME_LEVEL=$(dB_to_volume $GAIN_ADJUST)
  #if this returned -1 (error) or 1.0 (0dB) do not implement the volume element
  if [[ $VOLUME_LEVEL != "-1" ]] && [[ $VOLUME_LEVEL != $(dB_to_volume "0") ]]; then
    GST_SERVER_CODE+=('volume volume='$VOLUME_LEVEL' !')
  fi

  #change format to F32LE, since this is required by LADSPA plugins
  GST_SERVER_CODE+=("audioconvert ! audio/x-raw,format=F32LE !")

  #add server-side channel mixing, if present
  if [[ $mixmatrix_string != "" ]]; then
    GST_SERVER_CODE+=("$mixmatrix_string")
  fi

  #deinterleave audio input to permit access to individual channels
  GST_SERVER_CODE+=("deinterleave name=input")
  
  #substring replacement does not work on string arrays, so we need to make a copy
  #  if there is a local client, copy its code from the GST_CLIENT_CODE string 
  #  array into the string variable LOCAL_CLIENT_CODE
  if [[ $LOCAL_CLIENT_INDEX != "" ]]; then
    LOCAL_CLIENT_CODE=${GST_CLIENT_CODE[LOCAL_CLIENT_INDEX]}
  fi

  #Based on how many times each channel is used across all clients create tees
  #  Replace LOCAL_CLIENT_CODE channel source placeholders with appropriate server sources
  for i in ${!GLOBAL_SOURCE_USAGE[@]}; do
    if [ ${GLOBAL_SOURCE_USAGE[i]} -gt 1 ]; then 
      GST_SERVER_CODE+=("  input.src_$i"' ! tee name=input_ch'"$i")
      LOCAL_CLIENT_CODE=${LOCAL_CLIENT_CODE//"SOURCE_FOR_CH$i"/"input_ch$i"'. ! queue'} 
    else
      LOCAL_CLIENT_CODE=${LOCAL_CLIENT_CODE//"SOURCE_FOR_CH$i"/"input.src_$i"}
    fi
  done

  #if there is a local-playback client, add its client code to the server-side code
  if [[ $LOCAL_CLIENT_INDEX != "" ]]; then
    GST_SERVER_CODE+=( $LOCAL_CLIENT_CODE )
  fi

  #add the gstreamer commands to the server-side pipeline that stream audio to each remote client 
  for ((CLIENT_INDEX=0; CLIENT_INDEX < ${#IP[@]}; CLIENT_INDEX++))
  do
    #skip the code in this loop if this is the local client or an invalid IP address
    if [[ ${IP[CLIENT_INDEX]} == "-1" ]] || [[ ${IP[CLIENT_INDEX]} == "-2" ]]; then
      continue
    fi
    CLIENT_CONNECTIONS[CLIENT_INDEX]=0
    #create interleave and stream elements for streaming clients, then route audio to rtpbin
    #audiointerleave must be used with sufficient latency to prevent audio gliches
    GST_SERVER_CODE+=('   audiointerleave name=client'"$CLIENT_INDEX"'_stream latency='"$SERVER_BUFFER"' !')
    #RTP streams can accommodate 24bit or 16bit data only. Constrain BITS to these values 
    BITS=${STREAM_BITS[CLIENT_INDEX]}
    if [ $BITS -ne 24 ]; then
      BITS=16
    fi
    GST_SERVER_CODE+=("audioconvert ! audioresample quality=$RESAMPLER_QUALITY !")
    GST_SERVER_CODE+=('audio/x-raw,rate='${STREAM_RATE[CLIENT_INDEX]}',format=S'$BITS'LE !')
    GST_SERVER_CODE+=('audioconvert ! rtpL'$BITS'pay !')
    GST_SERVER_CODE+=("server_rtpbin.send_rtp_sink_$CLIENT_INDEX")

    #set up RTP audio data TX for this client
    GST_SERVER_CODE+=("server_rtpbin.send_rtp_src_$CLIENT_INDEX ! udpsink host=${IP[CLIENT_INDEX]} port=32768 ")
    
    if [[ "${SYNCHRONIZED_PLAYBACK[CLIENT_INDEX]}" == "enable" ]]; then
      #set up RTPC control data RX and TX for this client
      GST_SERVER_CODE+=("server_rtpbin.send_rtcp_src_$CLIENT_INDEX ! udpsink host=${IP[CLIENT_INDEX]} port=32769 sync=false async=false ")
      GST_SERVER_CODE+=("udpsrc port=${RTPC_RX_PORT_NUM[CLIENT_INDEX]} ! server_rtpbin.recv_rtcp_sink_$CLIENT_INDEX ")
    fi
    
    unset CHANNEL_USE
    IFS=' ' read -ra CHANNEL_USE <<<"${CLIENT_CHANNEL_USE[CLIENT_INDEX]}"
    for i in ${!CHANNEL_USE[@]}; do
      channel=${CHANNEL_USE[i]}
      if [ ${GLOBAL_SOURCE_USAGE[channel]} -gt 1 ]; then
        #the source for this channel is a tee (tee was created above)
        GST_SERVER_CODE+=("  input_ch$channel"'. ! queue ! client'"$CLIENT_INDEX"'_stream.sink_'"${CLIENT_CONNECTIONS[CLIENT_INDEX]}")
      else
        #the source for this channel is deinterleaved input. 
        GST_SERVER_CODE+=("  input.src_$channel ! queue ! client$CLIENT_INDEX"'_stream.sink_'"${CLIENT_CONNECTIONS[CLIENT_INDEX]}")
      fi
      (( CLIENT_CONNECTIONS[CLIENT_INDEX]++ ))
    done
  done
  #done creating server-side pipelines
  
  #check for Gstreamer pipeline errors in the form of empty elements
  #   and remove any that are found
  local max_spaces=8
  local idx
  local j
  local element
  local error_flag
  for idx in "${!GST_SERVER_CODE[@]}"; do
    error_flag=0
    element="${GST_SERVER_CODE[$idx]}"
    spaces="" #empty the string
    #add max_spaces spaces to the string:
    for ((j = 0 ; j < "$max_spaces" ; j++)); do
      spaces="$spaces "  
    done
    #now search for pattern with !, j spaces, and !, e.g. an "empty" element
    for ((j = "$max_spaces" ; j >= 0 ; j--)); do
      pattern="!$spaces!"
      if [[ $element =~ $pattern ]]; then
        ((error_flag++))
        message+="WARNING: removing an empty element from >> $element <<.   "
        commit_to_log "$message"
        element="${element//${pattern}/!}"
      fi
      if [[ $j -gt 0 ]]; then spaces="${spaces::-1}"; fi #remove one space
    done
    if [[ "$error_flag" -gt 0 ]]; then
       GST_SERVER_CODE[$idx]="$element"
    fi
  done  #done checking/removing pipeline errors 
 
} #end function 'build_gstreamer_pipeline'



function launch_server_pipeline {
  #print out GST_SERVER_CODE for debugging purposes
   if [[ "$DEBUG_MODE" != "" ]]; then
     echo; echo
     echo "# GST_SERVER_CODE in launch_server_pipeline"
     echo '# '${GST_SERVER_CODE[*]}
     echo; echo
   fi
 
  #launch gstreamer pipeline as nohup background and direct output to /dev/null
  if [[ "$DEBUG_MODE" == "" ]]; then
    eval nohup gst-launch-1.0 ${GST_SERVER_CODE[@]} 1> /dev/null 2> /dev/null &
  fi
  #launch gstreamer pipeline as nohup background and direct debug output to file
  if [[ "$DEBUG_MODE" == "run" ]]; then
    echo 'launching server-side gstreamer pipeline with debug output enabled...'           
    eval nohup gst-launch-1.0 -vm ${GST_SERVER_CODE[@]} > gst_server_output.txt 2>&1 &
  fi
  if [[ "$DEBUG_MODE" == "no-run" ]]; then
    echo 'generating server-side gstreamer pipeline. Pipeline execution disabled...'
    echo
    return           
  fi  
  
  #give the process some time to start
  sleep 0.2

  #check that the pipeline just lauched is still running by checking the elapsed run time  
  local elapsed_time
  local startup_error="false"
  elapsed_time=$(ps h -o etimes -C gst-launch-1.0 --sort=start_time | tail -1) #time in sec
  #remove leading and trailing whitespaces:
  elapsed_time=`expr "$elapsed_time" : "^\ *\(.*[^ ]\)\ *$"`
  if [[ $elapsed_time == "" ]]; then
    startup_error="true"
  elif [ $elapsed_time -gt 10 ]; then 
    startup_error="true"
  fi
  if [[ "$startup_error" == "true" ]]; then
    #an error ocurred - set the error flag and then return to the calling function 
    error_flag="The server pipeline encountered an error did not start properly"
    cp gst_server_output.txt "$DEBUG_INFO_PATH"
    return 
  fi
  #get the pid for the most recently launched gst-launch-1.0
  gst_pid=$( ps h -o pid -C gst-launch-1.0 --sort=start_time | tail -1 ) 
  #remove any leading and trailing whitespace
  gst_pid=`expr "$gst_pid" : "^\ *\(.*[^ ]\)\ *$"`
  #put the process PID into the local PID file (overwriting any previous contents)   
  echo $gst_pid > PID

} #end function launch_server_pipeline



function launch_system_clients {
  #connect to each client using SSH. Build and execute the pipeline that receives the audio stream
  declare -a local GST_ARGS #declare array variable for arguments  
  local saved_path #temp storage of path
  for ((CLIENT_INDEX=0; CLIENT_INDEX < ${#IP[@]}; CLIENT_INDEX++))
  do
    if [[ ${IP[CLIENT_INDEX]} == "-1" ]] || [[ ${IP[CLIENT_INDEX]} == "-2" ]]; then
      #this is a local-playback client or the clients' IP address is invalid. Skip it.
      continue
    fi
    echo 'launching gstreamer pipeline on client #'"$(( $CLIENT_INDEX + 1 ))"'...'           
    #begin launch of streaming client
    if [ -n "$GST_ARGS" ]; then unset GST_ARGS; fi #clear the GST_ARGS array
    
    #form the gstreamer command arguments for this client before connecting to client
    #declare use of rtpbin
    GST_ARGS+=("rtpbin name=client_rtpbin ${CLIENT_RTPBIN_PARAMS[CLIENT_INDEX]} ")

    #set up audio data RX, declare its properties, and route to rtpbin 
    GST_ARGS+=("udpsrc port=32768 caps='application/x-rtp, media=(string)audio,")
    #add the clock rate and encoding to the caps string  
    GST_ARGS+=("clock-rate=(int)"${STREAM_RATE[CLIENT_INDEX]}", encoding-name=(string)L"${STREAM_BITS[CLIENT_INDEX]}",")
    #add the number of channels to the caps string 
    IFS=' ' read -ra CHANNEL_USE <<<"${CLIENT_CHANNEL_USE[CLIENT_INDEX]}" #copy the list of channels into CHANNEL_USE
    GST_ARGS+=("channels=(int)${#CHANNEL_USE[@]}"',')
    GST_ARGS+=("payload=(int)96' ! client_rtpbin.recv_rtp_sink_0 ")

    #get audio data from rtpbin for this client:
    GST_ARGS+=("client_rtpbin. ! ")
    GST_ARGS+=("rtpL"${STREAM_BITS[CLIENT_INDEX]}"depay ! ")
    GST_ARGS+=('audioconvert ! audio/x-raw,format=F32LE ! ')
    GST_ARGS+=('deinterleave name=input ')

    if [[ "${SYNCHRONIZED_PLAYBACK[CLIENT_INDEX]}" == "enable" ]]; then
      #set up RTPC control data RX and TX for this client
      GST_ARGS+=('udpsrc port=32769 ! client_rtpbin.recv_rtcp_sink_0 ')
      GST_ARGS+=("client_rtpbin.send_rtcp_src_0 ! udpsink host=$server_IP_address port=${RTPC_RX_PORT_NUM[CLIENT_INDEX]} sync=false async=false ")
    fi
    
    #append the GST CODE that was created while reading in the client configuration file
    GST_ARGS+=( "${GST_CLIENT_CODE[CLIENT_INDEX]}" )

    #print out GST_ARGS for debugging purposes
     if [[ "$DEBUG_MODE" != "" ]]; then
       echo; echo
       echo "# GST_ARGS in function launch_system_clients, for CLIENT $CLIENT_INDEX at ${IP[CLIENT_INDEX]}"
       echo '# '${GST_ARGS[*]}
       echo; echo; echo
     fi

    if [[ "${LOCAL_SCRIPT_BEFORE_LAUNCH[CLIENT_INDEX]}" != "" ]] && [[ "$DEBUG_MODE" != "no-run" ]]; then
      #execute on the client a script that resides on the server filesystem 
      #as specified in the LOCAL_SCRIPT_BEFORE_LAUNCH text
      eval ${ACCESS[CLIENT_INDEX]} 'bash -s' -- < ${LOCAL_SCRIPT_BEFORE_LAUNCH[CLIENT_INDEX]}
      #if client access failed, generate error message and move on to next client
      if (( $? > 0 )); then
        message="An error was encountered while trying to run the local script on client "${IP[CLIENT_INDEX]}" before launch"
        commit_to_log "$message" 
      fi
    fi

    #attempt to connect to client using the user-supplied access string and run various commands
    eval ${ACCESS[CLIENT_INDEX]} /bin/bash << CLIENT_LAUNCH_HERE_DOC
    #begin HERE-DOCUMENT commands that are run on the client
    saved_path=\$(pwd)
    
    if [[ "${OTHER_COMMAND_BEFORE_LAUNCH[CLIENT_INDEX]}" != "" ]] && [[ "$DEBUG_MODE" != "no-run" ]]; then
      #execute on the client commands/scripts located on the client 
      #as specified in the OTHER_COMMAND_BEFORE_LAUNCH text
      eval ${OTHER_COMMAND_BEFORE_LAUNCH[CLIENT_INDEX]}
    fi
    
    #return to login dir
    cd $saved_path
    #create user supplied path if it does not exist
    mkdir -p ${INFO_PATH[CLIENT_INDEX]}
    #cd using user supplied path
    cd ${INFO_PATH[CLIENT_INDEX]}
    
    #run gstreamer pipeline on client as nohup background and direct output to file
    if [[ "$DEBUG_MODE" == "" ]]; then
      eval nohup gst-launch-1.0 "${GST_ARGS[@]}" 1> /dev/null 2> /dev/null &
    fi
    if [[ "$DEBUG_MODE" == "run" ]]; then
      eval nohup gst-launch-1.0 -vm "${GST_ARGS[@]}" 1> gst_client_output.txt 2> gst_client_output.err &
    fi  
  
    #give the process some time to start
    sleep 0.2
    #get the pid for the most recently launched gst-launch-1.0
    gst_pid=\$( ps h -o pid -C gst-launch-1.0 --sort=start_time | tail -1 ) 
    #put the process PID into the cPID file (overwriting any previous contents)   
    echo "\$gst_pid" > cPID
  
    if [[ "${OTHER_COMMAND_AFTER_LAUNCH[CLIENT_INDEX]}" != "" ]] && [[ "$DEBUG_MODE" != "no-run" ]]; then
      #execute on the client commands/scripts located on the client 
      #as specified in the OTHER_COMMAND_AFTER_LAUNCH text
      eval ${OTHER_COMMAND_AFTER_LAUNCH[CLIENT_INDEX]}
    fi

    #client startup complete. logout of client
    exit
CLIENT_LAUNCH_HERE_DOC
#end of HERE-DOCUMENT client commands.


    #if client access failed, generate error message and move on to next client
    if (( $? > 0 )); then
      message="An error was encountered while trying to launch client "${IP[CLIENT_INDEX]}
      commit_to_log "$message" 
      continue;
    else
      message="Client ${IP[CLIENT_INDEX]} was launched sucessfully"
      commit_to_log "$message" 
    fi

    if [[ "${LOCAL_SCRIPT_AFTER_LAUNCH[CLIENT_INDEX]}" != "" ]] && [[ "$DEBUG_MODE" != "no-run" ]]; then
      #execute on the client a script that resides on the server filesystem 
      #as specified in the LOCAL_SCRIPT_AFTER_LAUNCH text
      eval ${ACCESS[CLIENT_INDEX]} 'bash -s' -- < ${LOCAL_SCRIPT_AFTER_LAUNCH[CLIENT_INDEX]}
      #if client access failed, generate error message and move on to next client
      if (( $? > 0 )); then
        message="An error was encountered while trying to run the local script on client "${IP[CLIENT_INDEX]}" after launch"
        commit_to_log "$message" 
      fi
    fi
  done #done with loop over system clients
} #end function launch_system_clients



function terminate_system_clients {
  #connect to each client, terminate gstreamer processes, and run termination scripts
  for ((CLIENT_INDEX=0; CLIENT_INDEX < ${#IP[@]}; CLIENT_INDEX++))
  do
    if [[ "${IP[CLIENT_INDEX]}" == "-2"  ]]; then
      #client's IP address is invalid. Skip to next client
      continue
    fi
    #take action depending whether client is local or remote
    if [[ "${IP[CLIENT_INDEX]}" == "-1"  ]]; then
      #client is a LOCAL_PLAYBACK client 
      #it has already been terminated along with the server-side process
      #no further action is needed, so skip to next client
      message="   The local client has been terminated"
      commit_to_log "$message"
      continue 
    fi
    echo 'terminating system client #'"$(( $CLIENT_INDEX + 1 ))"'...'           
    #client is remote: before proceeding, confirm client is reachable using ping
    ping -c 1 ${IP[CLIENT_INDEX]} >/dev/null
    if [ $? -ne 0 ]; then
      message="ERROR: the client at IP="${IP[CLIENT_INDEX]}" was not reachable."
      commit_to_log "$message"
      continue;
    fi
    #begin non-local client termination procedure
    if [[ "${LOCAL_SCRIPT_BEFORE_TERMINATE[CLIENT_INDEX]}" != "" ]]; then
      #execute on the client a script that resides on the server filesystem 
      #as specified in the LOCAL_SCRIPT_BEFORE_TERMINATE text
      eval ${ACCESS[CLIENT_INDEX]} 'bash -s' -- < ${LOCAL_SCRIPT_BEFORE_TERMINATE[CLIENT_INDEX]}
      #if client access failed, generate error message and move on to next client
      if (( $? > 0 )); then
        message="An error was encountered while trying to run the local script on client "${IP[CLIENT_INDEX]}" before terminate"
        commit_to_log "$message"
      fi
    fi
    
    #attempt to connect to client using the user-supplied access string and run some commands
    eval ${ACCESS[CLIENT_INDEX]} /bin/bash << CLIENT_TERMINATE_HERE_DOC
    #begin HERE-DOCUMENT commands that are run on the client
    saved_path=\$(pwd)
    
    if [[ "${OTHER_COMMAND_BEFORE_TERMINATE[CLIENT_INDEX]}" != "" ]]; then
      #execute on the client commands/scripts located on the client 
      #as specified in the OTHER_COMMAND_BEFORE_TERMINATE text
      eval ${OTHER_COMMAND_BEFORE_TERMINATE[CLIENT_INDEX]}
    fi
    
    #return to login dir
    cd \$saved_path
    #cd to user supplied path
    cd ${INFO_PATH[CLIENT_INDEX]}

    if [[ $user_action == "k" ]]; then
      #if killall mode, just kill all running gst-launch-1.0 processes and remove the cPID file
      #get pid of most recently launched gstreamer process 
      gst_pid=\$( ps h -o pid -C gst-launch-1.0 --sort=start_time | tail -1 )
      #only use killall if there are running gstreamer processes
      if [[ \$gst_pid != "" ]]; then
        killall gst-launch-1.0
      fi
      #does the PID file exist?
      if [ -f "cPID" ]; then
       rm cPID
      fi
    else
      #does the PID file exist?
      if [ -f "cPID" ]; then
        #read each line of the PID file and kill extracted PIDs
        while IFS='' read -r ONE_LINE || [[ -n \$ONE_LINE ]]; do
          #if ONE_LINE is empty string, continue
          if [[ ONE_LINE == "" ]]; then continue; fi
          #send SIGINT signal to the PID and silence any output
          kill \$ONE_LINE > /dev/null
        done < cPID
        #done killing processes. remove the PID file
        rm cPID
      fi
    fi

    if [[ "${OTHER_COMMAND_AFTER_TERMINATE[CLIENT_INDEX]}" != "" ]]; then
      #execute on the client commands/scripts located on the client 
      #as specified in the OTHER_COMMAND_AFTER_TERMINATE text
      eval ${OTHER_COMMAND_AFTER_TERMINATE[CLIENT_INDEX]}
    fi
    
    #done with this client. Logout of client
    exit
CLIENT_TERMINATE_HERE_DOC
#end of HERE-DOCUMENT client commands. 

    #if client access failed, generate error message and move on to next client
    ret_val=$?
    if (( $ret_val > 0 )); then
      message='   While trying to terminate client '${IP[CLIENT_INDEX]}': an error was encountered.'
      commit_to_log "$message" 
      continue;
    else
      message="   Client ${IP[CLIENT_INDEX]} was terminated successfully"
      commit_to_log "$message" 
  fi

    if [[ "${LOCAL_SCRIPT_AFTER_TERMINATE[CLIENT_INDEX]}" != "" ]]; then
      #execute on the client a script that resides on the server filesystem 
      #as specified in the LOCAL_SCRIPT_AFTER_TERMINATE text
      eval ${ACCESS[CLIENT_INDEX]} 'bash -s' -- < ${LOCAL_SCRIPT_AFTER_TERMINATE[CLIENT_INDEX]}
      #if client access failed, generate error message and move on to next client
      if (( $? > 0 )); then
        message="An error was encountered while trying to run the local script on client "${IP[CLIENT_INDEX]}" after terminate"
        commit_to_log "$message" 
      fi
    fi

  done #end of loop over clients

} #end function terminate_system_clients



function pad2width {
  #pad ends of string $1 with spaces until length=$2, centering text
  STRING=$1
  WIDTH=$2
  side=1
  IFS='%' #need to set this to be something other than white space here.
  local length
  length=${#STRING}
  while (( length < WIDTH )); do
    if (( $side == -1 )); then
      STRING=" "$STRING
    else
      STRING+=" "
    fi
    side=$(( $side * -1 ))
    length=${#STRING}
  done
  echo $STRING
} #end function 'pad2width'



function reformat_for_output {
  #reformats the time/date info that is obtained about a particular pid using ps
  #   d-hh:mm:ss is reformatted to day(s),hour(s),min(s),sec(s) and only 
  #   displays the two most significant time bins, e.g. 1-13:22:47 will become
  #   1day,13hours and the remaining part of the time info is dropped. The 
  #   reformatted time stringis passed to WIDTH characters with spaces,  
  #   centered, and then echoed at the end of the function code
  date=$1
  saveIFS="$IFS"
  IFS="- :"
  date=($date)
  IFS="$saveIFS"
  ssmmhhdd=""
  for field in "${date[@]}"
  do
    ssmmhhdd=$field" "$ssmmhhdd
  done
  saveIFS="$IFS"
  IFS=" "
  date=($ssmmhhdd)
  IFS="$saveIFS"
  out_string=""
  label=(sec min hour day)
  labels=(secs mins hours days)
  field_pos=0
  # get length of an array
  arr_len=${#date[@]}
  ((arr_len-=1)) #subtract 1 to make into zero offset analog
  for field in "${date[@]}"
  do
    if [ $field_pos -lt $((arr_len - 1)) ]; then 
      field_pos=$((field_pos+1))
      continue 
    fi
    field=$((10#$field)) #remove leading zeros
    if [ $field -gt 1 ]; then
      out_string=$field${labels[$field_pos]}$out_string
    elif [ $field -gt 0 ]; then
      out_string=$field${label[$field_pos]}$out_string
    fi
    if [ "$field_pos" != "$arr_len" ]; then
      out_string=","$out_string
    fi
    field_pos=$((field_pos+1))
  done
  out_string=${out_string#,} #if the first character is a "," remove it
  out_string=${out_string%,} #if the last character is a "," remove it
  echo $out_string
} #end function 'reformat_for_output'


function get_system_status {
#get_system_status RETURN CODES:
# 0: no PID file found
# 1: PID file and corresponding process found
# 2: PID file found but corresponding process not found
  if [ -f "PID" ]; then
    #a PID file was found.
    gst_pid=$(cat PID)
    ps -p $gst_pid > /dev/null 
    if [ $? == 0 ]; then
      return 1 #the process exists so the system is ON
    fi
    #process not found so remove PID file.
    rm PID
    return 2
  fi
  #no PID file found
  return 0
}


function do_system_terminate {
  message="A request to TERMINATE $system_name was received."
  commit_to_log $message
  echo $message 
  gst_pid=''
  #check if system is ON (server-side)
  if [ -f "PID" ]; then
    gst_pid=$(cat PID)
    ps -p $gst_pid > /dev/null 
    if [ $? != 0 ]; then   
      #the PID file exists but the pid does not correspond to any process so the system is not ON
      message="   PID file found for $system_name but the pid does not correspond to any running server side process"
      commit_to_log $message 
      rm PID
      if [[ "$1" == "exit" ]]; then exit 1; fi
    fi
  else
    #no PID file found so system cannot be ON
    if [[ "$1" == "return" ]]; then return 1; fi
    message="   No PID file was found for $system_name on the server side"
    commit_to_log $message 
    if [[ "$1" == "exit" ]]; then exit 1; fi
  fi
  #if system is ON
  #first we need to re-build the system configuration to know how to proceed
  build_system_configuration_from_file
  #check to see if there is a local client. If one exists, then
  #   run the LOCAL_SCRIPT_BEFORE_TERMINATE 
  if [[ $LOCAL_CLIENT_INDEX != "" ]] && [[ "${LOCAL_SCRIPT_BEFORE_TERMINATE[LOCAL_CLIENT_INDEX]}" != "" ]]; then
    #execute a script as specified in the LOCAL_SCRIPT_BEFORE_TERMINATE text
    eval ${LOCAL_SCRIPT_BEFORE_TERMINATE[LOCAL_CLIENT_INDEX]}
    #if an error was produced, log an error message
    if (( $? > 0 )); then
      message="   An error was encountered while trying to run the LOCAL_SCRIPT_BEFORE_TERMINATE for the local client"
      commit_to_log "$message"
    fi
  fi
  #kill the running process to turn it OFF
  if [[ "$gst_pid" != '' ]]; then
    kill $gst_pid
    rm PID
    message="The gstreamer pipeline on the server was terminated."
    commit_to_log $message 
  fi
  #check to see if there is a local client. If one exists, then
  #   run the LOCAL_SCRIPT_AFTER_TERMINATE 
  if [[ $LOCAL_CLIENT_INDEX != "" ]] && [[ "${LOCAL_SCRIPT_AFTER_TERMINATE[LOCAL_CLIENT_INDEX]}" != "" ]]; then
    #execute a script as specified in the LOCAL_SCRIPT_BEFORE_TERMINATE text
    eval ${LOCAL_SCRIPT_AFTER_TERMINATE[LOCAL_CLIENT_INDEX]}
    #if an error was produced, log an error message
    if (( $? > 0 )); then
      message="   An error was encountered while trying to run the LOCAL_SCRIPT_AFTER_TERMINATE for the local client"
      commit_to_log "$message"
    fi
  fi
  
  #in all cases, attempt to terminate all reachable streaming clients
  #get number of reachable, streaming clients by inspection of IP address fields
  local num_streaming_clients
  local the_value
  num_streaming_clients=0
  for the_value in ${IP[*]}; do
    if [[ $the_value != "-1" ]] && [[ $the_value != "-2" ]]; then
      (( num_streaming_clients++ ))
    fi
  done
  if [ $num_streaming_clients -gt 0 ]; then
    message="Attempting to TERMINATE the clients of system $system_name :"
    commit_to_log $message
    terminate_system_clients
  elif [[ $LOCAL_CLIENT_INDEX == "" ]]; then
      message="$system_name has no reachable or streaming clients to TERMINATE."
      commit_to_log $message
  fi
}




function do_system_launch {
  #check if system is ON
  if [ -f "PID" ]; then
    gst_pid=$(cat PID)
    ps -p $gst_pid > /dev/null 
    if [ $? == 0 ]; then   #the PID exists so the system is ON
      message="No action taken because the system $system_name is already ON and running."
      commit_to_log $message
      if [[ "$1" == "exit" ]]; then
        exit 1; 
      else
        return;
      fi
    else
      #pid not found so remove PID file.
      rm PID
    fi
  fi
  #no PID file found, so system is not ON. Launch processes to turn it ON
  message="A request to LAUNCH $system_name was received."
  commit_to_log $message
  echo $message #dispaly message on screen
  build_gstreamer_pipeline
  if [[ "$error_flag" != "" ]]; then
    return 
  else
    #check to see if there is a local client. If one exists, then
    #   run the LOCAL_SCRIPT_BEFORE_LAUNCH 
    if [[ $LOCAL_CLIENT_INDEX != "" ]] && [[ "${LOCAL_SCRIPT_BEFORE_LAUNCH[LOCAL_CLIENT_INDEX]}" != "" ]] && [[ "$DEBUG_MODE" != "no-run" ]]; then
      #execute a script as specified in the LOCAL_SCRIPT_BEFORE_LAUNCH text
      eval ${LOCAL_SCRIPT_BEFORE_LAUNCH[LOCAL_CLIENT_INDEX]}
      #if an error was produced, log an error message
      if (( $? > 0 )); then
        message="   An error was encountered while trying to run the LOCAL_SCRIPT_BEFORE_LAUNCH for the local client"
        commit_to_log "$message"
      fi
    fi
    message=""
    launch_server_pipeline
    if [[ "$error_flag" != "" ]]; then
      return
    fi
    if [[ "$DEBUG_MODE" != "no-run" ]]; then
      message="The gstreamer pipeline was successfully launched on the server."
      commit_to_log $message
    fi 

    #check to see if there is a local client. If one exists, then
    #   run the LOCAL_SCRIPT_AFTER_LAUNCH 
    if [[ $LOCAL_CLIENT_INDEX != "" ]] && [[ "${LOCAL_SCRIPT_AFTER_LAUNCH[LOCAL_CLIENT_INDEX]}" != "" ]] && [[ "$DEBUG_MODE" != "no-run" ]]; then
      #execute a script as specified in the LOCAL_SCRIPT_AFTER_LAUNCH text
      eval ${LOCAL_SCRIPT_AFTER_LAUNCH[LOCAL_CLIENT_INDEX]}
      #if an error was produced, log an error message
      if (( $? > 0 )); then
        message="   An error was encountered while trying to run the LOCAL_SCRIPT_AFTER_LAUNCH for the local client"
        commit_to_log "$message"
      fi
    fi
    message=""
    launch_system_clients
  fi 
}


function show_volume {
  local control_name
  declare -a volume_info
  local index
  local vol_level_index
  local vol_percent_index
  local dB_index
  local vstring
  local mstring
  local control_info
  local action

#get the current volume control info. If multiple controls just display first one.
  #get info about the first volume control 
  vstring=( $(amixer ${VOL_CTL_TYPE[0]} ${VOL_CTL_ID[0]} sget ${VOL_CTL_NAME[0]} | grep -e '\[' -m 1 | cut -f2- -d: ) )
  IFS=' ' read -r -a volume_info <<< "$vstring"
  #find the index corresponding to various volume control information
  vol_level_index=-1
  vol_percent_index=-1
  dB_index=-1
  for (( index=0; index<${#volume_info[@]}; index++ )); do
    if [[ ${volume_info[index]} =~ .*%.* ]]; then
      vol_percent_index=$index #index to element containing percent character
      vol_level_index=$(( $index - 1 )) #the preceding element contains the level
    fi
    if [[ ${volume_info[index]} =~ .*dB.* ]]; then
      dB_index=$index
    fi
  done 
  mstring=( $(amixer ${MUTE_CTL_TYPE[0]} ${MUTE_CTL_ID[0]} sget ${MUTE_CTL_NAME[0]} | grep -e '\[' -m 1 | cut -f2- -d: ) )
  if [[ "$mstring" == *"[on]"* ]]; then 
    mstring="[on]"
  elif [[ "$mstring" == *"[off]"* ]]; then
    mstring="[off]"
  else
    mstring=""
  fi

  VOLUME_CONTROL_LEVEL=${volume_info[$vol_level_index]}
  #clear screen before writing volume info
  if [ -z "$DEBUG_MODE" ]; then clear; fi #clear the screen unless in debug mode
  #render the volume control
  case $VOLUME_CONTROL_STYLE in
  num*)
    #accepts number, numeric, numerical
    #build the text string containing the volume information
    vstring="VOL: ${volume_info[$vol_percent_index]}"
    if [ $dB_index -ne -1 ]; then
      vstring+=" ${volume_info[$dB_index]}"
    fi
    vstring+=" $mstring"
    #write the volume information
    echo $vstring
    ;;
  *)
    #the other option is a graphical volume control: 
    vstring=" VOL >"
    local barpos
    local max_level
    max_level=${VOL_CTL_MAX_LEVEL[0]}      
    barpos=$(( ${volume_info[$vol_level_index]} * $VOLUME_CONTROL_COLS / $max_level ))
    for ((index=0; index<$barpos; index++))
    do
      vstring+="|"
    done
    for ((index=$barpos; index<$VOLUME_CONTROL_COLS; index++))
    do
      vstring+="."
    done
    vstring+="<  "
    #done with volume bar. Add dB and muting info
    if [ $dB_index -ne -1 ]; then
      vstring+=" ${volume_info[$dB_index]}"
    fi
    vstring+=" $mstring"
    #write the volume information
    echo "$vstring"
    ;;
  esac
  vstring="press u to increase, d to decrease,"
  if [ $MUTING_IS_AVAILABLE -gt 0 ]; then
    vstring+=" m to mute,"
  fi
  vstring+=" or v to exit"
  echo $vstring
  echo $message #will display any messages about errors encountered while in volume control mode
  message="" #clear any existing text
}



function set_volume_control {
  #call with first parameter either u,d, or m
  #reset VOLUME_CONTROL_TIMEOUT timer
  SECONDS=0
  local control_action
  if [[ "$1" == "m" ]]; then
    if [ $MUTING_IS_AVAILABLE -eq 0 ]; then
      #oops, received request to mute but the control does not have that capability
      message="MUTING IS NOT AVAILABLE FOR THIS VOLUME CONTROL"
      return
    fi
    #determine if the control is muted [off] or unmuted [on]
    #get the state of the first mute control
    local mstring
    mstring=$(amixer ${MUTE_CTL_TYPE[0]} ${MUTE_CTL_ID[0]} sget ${MUTE_CTL_NAME[0]} )
    if [[ "$mstring" == *"[on]"* ]]; then
      if [ $MUTING_IS_AVAILABLE -eq 1 ]; then
        control_action="mute"
      else
        control_action="toggle"
      fi
      #Mute the control
      for (( i=0 ; i<${#MUTE_CTL_TYPE[@]} ; i++ ));
      do
        amixer ${MUTE_CTL_TYPE[i]} ${MUTE_CTL_ID[i]} -- sset ${MUTE_CTL_NAME[i]} $control_action >> /dev/null
      done
    else
      if [ $MUTING_IS_AVAILABLE -eq 1 ]; then
        control_action="unmute"
      else
        control_action="toggle"
      fi
      #Unmute the control
      for (( i=0 ; i<${#UNMUTE_CTL_TYPE[@]} ; i++ ));
      do
        amixer ${UNMUTE_CTL_TYPE[i]} ${UNMUTE_CTL_ID[i]} -- sset ${UNMUTE_CTL_NAME[i]} $control_action >> /dev/null
      done
    fi
    return
  fi
  #determine the multiplier for the volume change.
  #this is useful for e.g. pulse audio which has a total volume range of 65k versus 64 or 128 for ALSA controls
  local multiplier=0
  if [[ ${VOL_CTL_MAX_LEVEL[0]} > 100 ]]; then
    multiplier=${VOL_CTL_MAX_LEVEL[0]}
    multiplier=$(( multiplier - 100 ))
    multiplier=$(( multiplier / 100 ))
  fi
  if [ "$multiplier" -lt 1 ]; then
    multiplier=1
  fi

  #process volume control changes:
  if [[ "$1" == "u" ]]; then
    VOLUME_CONTROL_LEVEL=$((VOLUME_CONTROL_LEVEL + $2 * $multiplier)) #increment control_action
  elif [[ "$1" == "d" ]]; then
    VOLUME_CONTROL_LEVEL=$((VOLUME_CONTROL_LEVEL - $2 * $multiplier)) #decrement control_action
  else
    #assume the desired control level has been passed
    VOLUME_CONTROL_LEVEL=$1
  fi
  #Test for volume < 0
  #NOTE: if volume > max, ALSA will automatically set volume = max level during sset operation
  if [ "$VOLUME_CONTROL_LEVEL" -lt 0 ]; then 
    VOLUME_CONTROL_LEVEL=0 #set values<0 to zero 
  fi
  #SET the new VOLUME_CONTROL_LEVEL
  for (( i=0 ; i<${#VOL_CTL_TYPE[@]} ; i++ ));
  do
    #set the gain of the control 'control_name' on the ALSA card/device
    #silence the output
    amixer ${VOL_CTL_TYPE[i]} ${VOL_CTL_ID[i]} -- sset ${VOL_CTL_NAME[i]} $VOLUME_CONTROL_LEVEL >> /dev/null
  done
}


function do_volume_control {
#when entering, test the contents of the variable user_action
#  v --> volume control mode
#  m --> immediately mute, then enter volume control mode
  SECONDS=0 #reset the bash shell seconds timer
  message="" #clear any existing text
  local user_keypress
  local extra_keypress
  local last_user_keypress
  local volume_increment=1
  local acceleration_accumulator=0
  if [[ "$user_action" == "m" ]]; then
    set_volume_control "m"
  fi
  show_volume

  #turn off screen echo of user input 
  stty -echo
  while true; do
    last_user_keypress=$user_keypress 
    read -t 0.05 -N 1 extra_keypress
    if [[ $extra_keypress != "" ]] && [[ $last_user_keypress == $user_keypress ]]; then
      (( acceleration_accumulator++ )) #creates acceleration by incresing the increment of change
    else
      acceleration_accumulator=0
    fi
    volume_increment=$(( 1 + acceleration_accumulator / 5 ))
    #clear any remaining keystrokes
    read -t 0.05 -N 10 input_bufer_data
    #get new keyboard input. 
    read -rs -n 1 -t 1 user_keypress
    if [[ "$user_keypress" == "v" ]] || [[ "$input_bufer_data" == *"v"* ]]; then 
      #restore stty before exiting
      stty echo
      return
    fi
    if [[ "$input_bufer_data" == *"m"* ]]; then
      user_keypress="m"
    fi
    if [[ "$user_keypress" == "u" ]] || [[ "$user_keypress" == "d" ]] || [[ "$user_keypress" == "m" ]]; then 
      set_volume_control "$user_keypress" "$volume_increment"
    fi
    #Compare elapsed time in volume control mode to user provided timeout time
    # Return if volume control mode has timed out. 
    # When VOLUME_CONTOL_TIMEOUT=0 this check is not performed 
    if [ "$VOLUME_CONTROL_TIMEOUT" -gt 0 ]; then
      if [ "$SECONDS" -gt "$VOLUME_CONTROL_TIMEOUT" ]; then 
        stty echo
        return
      fi 
    fi
    #if not timed out, refresh volume control display
    show_volume
  done
}


function all_systems_off {
  #checks status and turns off all systems
  local f
  for f in *; do #$f=active_system_dir, loop over all contents
    if ! [ -d "$f" ]; then
      continue #if item $f is not a directory, skip to the next $f
    fi
    if [[ ${f:0:1} == "_" ]] ; then
      continue #skip directory if name begins with an underscore
    fi
    system_name=${f//"_"/" "} #$f=active_system_dir
    system_directory=$f
    cd $system_directory #$f=active_system_dir
    error_flag=""
    get_system_status
    #get_system_status RETURN CODES:
    # 0: no PID file found
    # 1: PID file and corresponding process found
    # 2: PID file found but corresponding process not found
    if [ $? == 1 ]; then
      do_system_terminate
    fi
    cd ..
  done #done toggling all systems OFF
  ACTIVE_SYSTEM=0  #set active system id to 'none'
}


function execute_user_action {
  local system_status_code
  local intialize_to_active_system
  local ps_retval
  local system_counter
  local f
  if [ $ACTIVE_SYSTEM -eq -1 ] && [[ $IO_MODE == "preamp" ]]; then
    #at first startup, set intialize_to_active_system to true
    #if a system is already running, ACTIVE_SYSTEM will become non-zero (below)
    #in that case the configuration file for the ACTIVE_SYSTEM will be read
    #   and it's parameters will be instantiated for the instance 
    #   of GASSysCon that is just system starting up
    intialize_to_active_system='true'
  fi  
  if [ -z "$DEBUG_MODE" ]; then clear; fi #clear the screen unless in debug mode
  case $user_action in
  r) #user input r displays status of all registered systems
    SAVEIFS=$IFS
    IFS='%' #need to set this to be something other than white space here until status screen has been written
    if [ "$system_count" == 0 ]; then  
      echo "FATAL ERROR: There are no registered systems to control!"
      echo "Please consult README.txt and SetUpGuide.txt for setup instructions."
      exit 1
    fi
    #print header for system status report
    if [[ $SESSION_TITLE != "" ]]; then
      echo -e $SESSION_TITLE
    fi
    echo -n " "
    echo -n $(pad2width "#" $SYS_NUM_WIDTH)
    echo -n $(pad2width "STATUS" $RUNTIME_WIDTH)
    echo "   SYSTEM NAME"
    echo "----------------------------------------------------------"
    #loop through subdirectories of this directory that contain info on each system info
    system_counter=1
    ACTIVE_SYSTEM=0
    for f in *; do #$f=active_system_dir, loop over all contents
      if ! [ -d "$f" ]; then
        continue #if item $f is not a directory, skip to the next $f
      fi
      if [[ ${f:0:1} == "_" ]] ; then
        continue #skip directory if name begins with an underscore
      fi
      #convert underscores in system folder names to spaces for display 
      system_name=${f//"_"/" "} #$f=active_system_dir
      system_directory=$f
      cd $system_directory #$f=active_system_dir
      echo -n " "
      echo -n $(pad2width $system_counter $SYS_NUM_WIDTH)
      if [ -f "PID" ]; then
        sys_pid=$(cat PID)
        ps_retval=-1
        if [[ "$sys_pid" != "" ]]; then
          ps -p $sys_pid > /dev/null
          ps_retval=$?
        fi 
        if [[ "$sys_pid" != "" ]] && [ $ps_retval -eq 0 ]; then   #the PID exists so the system is ON
          ACTIVE_SYSTEM=$system_counter
          if [[ $intialize_to_active_system == 'true' ]]; then
            build_system_configuration_from_file #build the system configuration to intialize all parameters
          fi
          #we need to get elapsed runtime for sys_pid here using the following code:
          RUNTIME=$(ps -p $sys_pid -o etime=)
          RUNTIME=$(reformat_for_output $RUNTIME) 
          RUNTIME=`expr "$RUNTIME" : "^\ *\(.*[^ ]\)\ *$"` #remove whitepaces
          if [ "$RUNTIME" = "" ]; then RUNTIME="0sec"; fi #make sure RUNTIME contains some text
          echo -n $(pad2width $RUNTIME $RUNTIME_WIDTH) 
          echo "   "$system_name
        else
          #the PID does not exist. Remove the file to expunge the error
          message="ERROR: no running process for $system_name could be found"
          commit_to_log $message
          echo -n $(pad2width "err" $RUNTIME_WIDTH)
          echo "   "$system_name
          rm PID
          if ! [[ $DEBUG_MODE == "" ]]; then
            if ! [[ $RAM_FS_ROOT == "" ]]; then
              #need to copy gstreamer output file from ram disk to fixed disk
              #copy the gst_server_output.txt file from memory into the system directory and note in log
              echo '#'$RAM_FS_ROOT'/'$FD_PROG_DIRNAME'/system_info/'$system_directory'/gst_server_output.txt' $DEBUG_INFO_PATH'/error_output.txt'
              mv $RAM_FS_ROOT'/'$FD_PROG_DIRNAME'/system_info/'$system_directory'/gst_server_output.txt' $DEBUG_INFO_PATH'/error_output.txt'
              message="information about this error has been placed into the file:\n   $DEBUG_INFO_PATH/error_output.txt" 
              commit_to_log $message
            fi
          fi
        fi             
      else
        #a PID file does not exist, so the system is OFF
        echo -n $(pad2width "OFF" $RUNTIME_WIDTH)
        echo "   "$system_name
      fi
      cd ..
      ((system_counter+=1))
    done
    echo "----------------------------------------------------------"
    IFS=$SAVEIFS
    ;;
  a) #user input a invokes automated mode
    SAVEIFS=$IFS
    IFS='%' #need to set this to be something other than white space here until runtime is written
    system_counter=0
    for f in *; do #$f=active_system_dir, loop over all contents
      if ! [ -d "$f" ]; then
        continue #if item $f is not a directory, skip to the next $f
      fi
      if [[ ${f:0:1} == "_" ]] ; then
        continue #skip directory if name begins with an underscore
      fi
      ((system_counter+=1))
      if [ "$system_counter" == "$auto_system_number" ] || [ "$f" == "$auto_system_folder_name" ]; then #$f=active_system_dir
        system_name=${f//"_"/" "} #$f=active_system_dir
        system_directory=$f
        cd $system_directory #$f=active_system_dir
        if [ "$auto_system_action" == "OFF" ]; then
          do_system_terminate 'exit'
          exit 0
        fi
        if [ "$auto_system_action" == "ON" ]; then
          do_system_launch 'exit'
          exit 0
        fi
        message='ERROR: The automated action must be either ON or OFF'
        commit_to_log $message
        exit 1
      fi
    done #done looping over systems 
    #if we get here, there was no system matching supplied system number or name
    message='ERROR: no system was found matching the supplied system name of '$auto_system_folder_name
    commit_to_log $message
    exit 1
    ;;
  k) #user input k causes automated termination of all systems
    SAVEIFS=$IFS
    IFS='%' #need to set this to be something other than white space here until runtime is written
    system_counter=0
    message="KILLALL: attempting to terminate all system processes on both server and client sides"
    commit_to_log $message
    #loop over all systems
    for f in *; do #$f=active_system_dir, loop over all contents
      if ! [ -d "$f" ]; then
        continue #if item $f is not a directory, skip to the next $f
      fi
      if [[ ${f:0:1} == "_" ]] ; then
        continue #skip directory if name begins with an underscore
      fi
      ((system_counter+=1))
      system_name=${f//"_"/" "} #$f=active_system_dir
      system_directory=$f
      cd $system_directory #$f=active_system_dir
      error_flag=""
      do_system_terminate #terminate this system
      cd ..
    done #done looping over systems
    #kill any unaccounted-for gst-launch-1.0 processes on the server
    killall gst-launch-1.0
    IFS=$SAVEIFS
    ;;
  p) #toggle power via user-supplied scripts. This options is only available in PREAMP mode
      #make sure all systems are off before powering up/down
      if (( $ACTIVE_SYSTEM > 0 )); then 
        all_systems_off; 
      fi
      #execute user power up/down script 
      eval 'bash -s' -- < $POWER_CONTROL_SCRIPT
    ;;
  v|m) #volume control. These options are only available in PREAMP mode
      if [ $ACTIVE_SYSTEM -gt 0 ]; then
        if [[ ${#VOL_CTL_TYPE[@]} > 0 ]]; then 
          do_volume_control;
        else
          message="volume control is unavailable"
          if [[ $IO_MODE == "preamp" ]]; then
            message+=": no volume controls were declared for this system."
          else
            message+=": no volume control was declared in the config file."
          fi
          commit_to_log $message
        fi 
      fi
    ;;
  M)
    #toggle the display of system messages
    if [[ $COLLECT_MESSAGES == "true" ]]; then
      COLLECT_MESSAGES="false"
    else
      COLLECT_MESSAGES="true"
    fi
    ;;
  d)
    #toggle debug-no-run mode on/off
    if [[ $DEBUG_MODE == "" ]]; then
      DEBUG_MODE="no-run"
      COLLECT_MESSAGES="true"
      message="DEBUG NO_RUN mode has been enabled. Press d or D to disable it."
      commit_to_log $message
    else
      DEBUG_MODE=""
      message="DEBUG mode has been disabled."
      commit_to_log $message
    fi
    ;;
  D)
    #toggle debug-run mode on/off
    if [[ $DEBUG_MODE == "" ]]; then
      DEBUG_MODE="run"
      COLLECT_MESSAGES="true"
      message="DEBUG RUN mode has been enabled. Press d or D to disable it."
      commit_to_log $message
    else
      DEBUG_MODE=""
      message="DEBUG mode has been disabled."
      commit_to_log $message
    fi
    ;;
  0)
    #turn all systems off.
    all_systems_off
    ;;
  *) #user input is index of system to toggle ON or OFF
    #when in PREAMP mode only one system can be ACTIVE on) at a time
    #  if there is an ACTIVE_SYSTEM and the user action will turn on a different system
    #  then turn off the ACTIVE_SYSTEM before turning on the new one
    if [[ $IO_MODE == "preamp" ]] && [[ $ACTIVE_SYSTEM > 0 ]] && [[ $ACTIVE_SYSTEM != $user_action ]]; then
      all_systems_off
    fi 
    SAVEIFS=$IFS
    IFS='%' #need to set this to be something other than white space here until runtime is written
    #step through systems and turn provided system number ON/OFF 
    system_counter=0
    for f in *; do #$f=active_system_dir, loop over all contents
      if ! [ -d "$f" ]; then
        continue #if item $f is not a directory, skip to the next $f
      fi
      if [[ ${f:0:1} == "_" ]] ; then
        continue #skip directory if name begins with an underscore
      fi
      ((system_counter+=1))
      if [[ "$system_counter" == "$user_action" ]]; then
        break;
      fi
    done 
    system_name=${f//"_"/" "} #$f=active_system_dir
    system_directory=$f
    cd $system_directory #$f=active_system_dir
    error_flag=""
    get_system_status
    system_status_code=$? #copy the return code into system_status_code
    #STATUS RETURN CODES:
    # 0: no PID file found
    # 1: PID file and corresponding process found
    # 2: PID file found but corresponding process not found
    if [ $system_status_code == 1 ]; then
      do_system_terminate
    else
      do_system_launch
    fi
    cd ..
    IFS=$SAVEIFS
    #done turning system ON/OFF
    ;;
  esac #done with case statement 
  
  if [[ $error_flag != "" ]]; then
    commit_to_log $error_flag
    error_flag=""
  fi
} #end function 'execute_user_action'


function startup_and_initialize {
  #check if log file needs to be truncated
  local num_lines
  local shorter
  num_lines=$(wc -l < $LOGFILE_PATH/$LOG_FILENAME)
  if (( num_lines > $LOG_MAX_LINES )); then
    #truncate log file to 80% of LOG_MAX_LINES lines
    #calculate the number of lines to truncate to
    shorter=$(( LOG_MAX_LINES * 8 / 10 ))
    #truncate into temp file and then copy temp file over the logfile
    tail -n $shorter $LOGFILE_PATH/$LOG_FILENAME > $LOGFILE_PATH/temp
    cat $LOGFILE_PATH/temp > $LOGFILE_PATH/$LOG_FILENAME
    rm $LOGFILE_PATH/temp
    message="Truncated the log file from $num_lines to $shorter lines."
    commit_to_log "$message"
  fi
  
  if [[ $RAM_FS_ROOT == "" ]]; then
    #there is no RAM FS ROOT specified, so use the systems directly from the FD instead
    #cd to the systems path on the FD
    cd $SYSTEMS_PATH
    message="No RAM FS ROOT specified - using the systems configurations on the FD.\nWARNING: Operation may be somewhat disk intensive."
    commit_to_log "$message" 
    #skip the rest of the function
    return 
  fi
  
  local RAM_PATH
  #synchronize system files on the RAM FS with those on the FD
  #build the pathname in RAM where systems should be located
  RAM_PATH=$RAM_FS_ROOT'/'$SYSTEMS_rPATH 
  #check to see if that path exists  
  if [ ! -d "$RAM_PATH" ]; then
    #that path and dir structure doesn't exist in RAM_FS_ROOT
    #create it including all parent directories as needed 
    mkdir -p $RAM_PATH
  fi
  
  #The dir structure exists in RAM_FS_ROOT
  #make sure all system directories under the fixed disk location are found in RAM
  #  do this by copying them even if they already exist, overwriting contents
  #  this will force an update in case any files or dirs were recently created or modified
  cp -R $SYSTEMS_PATH $(dirname "$RAM_PATH")

  #The final step is to check to make sure no dirs exist in RAM that are not on the FD
  #   This could happen if a dir was renamed or deleted on the FD
  #   If these exist, delete them and their contents
  diff -u <(ls $SYSTEMS_PATH) <(ls $RAM_PATH)  | sed -n '4,$s/^+//p' | xargs -I{} rm -r $RAM_PATH'/'{}
  
  #Now that the system info is properly cloned into the RAM FS we change the 
  #   current directory to RAM_PATH:
  cd $RAM_PATH
  
} #end function 'startup_and_initialize'


function set_program_mode_from_user_input {
  #perform user direction action, or produce help, copyright, version info text
  #check for progam options to print help, version, and copyright info:
  if [ ${#all_args[@]} -eq 0 ] || [[ ${all_args[0]} = "--help" ]] || [[ ${all_args[0]} = "-h" ]]; then
    #print help file and exit
    echo
    cat $DOCS_PATH/help.txt
    echo
    exit 0
  elif ( [[ ${all_args[0]} = "--version" ]] || [[ ${all_args[0]} = "-v" ]] ); then
    #print program version number info
    echo "version $VERSION_NUMBER"
    exit 0
  elif ( [[ ${all_args[0]} = "--copyright" ]] || [[ ${all_args[0]} = "-c" ]] ); then
    #print short copyright info and direct user to read included copyright terms
    echo '    Copyright (C) 2018 by Charlie Laub under GPL3'
    echo "    This program comes with ABSOLUTELY NO WARRANTY; This is free software" 
    echo "    and you are welcome to redistribute it under certain conditions."
    echo "    Please see the included GPL3 copyright terms for complete information."
    exit 0
  elif ( [[ ${all_args[0]} = "--killall" ]] || [[ ${all_args[0]} = "-k" ]] ); then
      user_action="k" #killall mode
      commit_to_log "Initiating killall action... \n"
      execute_user_action
      exit 0
  #check for automated mode
  elif ( [[ ${all_args[0]} = "--auto" ]] || [[ ${all_args[0]} = "-a" ]] ); then
    #implement run-once automated mode. Requires three arguments.
    if [[ ${#all_args[@]} < 3 ]]; then #if number of args in all_args array is < 3, then...
      commit_to_log "ERROR: automated mode requires three parameters."
      exit 1
    fi
    #count the number of systems.
    system_count=$(find ./* -maxdepth 0 -type d | wc -l)
    if [[ "${all_args[1]}" =~ ^[0-9]+$ ]]; then
      if [[ ${all_args[1]} > 0 ]] && [[ "${all_args[1]}" -le "$system_count" ]]; then
        user_action="a" #use automated mode
        auto_system_number=${all_args[1]} #supplied parameter was a system number
        auto_system_folder_name="" #not using system name method, so set to empty string
        auto_system_action=${all_args[2]} #set action for auto mode
        commit_to_log "Performing the following action using automated mode:"
        execute_user_action
      else
        commit_to_log "ERROR: the supplied parameter '${all_args[1]}' did not correspond to a system number. \n"
        exit 1
      fi
    else
      #supplied info was not numeric, so assume this is a system name
      user_action="a" #use automated mode
      auto_system_number="" #supplied parameter was not a system number, so set to empty string
      auto_system_folder_name=${all_args[1]} #set system name for auto mode action
      auto_system_action=${all_args[2]} #set action for auto mode
      commit_to_log "Performing the following action using automated mode..."
      execute_user_action
    fi
    #should not get here!
    commit_to_log "ERROR: an unknown error was encountered for automated mode."
    exit 1 
  #check suitability of input parameters for continuous mode operation
  elif ( [[ ${all_args[0]} = "-r" ]] || [[ ${all_args[0]} = "--run" ]] ) && [[ "${all_args[1]}" =~ ^[0-9]+$ ]]; then 
    if [[ ${all_args[1]} > 1 ]]; then
      #continuous update mode
      continuous_update=1
      if [ -z "$DEBUG_MODE" ]; then clear; fi #clear the screen.   
      echo -e "\nENTERING CONTINUOUS UPDATE MODE. UPDATE INTERVAL = ${all_args[1]} SECONDS \n"
      sleep 2 #give the user time to read the message...
    else
      #run once mode
      continuous_update=0 
    fi
  else
    #the user supplied parameters do not match any known operating mode. Return error and exit.
    message=$( IFS=$' '; echo "${all_args[*]}" )
    message="ERROR: the supplied parameters '$message' did not correspond to any operating mode. \n"
    commit_to_log "$message" 
    echo "$message"
    exit 1
  fi
} #end function 'set_program_mode_from_user_input'


function read_config_file {
  while IFS='' read -r ONE_LINE || [[ -n "$ONE_LINE" ]]; do
    #check for and remove any comments (test starting with a '#') on the line
    comment_identifier_position=$(strindex "$ONE_LINE" "#")
    if [ $comment_identifier_position != "-1" ]; then 
      #remove the comment
      ONE_LINE=${ONE_LINE:0:$comment_identifier_position}
    fi
    #remove any leading and trailing whitespace
    ONE_LINE=`expr "$ONE_LINE" : "^\ *\(.*[^ ]\)\ *$"`
    if [[ $ONE_LINE = "" ]]; then
      #if ONE_LINE is now blank, just skip to the next line
      continue;
    fi

    #flag type config file parameters:
    if [[ $ONE_LINE == "SHOW_SYSTEM_MESSAGES" ]]; then
      COLLECT_MESSAGES="true"
      continue
    fi
    
    #config file parameters in the form field_identifier = field_contents:
    local field_identifier=""
    local field_contents=""
    IFS=''
    
    separate_field_identifier_from_field_contents "=" "$ONE_LINE" #using this instead...
    
    case $field_identifier in
    TIMEOUT_TIME)
      TIMEOUT_TIME=$field_contents
    ;;
    SYS_NUM_WIDTH)
      SYS_NUM_WIDTH=$field_contents
    ;;
    RUNTIME_WIDTH)
      RUNTIME_WIDTH=$field_contents
    ;;
    LOG_MAX_LINES)
      LOG_MAX_LINES=$field_contents
    ;;
    RAM_FS_ROOT)
      local result
      result=$(df -h | grep $field_contents)
      if [[ "$result" == "" ]]; then
        message="FATAL ERROR: the RAM path $field_contents specified in the configuration file was not found. \nUse df -h to view valid tmpfs/ramfs filepaths"
        commit_to_log "$message" 
        echo
        echo -e "$message"
        echo
        exit 1
      fi
      RAM_FS_ROOT=$field_contents
    ;;
    DEBUG_INFO_PATH)
      DEBUG_INFO_PATH=$field_contents
    ;;
    AUDIO_SOURCE)
      AUDIO_SOURCE=$field_contents
    ;;
    OPERATING_MODE)
      IO_MODE=$field_contents
    ;;
    POWER_CONTROL_SCRIPT)
      if [ ${field_contents:0:1} = "~" ]; then
        #oops, first character is the tilde. Need to expand it.
        #replace the tilde with the HOME path for the user
        field_contents=${HOME}${field_contents:1}
      fi
      POWER_CONTROL_SCRIPT=$field_contents
    ;;
    VOLUME*)
      if [[ "$IO_MODE" != "preamp" ]]; then
        process_volume_control_info $field_identifier $field_contents
      fi
    ;;
    SESSION_TITLE)
      #the session title is displayed at the top of the continuous and run-once system status display screen
      SESSION_TITLE=$field_contents
    ;;
    SYSTEMS_FILEPATH)
      #the filepath relative to the system_info directory where system directories are located 
      #Append the user dir/path to the default value  
      SYSTEMS_rPATH+=/$field_contents
      SYSTEMS_PATH+=/$field_contents
    ;;
    LOG_FILENAME)
      #log messages to this file. If not supplied, the default name of logfile will be used
      LOG_FILENAME=$field_contents
    ;;
    esac
  done < $CONFIG_FILE_NAME
  
  #make sure critical parameters are set, or exit with error flag set
  if [[ "$IO_MODE" != "preamp" ]] && [[ "$IO_MODE" != "streaming" ]]; then
      message="FATAL ERROR: the supplied OPERATING MODE of $IO_MODE is not a recognized mode. Mode must be streaming or preamp. Terminating."
      commit_to_log "$message" 
      echo
      echo "$message"
      echo
      exit 1
  fi
  #test for streaming mode required parameters
  if [[ "$IO_MODE" == "streaming" ]]; then
    if [[ "$AUDIO_SOURCE" == "" ]]; then
      message="FATAL ERROR: no AUDIO_SOURCE was set. Terminating."
      commit_to_log "$message" 
      echo
      echo "$message"
      echo
      exit 1
    fi
  fi
} #end function 'read_config_file'


process_cmd_line_args() {
#looks thru the command line arguments for a user-supplied configuration file filepath
#  the syntax is: --config_file=filename
#all remaining command line arguments are copied into the array all_args
   local parameter
   local tmp
   local value 
   until [ -z "$1" ] ; do
      if [ ${1:0:1} = '-' ] ; then
         tmp=${1:1} # Strip off leading '-' . . .
         if [ ${tmp:0:1} = '-' ] ; then
            tmp=${tmp:1} # Allow double -
         fi
         parameter=${tmp%%=*} # Extract name.
         value=${tmp##*=} # Extract value.
      else
        parameter=$1
      fi
      if [[ "$parameter" == "debug" ]]; then
        DEBUG_MODE="on"
      elif [[ "$parameter" == "config_file" ]]; then
         if [ ${value:0:1} = "~" ]; then
            #oops, first character is the tilde. Need to expand it.
            #replace the tilde with the HOME path for the user
            value=${HOME}${value:1}
         elif [ ${value:0:1} != "/" ]; then
            #since the filepath specified by the user did not begin at the root dir
            #  the filepathname must be located in the PROG_CONFIGS_PATH directory
            #  so prepend the PROG_CONFIGS_PATH to value
            value=$PROG_CONFIGS_PATH'/'$value
         fi
         #test to see if the filepathname exists
         if [ -e $value ]; then
            CONFIG_FILE_NAME=$value;
            message="Initializing with user specified configuration file: $value"
            commit_to_log "$message" 
         else
            message="ERROR: The configuration file: $value does not exist.\nFatal error. Terminating execution."
            commit_to_log "$message" 
            exit 1
         fi
      else
         all_args+=("$1")  #add this argument to all_args
      fi
      shift
   done
}  #end function process_cmd_line_args


function setup_filepaths () {
   #set various path variables used within the code
   #start by getting the path to the directory where this script resides
   local SOMEPATH
   local SOURCE_PATH
   SOURCE_PATH="${BASH_SOURCE[0]}"
   while [ -h "$SOURCE_PATH" ]; do # resolve $SOURCE_PATH until the file is no longer a symlink
     SOMEPATH="$( cd -P "$( dirname "$SOURCE_PATH" )" && pwd )"
     SOURCE_PATH="$(readlink "$SOURCE_PATH")"
     #if $SOURCE_PATH was a relative symlink, we need to resolve it relative to the path 
     #   where the symlink file was located
     [[ $SOURCE_PATH != /* ]] && SOURCE_PATH="$SOMEPATH/$SOURCE_PATH" 
   done
   SOMEPATH="$( cd -P "$( dirname "$SOURCE_PATH" )" && pwd )" 
   #variable SOMEPATH now holds the script directory path
   #cd to that directory and then go up one level:
   cd $SOMEPATH; cd ..   
   SOMEPATH=$(pwd) #path to main/top dir of this program on fixed disk
   FD_PROG_DIRNAME=$(basename $SOMEPATH) #name of the main/top dir of this progam
   cd ..
   FD_FS_ROOT=$(pwd) #path to dir in which this program is installed on FD
   #now set filepath and dirname variables:
   #  PATH variables are a complete path
   #  rPATH variables are a path relative to the FD_FS_ROOT
   #  DIRNAME variables hold the name of the dir name only
   LOGFILE_PATH=$FD_FS_ROOT'/'$FD_PROG_DIRNAME'/log'
   PROG_CONFIGS_PATH=$FD_FS_ROOT'/'$FD_PROG_DIRNAME'/config'
   DOCS_PATH=$FD_FS_ROOT'/'$FD_PROG_DIRNAME'/docs'
   FILTER_DEFS_PATH=$FD_FS_ROOT'/'$FD_PROG_DIRNAME'/filter_defs'

   #set the default path where system info resides
   SYSTEMS_rPATH=$FD_PROG_DIRNAME'/system_info'
   SYSTEMS_PATH=$FD_FS_ROOT'/'$SYSTEMS_rPATH
   
} #end function setup_filepaths




# ============================================================================ #
#                                                                              #
#                          BEGIN MAIN PROGRAM HERE                             #
#                                                                              #
# ============================================================================ #

#set defaults for some configuration variables
COLLECT_MESSAGES=false
MESSAGE_COLLECTOR=""
SESSION_TITLE=""
continuous_update="not set"
user_action="r" #initialize user action to show the system list
gst_pid=0
CONFIG_FILE_NAME="" #force user to supply system configuration file by setting this to empty
TIMEOUT_TIME=30    #number of seconds for 'run once' mode to time out
SYS_NUM_WIDTH=5    #width of the system number field in the status output
RUNTIME_WIDTH=16   #width of the runtime field in the status output
LOG_MAX_LINES=100  #the number of lines to keep in the log file
RAM_FS_ROOT='/dev/shm' #tmpfs/ramfs FS. do not include a trailing "/" in the path
DEBUG_INFO_PATH=${HOME}'/GSASysCon_debug' #where info is written when in debug mode
CLIENT_INFO_PATH='GSASysCon_messages' #dir for GSASysCon output on client side
LOG_FILENAME="logfile"
IO_MODE=""
POWER_CONTROL_SCRIPT=""
SERVER_RTPBIN_PARAMS=""
pre_processed_sys_config=""
declare -a VOL_CTL_TYPE 
declare -a VOL_CTL_ID
declare -a VOL_CTL_NAME
declare -a VOL_CTL_MAX_LEVEL
declare -a MUTE_CTL_TYPE
declare -a MUTE_CTL_ID
declare -a MUTE_CTL_NAME
declare -a UNMUTE_CTL_TYPE
declare -a UNMUTE_CTL_ID
declare -a UNMUTE_CTL_NAME
declare -a SINK_CONNECTIONS
declare -a route_and_clones
declare -a GST_SERVER_CODE  
declare -a SYNCHRONIZED_PLAYBACK  

VOLUME_CONTROL_STYLE="graphical"
VOLUME_CONTROL_COLS="50"
VOLUME_CONTROL_TIMEOUT=0
MUTING_IS_AVAILABLE=""
declare -a all_args
SYSTEMS_FILEPATH=""
ACTIVE_SYSTEM=-1    #active system id. preamp mode only - keeps track of which system is "on"
                    #initialize to -1 to flag startup condition
system_directory=""
IFS=" " read server_IP_address dummy <<< $(hostname -I) #get server IP address

#determine the path to this script file, and generate paths relative to that path
setup_filepaths 

# Process command line arguments:
#   extract the user supplied configuration file filepath 
#   parse all other command line arguments into the array all_args
process_cmd_line_args "$@"
#check for user supplied conf file. If none, exit with error
if [[ $CONFIG_FILE_NAME == "" ]]; then
  message="ERROR: a program config file was not specified on the command line!\nThis is a required parameter. Terminating execution."
  commit_to_log "$message"
  echo -e $message
  echo -e "Please consult the help file below for syntax information:"
  echo
  cat $DOCS_PATH/help.txt
  echo
  exit 1
fi

#set the configuration variables with the values provided in the program config file that
#   was specified by the user on the command line
#cd to the PROG_CONFIGS_PATH - all progam config files must be located there
cd $PROG_CONFIGS_PATH
#read in and process the config file specified by the user
read_config_file

#create DEBUG_INFO_PATH if it does not exist
ls $DEBUG_INFO_PATH > /dev/null 2>&1
if [ $? -ne 0 ]; then
  #the DEBUG_INFO_PATH does not exist, so create it
  mkdir $DEBUG_INFO_PATH
fi


#perform startup operations...
startup_and_initialize
# NOTE: if RAM_FS_ROOT was specified by the user all reads/writes of system status after this  
#   point are in memory except for the log file, which is always written to the fixed disk
#   If RAM_FS_ROOT is invalid or empty, all operations will take place on disk (can be disk intensive)

set_program_mode_from_user_input

#count the number of systems.
system_count=$(find ./* -maxdepth 0 -type d | wc -l)

#Build a list of permissable user inputs
#When complete, each entry will have a space to its left and right
#k = kill all
#r = show status of all registered systems
#x = exit
#v = enter volume control environment
#m = enter volume control environment and immediately mute
#M = toggles display of system messages
#d = toggles debug-no-run mode on/off
#D = toggles debug-run mode on/off
#0 = turn all systems off

permissible_responses=" k r x v m M d D 0"
#add system numbers to permissible responses
for (( system_index=1; system_index<=$system_count; system_index++ ))
do
 permissible_responses+=" $system_index"
done
permissible_responses+=" " #add the final space to the string

 

#loop that implements the run once and continuous update modes
for ((;;))
do
  user_action="r" #initial user action for run once and continuous update modes 
  execute_user_action #initially user_action is set to 'r' to display status   

  #list options for user input
  echo "Enter a system number to toggle it ON/OFF, x to exit"
  
#  if [[ $COLLECT_MESSAGES == "true" ]] && [[ $MESSAGE_COLLECTOR != "" ]]; then
  if [[ $COLLECT_MESSAGES == "true" ]]; then
    echo
    echo "SYSTEM MESSAGES:"
    echo -e $MESSAGE_COLLECTOR
    MESSAGE_COLLECTOR=""
  fi

  #wait for and then read user input
  if [ $continuous_update -eq 0 ]; then
    read -t $TIMEOUT_TIME user_action #wait for user input until TIMEOUT_TIME has passed 
  else
    read -t ${all_args[1]} user_action #wait for user input until the update interval to passed
  fi

  #process result of the read:
  if [ "$?" != "0" ]; then #if read timed out, then...
    if [ $continuous_update -eq 0 ]; then
      #run-once mode timed out, so exit
      echo "Run Once mode did not receive an input before timing out. Exiting." 
      exit 0
    else
      #run-continuous mode timed out, so skip over rest of loop
      continue
    fi
  fi

  #test the user input against permissible actions
  if [[ ! "$permissible_responses" =~ " "$user_action" " ]]; then
     if [[ $user_action == "" ]]; then
        #user pressed the return key, just update the status display
        continue
     fi
     echo
     echo "That is not a valid option"
     echo
     if [ $continuous_update -eq 0 ]; then 
        #if in run once mode, exit
        exit 1
     else
        sleep 2
        continue
     fi
  fi

  #is the user input x for exit?
  if [ "$user_action" == "x" ]; then
    echo
    exit 0
  fi

  #else must be a valid system number or k for killall. Take action.
  if [ $continuous_update -eq 0 ]; then
    #run once mode
    execute_user_action
    user_action="r" #refresh and display the status to reflect the change
    execute_user_action
    echo
    exit 0
  else
    #continuous mode
    execute_user_action
  fi
  #note: continuous mode will generate the next output at beginning of the next pass thru the loop

done #done with for loop used for continuous_update mode

# =========================== END MAIN PROGRAM ================================
#EOF



