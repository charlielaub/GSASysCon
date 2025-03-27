/*                    RIIR_AP1 LADSPA plugin, version 1.0 
                       Copyright 2024 Charlie Laub, GPLv3

  RIIR_AP1 is a LADSPA plugin for implementing the reverse (backwards)
  application of a first order allpass filter characterized by its pole
  frequency (fp) . The parameter SNR influences when the impulse tail 
  is truncated. Higher values of SNR better match the full impulse tail
  of the AP filter but give rise to higher latency (delay) of the output
  signal. A conservative value for SNR is 80.

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

  CREDITS:

  The Reverse-IIR calculation method was devised by Martin Vicanek. See:
  "A New Reverse IIR Filtering Algorithm" OCT 2015 REVISED JAN 2022
*/

#include <iostream>
#include <iomanip>
#include <sstream>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#define _USE_MATH_DEFINES
#include <math.h>
#include <ladspa.h>
#include <string>
#include <vector>
#include <complex>
using namespace std;


//order of LADSPA parameters:
#define RIIRAP1_FP        0 
#define RIIRAP1_SNR       1 
#define RIIRAP1_INPUT     2 
#define RIIRAP1_OUTPUT    3 


static LADSPA_Descriptor *RIIRAP1_Descriptor = NULL;

typedef struct {
  double a;
  vector<double> past_x_inputs; //buffer to hold recent inputs (real pipeline)
  unsigned int cb_index; //circular buffer read/write index
  unsigned int cb_size; //size of circular buffer
} RPstage_data_struct;


typedef struct {
  unsigned short num_RP1stages; //number of stages used in calculation for real pole
  double RP1; // " "
  LADSPA_Data x1; //one input sample ago
  unsigned long startup_samples;
  unsigned int instance_index; //the index of the correct num_RP1stages vectors
} per_instance_data_struct;


typedef struct {
  //this structure holds pointers that are obtained from the LADSPA host
  //  and other instance-specific data 
  LADSPA_Data *fp_ptr;
  LADSPA_Data *SNR_ptr;
  LADSPA_Data *input_ptr;
  LADSPA_Data *output_ptr;
  float SR; //sample rate of the data stream
  unsigned int instance_data_index; //points to the correct instance data
} plugin_data_struct;


//dedlare global storage that will be available to all procs in this file:
//  NOTE: these data structures will be shared by ALL INSTANCES of this plugin 
//    that are created by the host! The data for eahc instance is differentiated
//    using the outer vector index 
//storage involved in calculating the real pole
  static vector< vector<RPstage_data_struct> > RP1stage; //stores data for each reverse IIR RPstage, real pole 1
//storage for instance data. The instances are differentiated using the vector index
  static vector<per_instance_data_struct> instance_data;



const LADSPA_Descriptor *ladspa_descriptor(unsigned long index) {
  switch (index) {
  case 0:
    return RIIRAP1_Descriptor;
  default:
    return NULL;
  }
}


LADSPA_Handle RIIRAP1_instantiate(const LADSPA_Descriptor *descriptor, unsigned long sample_rate) {
  //one-liner to create a pointer to a plugin_data_struct and allocate its memory 
  plugin_data_struct *plugin_data = (plugin_data_struct *)malloc(sizeof(plugin_data_struct));
  //Use the pointer to store the sample rate
  plugin_data->SR = (float)sample_rate;
  //return the pointer plugin_data to the LADSPA host 
  return (LADSPA_Handle)plugin_data; 
}


void RIIRAP1_connectPort(LADSPA_Handle instance, unsigned long port, LADSPA_Data *data) {
  plugin_data_struct *plugin_data = (plugin_data_struct *)instance;
  switch (port) {
  case RIIRAP1_FP:
    plugin_data->fp_ptr = data;
    break;
  case RIIRAP1_SNR:
    plugin_data->SNR_ptr = data;
    break;
  case RIIRAP1_INPUT:
    plugin_data->input_ptr = data;
    break;
  case RIIRAP1_OUTPUT:
    plugin_data->output_ptr = data;
    break;
  }
}



