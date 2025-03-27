/* Copyright 2016 Charlie Laub under GPLv3 ====================================

  For usage notes, please consult the documentation included with the plugin.

  OnOffDelay LADSPA plugin Programmer Notes:

  Overview: 
  The purpose of this plugin is to control one or more GPIO outputs
  with on-delay and off-delay behavior under a linux OS. When entering the
  'on' state, the plugin sets one or more GPIO pins to 'high'. When entering
  the 'off' state, these same GPIO pins are set to 'low'. The GPIO pins can
  be used to trigger external equipment like relays, put amps or power supplies
  into standby, etc. The plugin monitors each of two (e.g. stereo) inputs. 
  
  Audio Trigger Threshold: 
  The plugin's two audio inputs are both analyzed and used to trigger the
  on-delay and off-delay behavior of the output. The peak level of the input
  (e.g. audio signal) is monitored and compared to a reference level called the
  'Threshold', specified in dB below maximum. When the peak level within a
  frame exceeds the threshold, a timer is started. As long as the peak signal
  level continues to exceed the Threshold the timer will count up. When the
  timer exceeds the value for the plugin's DelayON parameter the output is set
  to 'on'. Similarly, when the peak level within a frame does not exceed the
  threshold, a timer is again started. As long as the peak level continues to
  be below the Threshold for each frame, the timer will count up. When the
  timer exceeds the value for the plugin's DelayOFF parameter the output is
  set to 'off'.
  
  Options for Audio Signal Behavior at Turn-On:
  The plugin has the ability to first mute and then fade-up the audio level
  when 'turning on' the output after the DelayON period has completed. The
  duration of the muting and fade-in are both specified through a real-
  valued parameter in the format of M.F, where M is the number of seconds the
  audio signal should be muted and F is the number of seconds over which the
  fade-in should take place. M.F is a real number with digits to the left and
  right of of the decimal point. For example, 3 seconds of muting followed
  by two seconds of fade-in would be provided as the parameter '3.2'. The
  signal fades in from the level set by the Threshold parameter to the full 
  level over the number of seconds indicated. M and F are given in increments
  of whole seconds due to the integral nature of the M.F representation. An
  unlimited number of seconds of muting and up to 9 seconds of audio fade-in 
  can be specified in this way. If no muting or fade-in at turn-on is desired,
  simply supply the value 0.0 or omit the parameter entirely.
  
  Controlling Multiple GPIOs simultaneously from the same plugin instance:
  From one to seven GPIOs can simultaneously be turned on (HIGH logic state) or 
  turned off (LOW logic state) from the same plugin. The user provides the
  plugin with a number which is a concatenated list of one or more indexes. The
  default index is 0. If no index is supplied, the GPIO for index 0 is used.
  If index 0 is used in a list, it must come after at least one non-zero index 
  (e.g. zero cannot be the first digit). For example, if the user wishes to
  toggle the GPIOs corresponding to indexes of 0,2,3 and 7 then 7320 would be
  provided as input to the plugin. All are turned on and off simultaneously. 

  Specifying GPIO pins via the 'index_to_GPIO_map' array: 
  The user tells the plugin which GPIO(s) should be controlled using an index
  (0..9). Internally, the 'index_to_GPIO_map' array is used to translate the
  index to the actual GPIO number on the computing hardware. The plugin code
  has been provided with a set of otherwise unused GPIOs for the Raspberry Pi
  models 2 and 3. The 'map can be changed to control other GPIOs and for other
  computing hardware by editing the entries in the 'GPIO#' column (see below). 

  BEGIN 'index_to_GPIO_map' array DEFINITION ------------------------------- */

  //index         GPIO#   physical location on the R-Pi J8 header 
#define GPIO_0      4;              //pin #7
#define GPIO_1     17;              //pin #11
#define GPIO_2     27;              //pin #13
#define GPIO_3     22;              //pin #15
#define GPIO_4     12;              //pin #32
#define GPIO_5     16;              //pin #36
#define GPIO_6     20;              //pin #38
#define GPIO_7     21;              //pin #40
#define GPIO_8     19;              //pin #35
#define GPIO_9     26;              //pin #37

