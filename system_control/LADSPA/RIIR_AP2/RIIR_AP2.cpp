/*                    RIIR_AP2 LADSPA plugin, version 1.0 
                       Copyright 2024 Charlie Laub, GPLv3

  RIIR_AP2 is a LADSPA plugin for implementing the reverse (backwards)
  application of a second order allpass filter characterized by its pole
  frequency (fp) and pole Q (qp). The parameter SNR influences when the 
  impulse tail is truncated. Higher values of SNR better match the full
  impulse tail of the AP filter but give rise to higher latency (delay)
  of the output signal. A conservative value for SNR is 80.

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
#define RIIRAP2_FP        0 
#define RIIRAP2_QP        1 
#define RIIRAP2_SNR       2 
#define RIIRAP2_INPUT     3 
#define RIIRAP2_OUTPUT    4 


static LADSPA_Descriptor *RIIRAP2_Descriptor = NULL;

typedef struct {
  double a;
  double b;
  vector<double> past_x_inputs; //buffer to hold recent inputs (real pipeline)
  vector<double> past_y_inputs; //buffer to hold recent inputs (imag pipeline)
  unsigned int cb_index; //circular buffer read/write index
  unsigned int cb_size; //size of circular buffer
} CCstage_data_struct;


typedef struct {
  double a;
  vector<double> past_x_inputs; //buffer to hold recent inputs (real pipeline)
  unsigned int cb_index; //circular buffer read/write index
  unsigned int cb_size; //size of circular buffer
} RPstage_data_struct;


typedef struct {
  unsigned short num_CCstages; //number of complex conjugate stages used in calculations
  unsigned short num_RP1stages; //number of stages used in calculation for real pole 1
  unsigned short num_RP2stages; //number of stages used in calculation for real pole 2
  double a_over_b; //value used in last CCstage calculation
  LADSPA_Data b0; //forward IIR 2nd order allpass TF coefficients:
  LADSPA_Data b1; // " "
  LADSPA_Data b2; // " "
  LADSPA_Data x1; //one input sample ago
  LADSPA_Data x2; //two input samples ago
  unsigned long startup_samples;
  unsigned int instance_index; //the index of the correct num_CCstages or num_RP1stages and num_RP2stages vectors
} per_instance_data_struct;


typedef struct {
  //this structure holds pointers that are obtained from the LADSPA host
  //  and other instance-specific data 
  LADSPA_Data *fp_ptr;
  LADSPA_Data *qp_ptr;
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
//storage involved in calculating complex poles, when Q>0.5
  static vector< vector<CCstage_data_struct> > CCstage; //stores data for each reverse IIR CCstage
//storage involved in calculating real poles, when Q<=0.5
  static vector< vector<RPstage_data_struct> > RP1stage; //stores data for each reverse IIR RPstage, real pole 1
  static vector< vector<RPstage_data_struct> > RP2stage; //stores data for each reverse IIR RPstage, real pole 2
//storage for instance data. The instances are differentiated using the vector index
  static vector<per_instance_data_struct> instance_data;



const LADSPA_Descriptor *ladspa_descriptor(unsigned long index) {
  switch (index) {
  case 0:
    return RIIRAP2_Descriptor;
  default:
    return NULL;
  }
}


LADSPA_Handle RIIRAP2_instantiate(const LADSPA_Descriptor *descriptor, unsigned long sample_rate) {
  //one-liner to create a pointer to a plugin_data_struct and allocate its memory 
  plugin_data_struct *plugin_data = (plugin_data_struct *)malloc(sizeof(plugin_data_struct));
  //Use the pointer to store the sample rate
  plugin_data->SR = (float)sample_rate;
  //return the pointer plugin_data to the LADSPA host 
  return (LADSPA_Handle)plugin_data; 
}


void RIIRAP2_connectPort(LADSPA_Handle instance, unsigned long port, LADSPA_Data *data) {
  plugin_data_struct *plugin_data = (plugin_data_struct *)instance;
  switch (port) {
  case RIIRAP2_FP:
    plugin_data->fp_ptr = data;
    break;
  case RIIRAP2_QP:
    plugin_data->qp_ptr = data;
    break;
  case RIIRAP2_SNR:
    plugin_data->SNR_ptr = data;
    break;
  case RIIRAP2_INPUT:
    plugin_data->input_ptr = data;
    break;
  case RIIRAP2_OUTPUT:
    plugin_data->output_ptr = data;
    break;
  }
}



void RIIRAP2_activate(LADSPA_Handle instance) {
  plugin_data_struct *plugin_data = (plugin_data_struct *)instance;
  complex<double> complex_pole;
  complex<double> complex_temp;
  double real_part, imaginary_part, RP1, RP2;

  LADSPA_Data Fp = *(plugin_data->fp_ptr); 
  LADSPA_Data Qp = *(plugin_data->qp_ptr);
  LADSPA_Data SNR = *(plugin_data->SNR_ptr);
  unsigned int ii, idi;

  //TF coefficient calcs adapted from ACDf LADSPA plugin code:
  double Aa0, Aa1, Aa2, Ab0, Ab1, Ab2; //analog TF coefficients
  double Da0, Da1, Da2, Db0, Db1, Db2; //IIR digital TF coefficients
  double Wp, Wp2; //for analog radian frequency
  const double K = 2.0*plugin_data->SR;
  const double K2 = K*K;
  //calculate analog domain radian frequencies  
  Wp = 2.0*M_PI*Fp;
  //apply pre-warping 
  Wp = K*tan( Wp/K );
  //calculate square of pre-warped radian frequencies
  Wp2 = Wp*Wp;
  //2nd order all-pass filter specified by Fp, and Qp
  Ab2 = 1.0;
  Ab1 = -1.0 * Wp/Qp;
  Ab0 = Wp2;
  Aa2 = 1.0;
  Aa1 = Wp/Qp;
  Aa0 = Wp2;
  //convert the analog TF coefficients to z^-1 domain TF coefficients
  Db0 = Ab2*K2 + Ab1*K + Ab0;
  Db1 = 2.0*Ab0 - 2.0*Ab2*K2;
  Db2 = Ab2*K2 - Ab1*K + Ab0;
  Da0 = Aa2*K2 + Aa1*K + Aa0;
  Da1 = 2.0*Aa0 - 2.0*Aa2*K2;
  Da2 = Aa2*K2 - Aa1*K + Aa0;
  //convert to normalized form by dividing thru by Da0:
  Db0 /= Da0;
  Db1 /= Da0;
  Db2 /= Da0;
  Da1 /= Da0;
  Da2 /= Da0;
  //done with TF coefficient calcs...
  
  //push back a new instance_data and store the index of it in plugin_data
  instance_data.push_back(per_instance_data_struct() );
  plugin_data->instance_data_index = idi = instance_data.size()-1;

  // store Db0, Db1, and Db2 in instance_data:
  instance_data[idi].b0 = Db0;
  instance_data[idi].b1 = Db1;
  instance_data[idi].b2 = Db2;
  //initialize past samples x1, x2 to zero in instance_data:
  instance_data[idi].x1 = 0.0;
  instance_data[idi].x2 = 0.0;

  if ( Qp > 0.5 ) {
    //Q>0.5, so there are two complex poles. Initialize CC storage and parameters.
    //push back a new instance of CCstage
    CCstage.push_back( vector<CCstage_data_struct>() );
    //set the plugin_data's instance_index, and the local variable id, to CCstage.size()-1
    instance_data[idi].instance_index = ii = CCstage.size()-1;
    //calculate c = a + i*b from biquad coefficients per Martins' post on the KVR forums
    // above EQ rewritten as complex_pole = real_part + 1i * imaginary_part
    real_part = -Da1/2.0;
    imaginary_part = sqrt(Da2 - Da1*Da1/4.0); 
    complex_pole = real_part + 1i * imaginary_part; 
    //calculate a_over_b = a / b 
    instance_data[idi].a_over_b = real_part / imaginary_part; //a_over_b is a global var
    //calculate num_CCstages, the required numer of stages, using SNR and ABS(c).
    //  the number of required stages is rounded to the nearest integer
    instance_data[idi].num_CCstages = trunc( 0.5 + log2( -SNR / (20.0*log10( abs( complex_pole ) ) ) ) );
    //resize the CCstage[] vector
    CCstage[ii].resize(instance_data[idi].num_CCstages+1); //the +1 is because there is a 0th stage
    //loop over CCstage vector and peform setup tasks:
    for (unsigned int stage_index=0; stage_index<=instance_data[idi].num_CCstages; stage_index++) {
      CCstage[ii][stage_index].cb_size = pow(2,stage_index); //calc the circular buffer size
      // resize vectors to hold cb_size values and fill with zeroes :
      CCstage[ii][stage_index].past_x_inputs.assign( CCstage[ii][stage_index].cb_size, 0.0 );
      CCstage[ii][stage_index].past_y_inputs.assign( CCstage[ii][stage_index].cb_size, 0.0 );
      // calculate a and b values for each stage from c:
      complex_temp = pow( complex_pole, pow( 2, stage_index ) ); //calculate c^2^N
      CCstage[ii][stage_index].a = real( complex_temp ); 
      CCstage[ii][stage_index].b = imag( complex_temp );
      CCstage[ii][stage_index].cb_index = 0; //set an arbitrary start value for the c.b.
    } //end for-loop over stages
    //store the number of output samples that should be set to zero at startup
    instance_data[idi].startup_samples = pow(2,instance_data[idi].num_CCstages);
    //report the latency
    cout << "For the RIIR_AP2 instance with Fp = " << Fp << ", Qp = " << Qp << ", and SNR = " << SNR << ":" << endl;
    cout << "   " << instance_data[idi].num_CCstages << " stages are required for the complex pole." << endl;
    cout << "The latency produced by the reverse-IIR processing will be:" << endl;
    cout << "   " << instance_data[idi].startup_samples << " samples at at sample rate of " << plugin_data->SR << " Hz, or ";
    cout << fixed << setprecision(3) << 1000.0* instance_data[idi].startup_samples / plugin_data->SR << " milliseconds." << endl;    
    return;
  } //end initializations for Q>0.5

  //only reach here if Q<=0.5. This produces two real poles.
  //calculate the real poles from biquad coefficients:
  if ( Qp == 0.5 ) {
    //for Q=0.5 the poles are identical
    RP1 = RP2 = -Da1/2.0;
  } else {
    RP1 = -Da1/2.0 + sqrt( Da1*Da1/4.0 - Da2 );
    RP2 = -Da1/2.0 - sqrt( Da1*Da1/4.0 - Da2 );
  }     
  //Initialize storage and parameters for each pole separately
  //push back a new instance of RP1stage and RP2stage
  RP1stage.push_back( vector<RPstage_data_struct>() );
  RP2stage.push_back( vector<RPstage_data_struct>() );
  //set the plugin_data's instance_index, and the local variable id, to RP1stage.size()-1
  instance_data[idi].instance_index = ii = RP1stage.size()-1;

  //begin RP1 initializations:
  //calculate num_RP1stages, the required numer of stages, using SNR and ABS(c).
  //  the number of required stages is rounded to the nearest integer
   //calculate real poles RP1 and RP2 from biquad coefficients:
  //proceed first with RP1: 
  instance_data[idi].num_RP1stages = trunc( 0.5 + log2( -SNR / (20.0*log10( RP1 ) ) ) );
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

  //begin RP2 initializations:
  //Repeat for second pole. Values are different since poles are not identical
  instance_data[idi].num_RP2stages = trunc( 0.5 + log2( -SNR / (20.0*log10( RP2 ) ) ) );
  //resize the RP2stage[] vector
  RP2stage[ii].resize(instance_data[idi].num_RP2stages+1); //the +1 is because there is a 0th stage
  for (unsigned int stage_index=0; stage_index<=instance_data[idi].num_RP2stages; stage_index++) {
    RP2stage[ii][stage_index].cb_size = pow(2,stage_index); //calc the circular buffer size
    // resize vector to hold cb_size values and fill with zeroes :
    RP2stage[ii][stage_index].past_x_inputs.assign( RP2stage[ii][stage_index].cb_size, 0.0 );
    // calculate a value for each stage from c:
    RP2stage[ii][stage_index].a = pow( RP2, pow( 2, stage_index ) ); //calculate c^2^N 
    RP2stage[ii][stage_index].cb_index = 0; //set an arbitrary start value for the c.b.
  } //end for-loop over RP2 stages
  //done with RP2 initializations:
  //store the number of output samples that should be set to zero at startup
  instance_data[idi].startup_samples = pow(2, instance_data[idi].num_RP1stages);
  instance_data[idi].startup_samples += pow(2, instance_data[idi].num_RP2stages );
  //report the latency
  cout << "For the RIIR_AP2 instance with Fp = " << Fp << ", Qp = " << Qp << ", and SNR = " << SNR << ":" << endl;
  cout << "   " << instance_data[idi].num_RP1stages << " stages are required for real pole 1" << endl;
  cout << "   " << instance_data[idi].num_RP2stages << " stages are required for real pole 2." << endl;
  cout << "The latency produced by the reverse-IIR processing will be:" << endl;
  cout << "   " << instance_data[idi].startup_samples << " samples at at sample rate of " << plugin_data->SR << " Hz, or ";
  cout << fixed << setprecision(3) << 1000.0* instance_data[idi].startup_samples / plugin_data->SR << " milliseconds." << endl;    

} //end activate_RIIRAP2




void RIIRAP2_run(LADSPA_Handle instance, unsigned long sample_count) {
  plugin_data_struct *plugin_data = (plugin_data_struct *)instance;
  const LADSPA_Data *input = plugin_data->input_ptr;
  LADSPA_Data *output = plugin_data->output_ptr;
  LADSPA_Data Qp = *(plugin_data->qp_ptr);
  double x, y, u, v; 
  unsigned int ii, idi;

  //get indeces for this particular instance of the plugin:
  idi = plugin_data->instance_data_index;
  ii = instance_data[idi].instance_index;   
  //begin RIIR calculation of poles (denominator of TF)
  //the calculation method depends on the type of poles:
  if ( Qp > 0.5 ) {
    //for Q>0.5 there are two complex conjugate poles:      
    for (unsigned long pos = 0; pos < sample_count; pos++) {
      x = input[pos];
      y = 0.0;
      for (unsigned int stage_index=0; stage_index<=instance_data[idi].num_CCstages; stage_index++) {
        u = CCstage[ii][stage_index].a * x - CCstage[ii][stage_index].b * y + CCstage[ii][stage_index].past_x_inputs[CCstage[ii][stage_index].cb_index]; 
        v = CCstage[ii][stage_index].b * x + CCstage[ii][stage_index].a * y + CCstage[ii][stage_index].past_y_inputs[CCstage[ii][stage_index].cb_index];
        CCstage[ii][stage_index].past_x_inputs[CCstage[ii][stage_index].cb_index] = x;
        CCstage[ii][stage_index].past_y_inputs[CCstage[ii][stage_index].cb_index] = y;
        CCstage[ii][stage_index].cb_index = ( CCstage[ii][stage_index].cb_index + 1 ) % CCstage[ii][stage_index].cb_size;
        x = u;
        y = v;
      } //  end for-loop over stages
      // final combines the real and imaginary outputs:
      x = x + instance_data[idi].a_over_b * y;
      //done with RIIR denominator pole calculation for a pair of complex conjugate poles.
      output[pos] = instance_data[idi].b0 * instance_data[idi].x2 + instance_data[idi].b1 * instance_data[idi].x1 + instance_data[idi].b2 * x;
      //update values for x1, x2
      instance_data[idi].x2 = instance_data[idi].x1;
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
    }  //end check for startup samples
    //end processing for Q>0.5
  } else {
    //for Q<=0.5 there are two real poles. Calculate these in series:
    for (unsigned long pos = 0; pos < sample_count; pos++) {
      x = input[pos];
      //RP1:      
      for (unsigned int stage_index=0; stage_index<=instance_data[idi].num_RP1stages; stage_index++) {
        y = RP1stage[ii][stage_index].a * x + RP1stage[ii][stage_index].past_x_inputs[RP1stage[ii][stage_index].cb_index]; 
        RP1stage[ii][stage_index].past_x_inputs[RP1stage[ii][stage_index].cb_index] = x;
        RP1stage[ii][stage_index].cb_index = ( RP1stage[ii][stage_index].cb_index + 1 ) % RP1stage[ii][stage_index].cb_size;
        x = y;
      }
      //done with RP1. Continue with RP2:
      for (unsigned int stage_index=0; stage_index<=instance_data[idi].num_RP2stages; stage_index++) {
        y = RP2stage[ii][stage_index].a * x + RP2stage[ii][stage_index].past_x_inputs[RP2stage[ii][stage_index].cb_index]; 
        RP2stage[ii][stage_index].past_x_inputs[RP2stage[ii][stage_index].cb_index] = x;
        RP2stage[ii][stage_index].cb_index = ( RP2stage[ii][stage_index].cb_index + 1 ) % RP2stage[ii][stage_index].cb_size;
        x = y;
      }
      //done calculating poles RP1 and RP2 in series 
      output[pos] = instance_data[idi].b0 * instance_data[idi].x2 + instance_data[idi].b1 * instance_data[idi].x1 + instance_data[idi].b2 * x;
      //update values for x1, x2
      instance_data[idi].x2 = instance_data[idi].x1;
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
  } //end processing for Q<=0.5
} //end run_RIIRAP2.



void RIIRAP2_cleanup(LADSPA_Handle instance) {
  //free storage used by global data containers
  CCstage.clear();
  RP1stage.clear();
  RP2stage.clear();
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
    RIIRAP2_Descriptor = (LADSPA_Descriptor *)malloc(sizeof(LADSPA_Descriptor));
    const unsigned long num_ports = 5;
    string text;

    if (RIIRAP2_Descriptor) {
      //plugin descriptor info
      RIIRAP2_Descriptor->UniqueID = 5225;
      RIIRAP2_Descriptor->Label = "RIIR_AP2";
      RIIRAP2_Descriptor->Properties = LADSPA_PROPERTY_HARD_RT_CAPABLE;
      RIIRAP2_Descriptor->Name = "Reverse IIR 2nd order AllPass Filter";
      RIIRAP2_Descriptor->Maker = "Charlie Laub, 2024";
      RIIRAP2_Descriptor->Copyright = "GPL";
      RIIRAP2_Descriptor->PortCount = num_ports;

      //create storage for port_descriptors, port_range_hints, and port_names        
      port_descriptors = (LADSPA_PortDescriptor *)calloc(num_ports,sizeof(LADSPA_PortDescriptor));
      RIIRAP2_Descriptor->PortDescriptors = (const LADSPA_PortDescriptor *)port_descriptors;
      port_range_hints = (LADSPA_PortRangeHint *)calloc(num_ports,sizeof(LADSPA_PortRangeHint));
      RIIRAP2_Descriptor->PortRangeHints = (const LADSPA_PortRangeHint *)port_range_hints;
      port_names = (char **)calloc(num_ports, sizeof(char*));
      RIIRAP2_Descriptor->PortNames = (const char **)port_names;
      //done creating storage. now set the descriptor, range_hints, and name for each port:

      //port = pole frequency      
      port_descriptors[RIIRAP2_FP] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "fp";
      port_names[RIIRAP2_FP] = strdup(text.c_str());
      port_range_hints[RIIRAP2_FP].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_DEFAULT_440;
      port_range_hints[RIIRAP2_FP].LowerBound = 1.0;
      port_range_hints[RIIRAP2_FP].UpperBound = 100000.0;

      //port = pole Q      
      port_descriptors[RIIRAP2_QP] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "qp";
      port_names[RIIRAP2_QP] = strdup(text.c_str());
      port_range_hints[RIIRAP2_QP].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_DEFAULT_1;
      port_range_hints[RIIRAP2_QP].LowerBound = 0.1;
      port_range_hints[RIIRAP2_QP].UpperBound = 20.0;

      //port = Signal to Noise Ratio      
      port_descriptors[RIIRAP2_SNR] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "snr";
      port_names[RIIRAP2_SNR] = strdup(text.c_str());
      port_range_hints[RIIRAP2_SNR].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_DEFAULT_MIDDLE;
      port_range_hints[RIIRAP2_SNR].LowerBound = 10.0;
      port_range_hints[RIIRAP2_SNR].UpperBound = 150.0;

      //port = audio data INPUT   
      port_descriptors[RIIRAP2_INPUT] = LADSPA_PORT_INPUT | LADSPA_PORT_AUDIO;
      text = "Input";
      port_names[RIIRAP2_INPUT] = strdup(text.c_str());

      //port = audio data OUTPUT
      port_descriptors[RIIRAP2_OUTPUT] = LADSPA_PORT_OUTPUT | LADSPA_PORT_AUDIO;
      text = "Output";
      port_names[RIIRAP2_OUTPUT] = strdup(text.c_str());

      RIIRAP2_Descriptor->activate = RIIRAP2_activate;
      RIIRAP2_Descriptor->cleanup = RIIRAP2_cleanup;
      RIIRAP2_Descriptor->connect_port = RIIRAP2_connectPort;
      RIIRAP2_Descriptor->deactivate = NULL;
      RIIRAP2_Descriptor->instantiate = RIIRAP2_instantiate;
      RIIRAP2_Descriptor->run = RIIRAP2_run;
      RIIRAP2_Descriptor->run_adding = NULL;
      RIIRAP2_Descriptor->set_run_adding_gain = NULL;
    }
  }
  ~Initialiser() {
    if (RIIRAP2_Descriptor) {
      free((LADSPA_PortDescriptor *)RIIRAP2_Descriptor->PortDescriptors);
      free((char **)RIIRAP2_Descriptor->PortNames);
      free((LADSPA_PortRangeHint *)RIIRAP2_Descriptor->PortRangeHints);
      free(RIIRAP2_Descriptor);
    }
  }                                      
} g_theInitialiser;


  