void RIIRAP1_activate(LADSPA_Handle instance) {
  plugin_data_struct *plugin_data = (plugin_data_struct *)instance;

  LADSPA_Data Fp = *(plugin_data->fp_ptr); 
  LADSPA_Data SNR = *(plugin_data->SNR_ptr);
  double RP1;
  unsigned int ii, idi;
  const double Wp = 2.0*M_PI*Fp; //for analog radian frequency
  const double K = 2.0*plugin_data->SR;

  //push back a new instance_data and store the index of it in plugin_data
  instance_data.push_back(per_instance_data_struct() );
  plugin_data->instance_data_index = idi = instance_data.size()-1;

  //initialize past samples x1, x2 to zero in instance_data:
  instance_data[idi].x1 = 0.0;

  //calculate the real pole from the Fpole specification. Adopted from :
  //https://ccrma.stanford.edu/~jos/pasp/Classic_Virtual_Analog_Phase.html
  instance_data[idi].RP1 = RP1 = (1.0 - tan( Wp/K ))/(1.0 + tan( Wp/K ));
  //Initialize storage and parameters for each pole separately
  //push back a new instance of RP1stage and RP2stage
  RP1stage.push_back( vector<RPstage_data_struct>() );
  //set the plugin_data's instance_index, and the local variable id, to RP1stage.size()-1
  instance_data[idi].instance_index = ii = RP1stage.size()-1;

  //begin RP1 initializations:
  //calculate num_RP1stages, the required numer of stages, using SNR and ABS(c).
  //  the number of required stages is rounded to the nearest integer
   //calculate real poles RP1 and RP2 from biquad coefficients:
  //proceed first with RP1: 
  instance_data[idi].num_RP1stages = trunc( 0.5 + log2( -SNR / (20.0*log10( instance_data[idi].RP1 ) ) ) );
  //resize the RP1stage[] vector
  RP1stage[ii].resize(instance_data[idi].num_RP1stages+1); //the +1 is because there is a 0th stage
  //loop over CCstage vector and peform setup tasks:
  for (unsigned int stage_index=0; stage_index<=instance_data[idi].num_RP1stages; stage_index++) {
    RP1stage[ii][stage_index].cb_size = pow(2,stage_index); //calc the circular buffer size
    // resize vector to hold cb_size values and fill with zeroes :
    RP1stage[ii][stage_index].past_x_inputs.assign( RP1stage[ii][stage_index].cb_size, 0.0 );
    // calculate a value for each stage from c:
    RP1stage[ii][stage_index].a = pow( RP1, pow( 2, stage_index ) ); //calculate c^2^N 
    RP1stage[ii][stage_index].cb_index = 0; //set an arbitrary start value for the c.b.
  } //end for-loop over RP1 stages
  //done with RP1 initializations:

  //store the number of output samples that should be set to zero at startup
  instance_data[idi].startup_samples = pow(2, instance_data[idi].num_RP1stages);
  //report the latency
  cout << "For the RIIR_AP1 instance with Fp = " << Fp << ", and SNR = " << SNR << ":" << endl;
  cout << "   " << instance_data[idi].num_RP1stages << " stages are required for the real pole." << endl;
  cout << "The latency produced by the reverse-IIR processing will be:" << endl;
  cout << "   " << instance_data[idi].startup_samples << " samples at at sample rate of " << plugin_data->SR << " Hz, or ";
  cout << fixed << setprecision(3) << 1000.0* instance_data[idi].startup_samples / plugin_data->SR << " milliseconds." << endl;    

} //end activate_RIIRAP1




void RIIRAP1_run(LADSPA_Handle instance, unsigned long sample_count) {
  plugin_data_struct *plugin_data = (plugin_data_struct *)instance;
  const LADSPA_Data *input = plugin_data->input_ptr;
  LADSPA_Data *output = plugin_data->output_ptr; 

  double x, y; 
  unsigned int ii, idi;
   
  //get indeces for this particular instance of the plugin:
  idi = plugin_data->instance_data_index;
  ii = instance_data[idi].instance_index;   
  //begin RIIR calculation of poles (denominator of TF)
  for (unsigned long pos = 0; pos < sample_count; pos++) {
    x = input[pos];
    //RP1:      
    for (unsigned int stage_index=0; stage_index<=instance_data[idi].num_RP1stages; stage_index++) {
      y = RP1stage[ii][stage_index].a * x + RP1stage[ii][stage_index].past_x_inputs[RP1stage[ii][stage_index].cb_index]; 
      RP1stage[ii][stage_index].past_x_inputs[RP1stage[ii][stage_index].cb_index] = x;
      RP1stage[ii][stage_index].cb_index = ( RP1stage[ii][stage_index].cb_index + 1 ) % RP1stage[ii][stage_index].cb_size;
      x = y;
    }
    //done with RP1. 
    output[pos] = instance_data[idi].RP1 * instance_data[idi].x1 - x;
    //update value for x1
    instance_data[idi].x1 = x;
  } //end for-loop over samples
  //test if we are still in the startup period...
  if ( instance_data[idi].startup_samples > 0 ) {
    for (unsigned long pos = 0; pos < sample_count; pos++) {
      //the output should be discarded until startup_samples samples have passed through
      output[pos] = 0.0;
      instance_data[idi].startup_samples -= 1;
      if ( instance_data[idi].startup_samples == 0 ) break;
    }     
  } //end check for startup samples
} //end run_RIIRAP1.