/* END 'index_to_GPIO_map' array DEFINITION -----------------------------------
  
  License Info:
  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.

============================================================================ */

#include <ladspa.h>
#include <string>
#include <sstream>
#include <cstring>
#include <iostream>
#include <iomanip>
#include <cmath>
#include <algorithm>
using namespace std;

//DEFAULT, MINIMUM, AND MAXIMUM PARAMETER VALUES:
//  NOTES: default values should be greater than or equal to min values.
//  Minimum values must be greater than zero for all parameters.
//  Delay times are in seconds. Frequency in Hertz. 
//  The Threshold must be given in units of dB below the maximum level (e.g. below 0dB)
//  Threshold_max has a ceiling that is approximately equal to the bit depth minus 6dB:
//    for 16bit-audio the max value is ~90 dB; 24bit = ~138 dB; 32bit = ~186 dB
static const float DelayOFF_min = 0.0; 
static const float DelayON_min = 0.0;
static const float Threshold_min = 20.0;
static const float Threshold_max = 186.0;
//defaults used when no parameter or zero is supplied.
static const float Default_Threshold = 60.0;
static const float Default_DelayOFF = 120.0;
static const float Default_DelayON = 0.0;
static const bool PassThru = false; 


//---- GPIO MANIPULATION FUNCTIONS --------------------------------------------
//The following functions employ the linux kernel's GPIO Sysfs Interface

#define GPIO_ON 1
#define GPIO_OFF 0
#define OS_sleep_between_commands 0.1

void configure_GPIO_for_output (unsigned int pin_index, int map[] ) {
  //first check to make sure that a GPIO has been associated with this index
  if (map[pin_index] == -1) {
    cout << "no valid GPIO has been associated with index " << pin_index << endl;
    cout << "please correct this error and try again." << endl;
    return;
  }
  std::stringstream commandString;
  //build the command string; 
  commandString << "echo " << map[pin_index] << " > /sys/class/gpio/export";
  //run the command on the system
  int retval = system( strdup( (commandString.str()).c_str() ) ); //run command string in shell
  if (retval != 0) cout << "OnOffDelay ERROR: could not run command in shell!" << endl;
  //clear contents of command string by setting it equal to empty string - must do this after
  //  each command if multiple commands are run within the same function call
  commandString.str("");
  commandString << "sleep " << OS_sleep_between_commands; //needed to allow command to complete in OS
  retval = system( strdup( (commandString.str()).c_str() ) ); //run command string in shell
  if (retval != 0) cerr << "OnOffDelay: ERROR encountered when attempting to run command in shell!" << endl;
  commandString.str("");  
  commandString << "echo \"out\" > /sys/class/gpio/gpio" << map[pin_index] <<"/direction";
  //run the command on the system
  retval = system( strdup( (commandString.str()).c_str() ) ); //run command string in shell
  if (retval != 0) cerr << "OnOffDelay: ERROR encountered when attempting to run command in shell!" << endl;
} // end configure_GPIO_for_output


void set_GPIO_state (unsigned int pin_index, bool pin_state, int map[]) {
  //first check to make sure that a GPIO has been associated with this index
  if (map[pin_index] == -1) return;
  std::stringstream commandString;
  //build the command string; syntax: 
  commandString << "echo " << (unsigned int)pin_state << " > /sys/class/gpio/gpio" << map[pin_index] <<"/value";
  //run the command on the system
  int retval = system( (commandString.str()).c_str() ); //run command string in shell
  if (retval != 0) cerr << "OnOffDelay: ERROR encountered when attempting to run command in shell!" << endl;
  //clear contents of command string by setting it equal to empty string - must do this after
  //  each command if multiple commands are run within the same function call
  commandString.str(""); 
} //end set_GPIO_state


void GPIO_teardown (unsigned int array_of_GPIOs_in_use[], unsigned int num_GPIOs, int map[]) {
  //this function is called when exiting the plugin. Note that it may also be called once when
  //  the plugin is initializing (this behavior may be LADSPA host dependent)
  std::stringstream commandString;
  int GPIO;
  for (unsigned int j=0; j < num_GPIOs; j++) {
    GPIO = map[array_of_GPIOs_in_use[j]];
    //check to make sure that a GPIO has been associated with this index
    if (GPIO != -1) {
      //build the command string; 
      commandString << "echo " << GPIO << " > /sys/class/gpio/unexport";
      //run the command on the system
      system( strdup( (commandString.str()).c_str() ) ); //run command string in shell
      //clear contents of command string by setting it equal to empty string - must do this after
      //  each command if multiple commands are run within the same function call
      commandString.str("");  
      commandString << "sleep " << OS_sleep_between_commands; //needed to allow command to complete in OS
      system( strdup( (commandString.str()).c_str() ) ); //run command string in shell
    }
  }
}

//---- END GPIO MANIPULATION FUNCTIONS ----------------------------------------





typedef struct {
  float sample_rate;
  float Threshold;
  float DelayOFF;
  float DelayON;
  float ConcatenatedIndexList;
  float TurnOnBehaviorUserValue;
  bool PassThru;
  unsigned long OnOffDelay_counter;
  unsigned int MuteAndFade_counter;
  unsigned int TurnOnMuteDuration;
  unsigned int TurnOnFadeInDuration;
  unsigned int BuffersOfMuting;
  unsigned int BuffersOfFadeIn;
  float FadeUpFactor;
  float FadeMultiplier;
  bool OutputEnabled;
  bool SetPinsHighActionNeeded;
  unsigned int PinCount;
  unsigned int PinIndexList[7];
  int index_to_GPIO_map[10];
} ParameterStorage;


typedef struct {
  ParameterStorage * Parameters;
  LADSPA_Data *ch1_input;
  LADSPA_Data *ch1_output;
} PluginDataContainer;


static LADSPA_Descriptor *PluginDescriptor = NULL;

const LADSPA_Descriptor *ladspa_descriptor(unsigned long index) {
  switch (index) {
  case 0:
    return PluginDescriptor;
  default:
    return NULL;
  }
}


LADSPA_Handle Instantiate_Plugin(const LADSPA_Descriptor *descriptor, unsigned long sample_rate) {
  PluginDataContainer *pluginData = (PluginDataContainer *)malloc(sizeof(PluginDataContainer));
  ParameterStorage *PS = NULL;
  PS = (ParameterStorage *)malloc(sizeof(ParameterStorage));
  PS->sample_rate = sample_rate;
  pluginData->Parameters = PS;
  return (LADSPA_Handle)pluginData;
}


void Connect_Plugin_Ports(LADSPA_Handle instance, unsigned long port, LADSPA_Data *data) {
  PluginDataContainer *pluginData = (PluginDataContainer *)instance;
  ParameterStorage *PS = pluginData->Parameters;
  int user_value;
  switch (port) {
  case 0: //parameter = Threshold
    PS->Threshold = *(data);
    break; 
  case 1: //parameter = DelayOFF
    PS->DelayOFF = *(data);
    break; 
  case 2: //parameter = DelayON
    PS->DelayON = *(data);
    break; 
  case 3: //parameter = ConcatenatedIndexList
    PS->ConcatenatedIndexList = *(data);
    break; 
  case 4: //parameter = Delay.Fade-in
    PS->TurnOnBehaviorUserValue = *(data);
    break; 
  case 5: //parameter = PassThru flag (see programmer's notes)
    user_value = int( *(data) );
    if (user_value == 0) 
      PS->PassThru = false;
    else
      PS->PassThru = true;
    break;
  case 6: //port = first audio input
    pluginData->ch1_input = data;
    break;
  case 7: //port = first audio output
    pluginData->ch1_output = data;
    break;
  }
}
      