void RIIRAP1_cleanup(LADSPA_Handle instance) {
  //free storage used by global data containers
  RP1stage.clear();
  instance_data.clear();
  //free memory obtained via malloc for the LADSPA plugin interface
  free(instance); 
}



static class Initialiser {
public:
  Initialiser() {
    char **port_names;
    LADSPA_PortDescriptor *port_descriptors;
    LADSPA_PortRangeHint *port_range_hints;
    RIIRAP1_Descriptor = (LADSPA_Descriptor *)malloc(sizeof(LADSPA_Descriptor));
    const unsigned long num_ports = 4;
    string text;

    if (RIIRAP1_Descriptor) {
      //plugin descriptor info
      RIIRAP1_Descriptor->UniqueID = 5226;
      RIIRAP1_Descriptor->Label = "RIIR_AP1";
      RIIRAP1_Descriptor->Properties = LADSPA_PROPERTY_HARD_RT_CAPABLE;
      RIIRAP1_Descriptor->Name = "Reverse IIR 1st order AllPass Filter";
      RIIRAP1_Descriptor->Maker = "Charlie Laub, 2024";
      RIIRAP1_Descriptor->Copyright = "GPL";
      RIIRAP1_Descriptor->PortCount = num_ports;

      //create storage for port_descriptors, port_range_hints, and port_names        
      port_descriptors = (LADSPA_PortDescriptor *)calloc(num_ports,sizeof(LADSPA_PortDescriptor));
      RIIRAP1_Descriptor->PortDescriptors = (const LADSPA_PortDescriptor *)port_descriptors;
      port_range_hints = (LADSPA_PortRangeHint *)calloc(num_ports,sizeof(LADSPA_PortRangeHint));
      RIIRAP1_Descriptor->PortRangeHints = (const LADSPA_PortRangeHint *)port_range_hints;
      port_names = (char **)calloc(num_ports, sizeof(char*));
      RIIRAP1_Descriptor->PortNames = (const char **)port_names;
      //done creating storage. now set the descriptor, range_hints, and name for each port:

      //port = pole frequency      
      port_descriptors[RIIRAP1_FP] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "fp";
      port_names[RIIRAP1_FP] = strdup(text.c_str());
      port_range_hints[RIIRAP1_FP].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_DEFAULT_440;
      port_range_hints[RIIRAP1_FP].LowerBound = 1.0;
      port_range_hints[RIIRAP1_FP].UpperBound = 100000.0;

      //port = Signal to Noise Ratio      
      port_descriptors[RIIRAP1_SNR] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "snr";
      port_names[RIIRAP1_SNR] = strdup(text.c_str());
      port_range_hints[RIIRAP1_SNR].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_DEFAULT_MIDDLE;
      port_range_hints[RIIRAP1_SNR].LowerBound = 10.0;
      port_range_hints[RIIRAP1_SNR].UpperBound = 150.0;

      //port = audio data INPUT   
      port_descriptors[RIIRAP1_INPUT] = LADSPA_PORT_INPUT | LADSPA_PORT_AUDIO;
      text = "Input";
      port_names[RIIRAP1_INPUT] = strdup(text.c_str());

      //port = audio data OUTPUT
      port_descriptors[RIIRAP1_OUTPUT] = LADSPA_PORT_OUTPUT | LADSPA_PORT_AUDIO;
      text = "Output";
      port_names[RIIRAP1_OUTPUT] = strdup(text.c_str());

      RIIRAP1_Descriptor->activate = RIIRAP1_activate;
      RIIRAP1_Descriptor->cleanup = RIIRAP1_cleanup;
      RIIRAP1_Descriptor->connect_port = RIIRAP1_connectPort;
      RIIRAP1_Descriptor->deactivate = NULL;
      RIIRAP1_Descriptor->instantiate = RIIRAP1_instantiate;
      RIIRAP1_Descriptor->run = RIIRAP1_run;
      RIIRAP1_Descriptor->run_adding = NULL;
      RIIRAP1_Descriptor->set_run_adding_gain = NULL;
    }
  }
  ~Initialiser() {
    if (RIIRAP1_Descriptor) {
      free((LADSPA_PortDescriptor *)RIIRAP1_Descriptor->PortDescriptors);
      free((char **)RIIRAP1_Descriptor->PortNames);
      free((LADSPA_PortRangeHint *)RIIRAP1_Descriptor->PortRangeHints);
      free(RIIRAP1_Descriptor);
    }
  }                                      
} g_theInitialiser;


  