void Activate_Plugin(LADSPA_Handle instance) {
  PluginDataContainer *pluginData = (PluginDataContainer *)instance;
  ParameterStorage *PS = pluginData->Parameters;
  
  //initialize values and bounds check parameters...

  //NOTE: when a parameter is not supplied by the user to the host, the host 
  //  will pass a value of zero for that parameter to the plugin. Below we 
  //  substitute a default value if the parameter value is zero.

  //DelayOFF: delay time in seconds to wait before disabling output while there 
  //  is no input signal
  if (PS->DelayOFF == 0.0) 
    PS->DelayOFF = Default_DelayOFF;
  else 
    if (PS->DelayOFF < DelayOFF_min) PS->DelayOFF = DelayOFF_min;  

  //DelayON: delay time in seconds to wait before enabling output when there is 
  //  an input signal present
  if (PS->DelayON == 0.0) 
    PS->DelayON = Default_DelayON;
  else 
    if (PS->DelayON < DelayON_min) PS->DelayON = DelayON_min;  
  
  //Threshold: level in dB below 0dB used to trigger on/off behavior
  if (PS->Threshold == 0.0) 
    PS->Threshold = Default_Threshold;
  else
    if (PS->Threshold < Threshold_min) PS->Threshold = Threshold_min;
  else
    if (PS->Threshold > Threshold_max) PS->Threshold = Threshold_max;
  //convert Threshold in dB to signal level
  PS->Threshold = pow(10.0,-(PS->Threshold)/20.0);

  //populate the 'index_to_GPIO_map' array
#ifdef GPIO_0 
  PS->index_to_GPIO_map[0] = GPIO_0;
#else
  PS->index_to_GPIO_map[0] = -1;
#endif
#ifdef GPIO_1
  PS->index_to_GPIO_map[1] = GPIO_1;
#else
  PS->index_to_GPIO_map[1] = -1;
#endif
#ifdef GPIO_2 
  PS->index_to_GPIO_map[2] = GPIO_2;
#else
  PS->index_to_GPIO_map[2] = -1;
#endif
#ifdef GPIO_3 
  PS->index_to_GPIO_map[3] = GPIO_3;
#else
  PS->index_to_GPIO_map[3] = -1;
#endif
#ifdef GPIO_4 
  PS->index_to_GPIO_map[4] = GPIO_4;
#else
  PS->index_to_GPIO_map[4] = -1;
#endif
#ifdef GPIO_5 
  PS->index_to_GPIO_map[5] = GPIO_5;
#else
  PS->index_to_GPIO_map[5] = -1;
#endif
#ifdef GPIO_6 
  PS->index_to_GPIO_map[6] = GPIO_6;
#else
  PS->index_to_GPIO_map[6] = -1;
#endif
#ifdef GPIO_7 
  PS->index_to_GPIO_map[7] = GPIO_7;
#else
  PS->index_to_GPIO_map[7] = -1;
#endif
#ifdef GPIO_8 
  PS->index_to_GPIO_map[8] = GPIO_8;
#else
  PS->index_to_GPIO_map[8] = -1;
#endif
#ifdef GPIO_9 
  PS->index_to_GPIO_map[9] = GPIO_9;
#else
  PS->index_to_GPIO_map[9] = -1;
#endif

  //split the ConcatenatedIndexList into the PinIndexList array 
  if (PS->ConcatenatedIndexList <= 0.0) { //error control...
    PS->PinCount = 1;
    PS->PinIndexList[0] = 0;
  } else {
    //create the pin list from the input and eliminate pins > 7 to
    //  only allow up to 7 entries in the list
    unsigned int one_digit, value;
    value = (unsigned int)( PS->ConcatenatedIndexList );
    PS->PinCount = 0; 
    do {
      one_digit = value%10;
      if ( one_digit <= 7 ) {
        PS->PinIndexList[PS->PinCount] = one_digit;
        PS->PinCount += 1;
      }
    } while (( value/= 10 ) && ( PS->PinCount < 7 ));
  }

  //set up the pins in the PinIndexList for output
  for (unsigned int j=0; j < PS->PinCount; j++) configure_GPIO_for_output(PS->PinIndexList[j], PS->index_to_GPIO_map);

  //Extract the duration of the Delay and Fade-in from the passed value
  //The number of seconds of delay are taken as the digits left of the decimal point
  //The number of seconds for the fade in are taken as the first digit right of the decimal point
  //first, check for valid range of passed variable:
  if (PS->TurnOnBehaviorUserValue < 0.0) PS->TurnOnBehaviorUserValue = 0.0;
  //set the delay duration equal to the digits to the left of the decimal point
  PS->TurnOnMuteDuration = (unsigned int)(PS->TurnOnBehaviorUserValue);
  //set the fade-in duration equal to the first decimal digit
  float decimal_places = 10.0*(PS->TurnOnBehaviorUserValue - PS->TurnOnMuteDuration);
  PS->TurnOnFadeInDuration = (unsigned int)( decimal_places+0.5 ); //need to round when converting to uint

  //initialize remaining values
  PS->OutputEnabled = false;
  PS->SetPinsHighActionNeeded = false;
  PS->OnOffDelay_counter = 0;
  PS->MuteAndFade_counter = 0;
  
} //end Activate_Plugin


void Run_Plugin(LADSPA_Handle instance, unsigned long sample_count) {
  PluginDataContainer *pluginData = (PluginDataContainer *)instance;
  const LADSPA_Data *ch1_input = pluginData->ch1_input;
  LADSPA_Data *ch1_output = pluginData->ch1_output;
  ParameterStorage *PS = pluginData->Parameters;

  LADSPA_Data signal_peak = 0.0;
  bool have_input_signal;
  unsigned long pos;

  //if SetPinsHighActionNeeded has been set to true in a previous call, set the output pin(s) HIGH and
  //  reset the SetPinsHighActionNeeded flag
  if (PS->SetPinsHighActionNeeded) {
    //set pins in PinIndexList to 'on' state
    for (unsigned int j=0; j < PS->PinCount; j++) set_GPIO_state(PS->PinIndexList[j], GPIO_ON, PS->index_to_GPIO_map);
    //reset flag
    PS->SetPinsHighActionNeeded = false;
  }

  //search over the input for the highest level in this frame  
  for (pos = 0; pos < sample_count; pos++) signal_peak = std::max( std::abs( ch1_input[pos] ), signal_peak);

  //check to see if any peaks > Threshold were detected during the frame
  if (signal_peak > PS->Threshold)
    have_input_signal = true;
  else
    have_input_signal = false;

  if ( (PS->OutputEnabled == false) && (have_input_signal == false) ) 
    //reset the PS->OnOffDelay_counter if not_enabled & no_input
    PS->OnOffDelay_counter = 0;
  else if ( (PS->OutputEnabled == false) && (have_input_signal == true) ) {
    //if output is disabled but we have input signal, add to the sample counter
    //  if OnOffDelay_counter exceeds DelayON, turn on the output and reset the 
    //  OnOffDelay_counter value to zero
    PS->OnOffDelay_counter += sample_count;
    if ( (PS->OnOffDelay_counter / PS->sample_rate) > PS->DelayON ) {
      PS->OutputEnabled = true;
      PS->OnOffDelay_counter = 0;
      //set the PS->SetPinsHighActionNeeded flag to set pins to 'on'  
      PS->SetPinsHighActionNeeded = true;
      //determine how many buffers span the delay period (signal is muted during this time)
      PS->BuffersOfMuting = (unsigned int)( 0.5+(PS->sample_rate/sample_count)*PS->TurnOnMuteDuration );
      PS->BuffersOfFadeIn = (unsigned int)( 0.5+(PS->sample_rate/sample_count)*PS->TurnOnFadeInDuration );
      //calculate the FadeUpFactor
      PS->FadeUpFactor = pow( (double)(1.0/PS->Threshold), (double)(1.0/PS->BuffersOfFadeIn) );
      //set the MuteAndFade_counter to 1 to enable the DelayAndFadeIn output mode 
      PS->MuteAndFade_counter = 1;
      //set the intial value of the FadeMultiplier to the value of the Threshold parameter
      PS->FadeMultiplier = PS->Threshold;
    }
  } 

  if ( (PS->OutputEnabled == true) && (have_input_signal == true) ) 
    //reset the PS->OnOffDelay_counter if enabled & have_input
    PS->OnOffDelay_counter = 0;
  else if ( (PS->OutputEnabled == true) && (have_input_signal == false) ) {
    //if output is enabled but we have no input signal, add to the sample counter
    //  if OnOffDelay_counter exceeds DelayOFF, turn off the output and reset the 
    //  OnOffDelay_counter value to zero
    PS->OnOffDelay_counter += sample_count;
    if ((PS->OnOffDelay_counter / PS->sample_rate) > PS->DelayOFF ) {
      PS->OutputEnabled = false;
      PS->OnOffDelay_counter = 0;
      //set pins in PinIndexList to 'off' state
      for (unsigned int j=0; j < PS->PinCount; j++) set_GPIO_state(PS->PinIndexList[j], GPIO_OFF, PS->index_to_GPIO_map);
    }
  }
  
  //if output is disabled...
  if (PS->OutputEnabled == false) {
    //test if PassThru is true...
    if ( PS->PassThru )
      //continue to pass the input signal to the output
      for (pos = 0; pos < sample_count; pos++) {
        ch1_output[pos] = ch1_input[pos];
      }
    else
      //set output values to 0.0
      for (pos = 0; pos < sample_count; pos++) {
        ch1_output[pos] = 0.0;
      }
    return;
  }  
  //if we get here, output is enabled. Determine output mode and set output values
  if (PS->MuteAndFade_counter == 0) {
  //when MuteAndFade_counter == 0 normal output mode is ocurring, so pass input to output and return
    for (pos = 0; pos < sample_count; pos++) {
      ch1_output[pos] = ch1_input[pos];
    }
    return;
  }
  //if we get here, operation is in DelayAndFadeIn mode 
  if (PS->MuteAndFade_counter < PS->BuffersOfMuting) {
    //delay (mute) the output 
    for (pos = 0; pos < sample_count; pos++) {
      ch1_output[pos] = 0.0;
    }
  }
  else
  {
    //apply the mutliplier to the output to fade up the level
    for (pos = 0; pos < sample_count; pos++) {
      ch1_output[pos] = ch1_input[pos]*PS->FadeMultiplier;
    }
    //increase the multiplier by the FadeUpFactor
    PS->FadeMultiplier *= PS->FadeUpFactor;
  }
  //increment the counter
  PS->MuteAndFade_counter += 1;
  //check if the delay and fade has completed and, if so, reset the counter to enter normal output mode
  if ( PS->MuteAndFade_counter > (PS->BuffersOfMuting + PS->BuffersOfFadeIn) ) PS->MuteAndFade_counter = 0;

} //end Run_Plugin


void Free_Allocated_Storage(LADSPA_Handle instance) {
  PluginDataContainer *pluginData = (PluginDataContainer *)instance;
  ParameterStorage *PS = pluginData->Parameters;
  GPIO_teardown (PS->PinIndexList, PS->PinCount, PS->index_to_GPIO_map);
  free(pluginData->Parameters);
  free(instance);
}


static class Initialiser {
//handles global initialization usually done in init() and fini()
public:
  Initialiser() {
    char **port_names;
    LADSPA_PortDescriptor *port_descriptors;
    LADSPA_PortRangeHint *port_range_hints;
    PluginDescriptor = (LADSPA_Descriptor *)malloc(sizeof(LADSPA_Descriptor));
    std::string text;
    const unsigned long num_ports = 8;
  
    if (PluginDescriptor) {
      //plugin descriptor info
      PluginDescriptor->UniqueID = 5223;
      PluginDescriptor->Label = "OnOffDelay";
      PluginDescriptor->Properties = LADSPA_PROPERTY_HARD_RT_CAPABLE;
      PluginDescriptor->Name = "OnOffDelay v2.0: Toggle GPIO pins with on- and off-delay behavior";
      PluginDescriptor->Maker = "Charlie Laub, 2018";
      PluginDescriptor->Copyright = "GPLv3";
      PluginDescriptor->PortCount = num_ports;
  
      //create storage for port_descriptors, port_range_hints, and port_names        
      port_descriptors = (LADSPA_PortDescriptor *)calloc(num_ports,sizeof(LADSPA_PortDescriptor));
      PluginDescriptor->PortDescriptors = (const LADSPA_PortDescriptor *)port_descriptors;
      port_range_hints = (LADSPA_PortRangeHint *)calloc(num_ports,sizeof(LADSPA_PortRangeHint));
      PluginDescriptor->PortRangeHints = (const LADSPA_PortRangeHint *)port_range_hints;
      port_names = (char **)calloc(num_ports, sizeof(char*));
      PluginDescriptor->PortNames = (const char **)port_names;
      //done creating storage. now set the descriptor, range_hints, and name for each port:
 
      //ports for user parameters are numbered 0-5     
      port_descriptors[0] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "threshold"; //Signal Detection Threshold in dB below 0dB
      port_names[0] = strdup(text.c_str());
      port_range_hints[0].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE;
      port_range_hints[0].LowerBound = 100;
      port_range_hints[0].UpperBound = 20;

      port_descriptors[1] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "off_delay"; //OFF Delay in sec
      port_names[1] = strdup(text.c_str());
      port_range_hints[1].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW;
      port_range_hints[1].LowerBound = DelayOFF_min;

      port_descriptors[2] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "on_delay"; //ON Delay in sec
      port_names[2] = strdup(text.c_str());
      port_range_hints[2].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW;
      port_range_hints[2].LowerBound = DelayON_min;

      port_descriptors[3] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "pins"; //Concatenated List of Pins to Toggle
      port_names[3] = strdup(text.c_str());
      port_range_hints[3].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE;
      port_range_hints[3].LowerBound = 0;
      port_range_hints[3].UpperBound = 76543210.0;
  
      port_descriptors[4] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "delayfade"; //Delay.Fade-in: Mute-Delay and Fade-in times in seconds
      port_names[4] = strdup(text.c_str());
      port_range_hints[4].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE;
      port_range_hints[4].LowerBound = 0;
      port_range_hints[4].UpperBound = 99.9;
  
      port_descriptors[5] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "passthru";
      port_names[5] = strdup(text.c_str());
      port_range_hints[5].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE;
      port_range_hints[5].LowerBound = 0;
      port_range_hints[5].UpperBound = 1.0;
  
      //port = audio input 1    
      port_descriptors[6] = LADSPA_PORT_INPUT | LADSPA_PORT_AUDIO;
      text = "input_1";
      port_names[6] = strdup(text.c_str());
      port_range_hints[6].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE;
      port_range_hints[6].LowerBound = -1.0;
      port_range_hints[6].UpperBound = +1.0;
  
      //port = audio output 1
      port_descriptors[7] = LADSPA_PORT_OUTPUT | LADSPA_PORT_AUDIO;
      text = "output_1";
      port_names[7] = strdup(text.c_str());
      port_range_hints[7].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE;
      port_range_hints[7].LowerBound = -1.0;
      port_range_hints[7].UpperBound = +1.0;
  
      //specify the names of functions that will be called by LADSPA  
      PluginDescriptor->activate = Activate_Plugin;
      PluginDescriptor->cleanup = Free_Allocated_Storage;
      PluginDescriptor->connect_port = Connect_Plugin_Ports;
      PluginDescriptor->deactivate = NULL;
      PluginDescriptor->instantiate = Instantiate_Plugin;
      PluginDescriptor->run = Run_Plugin;
      PluginDescriptor->run_adding = NULL;
      PluginDescriptor->set_run_adding_gain = NULL;
    }
  }
  ~Initialiser() {
    if (PluginDescriptor) {
      free((LADSPA_PortDescriptor *)PluginDescriptor->PortDescriptors);
      free((char **)PluginDescriptor->PortNames);
      free((LADSPA_PortRangeHint *)PluginDescriptor->PortRangeHints);
      free(PluginDescriptor);
    }
  }
} g_theInitialiser;                                      
  

    
    
