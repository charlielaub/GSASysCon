/* ACDf LADSPA plugin, version 4.1
   Copyright 2019-2024 Charlie Laub, GPLv3 

  ACDf is a LADSPA plugin for implementing filters for loudspeaker crossovers
  as described in the Active Crossover Designer tools, a set of Excel tools
  for designing crossovers based on driver measurements. See the documentation
  that accompanies this code or the Active Crossover Designer web site for 
  information on how to call this plugin correctly.  

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

  Much of the code here was adapted from previous work by:
  Matthias Nagorni (VCF filters)
  Richard Taylor (rt-plugins) 
  Steve Harris (swh-plugins)
*/

#include <string.h>
#include <stdlib.h>
#define _USE_MATH_DEFINES
#include <math.h>
#include <ladspa.h>
#include <string>
#include <iostream>
using namespace std;


#define D_(s) (s)
#define DENORMALKILLER 1.e-15; //1.e-15 corresponds to -300dB
  //DENORMALKILLER is added to the filter output to avoid denormal values that 
  //may slow the calculation on some hardware when very small values are
  //produced. The added signal is a square wave at the Nyquist frequency.


//order of parameters:
#define ACDf_TYPE         0 
#define ACDf_POLARITY     1 
#define ACDf_GAIN         2 
#define ACDf_FP           3 
#define ACDf_QP           4 
#define ACDf_FZ           5 
#define ACDf_QZ           6 
#define ACDf_INPUT        7 
#define ACDf_OUTPUT       8 


static LADSPA_Descriptor *ACDfDescriptor = NULL;

typedef struct {
  double dn;
  double x1, x2, y1, y2;
  double b0, b1, b2, a1, a2;
} biquad;


typedef struct {
	LADSPA_Data *type;
	LADSPA_Data *polarity;
	LADSPA_Data *gain;
	LADSPA_Data *Fp;
	LADSPA_Data *Qp;
	LADSPA_Data *Fz;
	LADSPA_Data *Qz;
  LADSPA_Data rate;
  biquad * filter;
	LADSPA_Data *input;
	LADSPA_Data *output;
} ACDf;


const LADSPA_Descriptor *ladspa_descriptor(unsigned long index) {
	switch (index) {
	case 0:
		return ACDfDescriptor;
	default:
		return NULL;
	}
}


LADSPA_Handle instantiateACDf(const LADSPA_Descriptor *descriptor, 
                                    unsigned long sample_rate) {
 
  ACDf *pluginData = (ACDf *)malloc(sizeof(ACDf));
  pluginData->rate = (LADSPA_Data)sample_rate;

	biquad *f = NULL;
	f = (biquad *)malloc(sizeof(biquad));
	pluginData->filter = f;

  return (LADSPA_Handle)pluginData;
}


void connectPortACDf(LADSPA_Handle instance, unsigned long port, LADSPA_Data *data) {
  ACDf *pluginData = (ACDf *)instance;
	switch (port) {
	case ACDf_TYPE:
		pluginData->type = data;
		break;
	case ACDf_POLARITY:
		pluginData->polarity = data;
		break;
	case ACDf_GAIN:
		pluginData->gain = data;
		break;
	case ACDf_FP:
		pluginData->Fp = data;
		break;
	case ACDf_QP:
		pluginData->Qp = data;
		break;
	case ACDf_FZ:
		pluginData->Fz = data;
		break;
	case ACDf_QZ:
		pluginData->Qz = data;
		break;
	case ACDf_INPUT:
		pluginData->input = data;
		break;
	case ACDf_OUTPUT:
		pluginData->output = data;
		break;
	}
}


void activateACDf(LADSPA_Handle instance) {
  ACDf *pluginData = (ACDf *)instance;
	biquad *f = pluginData->filter;
  const LADSPA_Data ftype = *(pluginData->type);
  const LADSPA_Data fpolarity = *(pluginData->polarity); 
  const LADSPA_Data dBgain = *(pluginData->gain);
  double Fp = *(pluginData->Fp); 
  double Qp = *(pluginData->Qp);
  double Fz = *(pluginData->Fz);
  double Qz = *(pluginData->Qz);
  const LADSPA_Data SR = pluginData->rate;

	//initialize some values...
  f->x1 = 0.0;
	f->x2 = 0.0;
	f->y1 = DENORMALKILLER;
	f->y2 = DENORMALKILLER;
  f->dn = DENORMALKILLER;

/* ====== BEGIN CODE TO CALCULATE FILTER TRANSFER FUNCTION COEFFICIENTS ========== */
  double Aa0, Aa1, Aa2, Ab0, Ab1, Ab2; //analog TF coefficients
  double Da0, Da1, Da2, Db0, Db1, Db2; //IIR digital TF coefficients
  double voltage_gain; //voltage gain
  double p_voltage_gain; //voltage gain including polarity
  double Wp, Wz, Wp2, Wz2; //for analog radian frequency
  bool reversed_polarity = false;
  const double K = 2.0*SR;
  const double K2 = K*K;
  int type; //type is used internally to select filter
  type = roundf((float)ftype); //round to nearest integer 
  voltage_gain = pow(10.0,(0.05*dBgain)); //calculate voltage gain
  p_voltage_gain = voltage_gain;
  //if reverse polarity is indicated, multiply p_voltage_gain by -1
  if (( fpolarity < -0.99 ) && (fpolarity > -1.01 )) {
    p_voltage_gain *= -1.0;
    reversed_polarity = true;
  }
  //error checking :
  //  if  parameters are invalid, return silence.
  if ( (Fp > 0.5*SR) || (Fp < 0) ) type = -1;
  if ( (Fz > 0.5*SR) || (Fz < 0) ) type = -1;

  //calculate analog domain radian frequencies  
  Wp = 2.0*M_PI*Fp;
  Wz = 2.0*M_PI*Fz;
  //apply pre-warping 
  Wp = K*tan( Wp/K );
  Wz = K*tan( Wz/K );
  //calculate square of pre-warped radian frequencies
  Wp2 = Wp*Wp;
  Wz2 = Wz*Wz;
  //initialize these analog coefficient values to zero
  Aa1 = Aa2 = Ab0 = Ab1 = Ab2 = 0.0;
  //and initialize the value of analog coefficient a0 to 1.0
  Aa0 = 1.0;

  switch (type) {
  case 0: //gain with polarity
    Ab0 = p_voltage_gain;
  break;
  case 1: //1st order lowpass filter with gain and polarity
    Ab0 = Wp * p_voltage_gain;
    Aa1 = 1.0;
    Aa0 = Wp;
  break;
  case 2: //1st order highpass filter with gain and polarity
    Ab1 = p_voltage_gain;
    Aa1 = 1.0;
    Aa0 = Wp;
  break;
  case 3: //first order all-pass filter with polarity 
    Ab1 = 1.0;
    Ab0 = -1.0 * Wp;
    if (reversed_polarity) {
      Ab1 *= -1.0;
      Ab0 *= -1.0;
    } 
    Aa1 = 1.0;
    Aa0 = Wp;
  break;
  case 4: //1st order low shelf specified by gain, polarity, and Fp (used as center of shelf)
    Wz = Wp * pow(10.0,(dBgain/40.0));
    Wp = Wp2 / Wz;
    Ab1 = 1.0;
    Ab0 = Wz;
    if (reversed_polarity) {
      Ab1 *= -1.0;
      Ab0 *= -1.0;
    }
    Aa1 = 1.0;
    Aa0 = Wp;
  break;
  case 5: //1st order high shelf specified by gain, polarity, and Fp (used as center of shelf) 
    Wz = Wp * pow(10.0,(-dBgain/40.0));
    Wp = Wp2 / Wz;
    Ab1 = 1.0 * voltage_gain;
    Ab0 = Wz * voltage_gain;
    if (reversed_polarity) {
      Ab1 *= -1.0;
      Ab0 *= -1.0;
    }
    Aa1 = 1.0;
    Aa0 = Wp;
  break;
  case 21: //2nd order lowpass filter specified by gain, polarity, Fp, Qp
    Ab0 = p_voltage_gain * Wp2;
    Aa2 = 1.0;
    Aa1 = Wp/Qp;
    Aa0 = Wp2;
  break;
  case 22: //2nd order highpass filter specified by gain, polarity, Fp, Qp
    Ab2 = p_voltage_gain;
    Aa2 = 1.0;
    Aa1 = Wp/Qp;
    Aa0 = Wp2;
  break;
  case 23: //2nd order all-pass filter specified by gain, polarity, Fp, Qp
    Ab2 = 1.0;
    Ab1 = -1.0 * Wp/Qp;
    Ab0 = Wp2;
    if (reversed_polarity) {
      Ab2 *= -1.0;
      Ab1 *= -1.0;
      Ab0 *= -1.0;
    }
    Aa2 = 1.0;
    Aa1 = Wp/Qp;
    Aa0 = Wp2;
  break;
  case 24: //2nd order low shelf specified by Fp (used as center of shelf), gain, Q, and polarity
    Qz = Qp;
    Wz = Wp * pow(10.0,(dBgain/80.0));
    Wp = Wp2 / Wz;
    Wz2 = Wz*Wz;
    Wp2 = Wp*Wp;
    Ab2 = 1.0;
    Ab1 = Wz/Qz;
    Ab0 = Wz2;
    if (reversed_polarity) {
      Ab2 *= -1.0;
      Ab1 *= -1.0;
      Ab0 *= -1.0;
    }
    Aa2 = 1.0;
    Aa1 = Wp/Qp;
    Aa0 = Wp2;
  break;
  case 25: //2nd order high shelf specified by Fp (used as center of shelf), gain, Q, and polarity
    Qz = Qp;
    Wz = Wp * pow(10.0,(-dBgain/80.0));
    Wp = Wp2 / Wz;
    Wz2 = Wz*Wz;
    Wp2 = Wp*Wp;
    Ab2 = voltage_gain;
    Ab1 = voltage_gain * Wz/Qz;
    Ab0 = voltage_gain * Wz2;
    if (reversed_polarity) {
      Ab2 *= -1.0;
      Ab1 *= -1.0;
      Ab0 *= -1.0;
    }
    Aa2 = 1.0;
    Aa1 = Wp/Qp;
    Aa0 = Wp2;
  break;
  case 26: //parametric EQ specified by gain, Fp, Qp 
    Ab2 = 1.0;
    Ab1 = Wp/Qp;
    if (voltage_gain > 1.0) Ab1 *= voltage_gain;
    Ab0 = Wp2;
    Aa2 = 1.0;
    Aa1 = Wp/Qp;
    if (voltage_gain < 1.0) Aa1 /= voltage_gain;
    Aa0 = Wp2;
  break;
  case 27: //2nd order notch specified by gain, polarity, Fp, Qp, Fz
    Ab2 = p_voltage_gain;
    Ab0 = p_voltage_gain * Wz2;
    Aa2 = 1.0;
    Aa1 = Wp/Qp;
    Aa0 = Wp2;
  break;
  case 28: //general biquadratic filter specified by gain, polarity, Fp,Qp,Fz,Qz 
    Ab2 = p_voltage_gain;
    Ab1 = p_voltage_gain * Wz/Qz;
    Ab0 = p_voltage_gain * Wz2;
    Aa2 = 1.0;
    Aa1 = Wp/Qp;
    Aa0 = Wp2;
  break;
  case 77: //2nd order notch specified by polarity, Fp, Qp, Fz and with automatic gain calculation
    // NOTE: the gain is automatically calculated for the LowPass notch and
    //    any gain supplied by the user is ignored. Gain is calcualted as follows:
    //     when Fp < Fz gain in dB = 40 log10( tan(p Fp/SR) / tan(p Fz/SR) )
    //     otherwise gain in dB = 0
    p_voltage_gain = voltage_gain = 1.0;
    if (Fp < Fz ) {
      //This is a Lowpass Notch filter. Calculate voltage gain and p_voltage_gain such that the
      //  passband level is set to 0dB
      voltage_gain = tan( M_PI*Fp/SR) / tan( M_PI*Fz/SR );
      voltage_gain = pow( voltage_gain, 2.0 ); //calculate voltage gain
      p_voltage_gain = voltage_gain;
    }
    //if reverse polarity is indicated, multiply p_voltage_gain by -1
    if (( fpolarity < -0.99 ) && (fpolarity > -1.01 )) {
      p_voltage_gain *= -1.0;
      reversed_polarity = true;
    }
    //calculate analog TF coefficients
    Ab2 = p_voltage_gain;
    Ab0 = p_voltage_gain * Wz2;
    Aa2 = 1.0;
    Aa1 = Wp/Qp;
    Aa0 = Wp2;
  break;
  default:
    //if user supplies a non-supported filter type silence is returned
    type = -1;
  } //end switch-case, done computing analog transfer function coefficients 

  //convert continuous time TF coefficients to discrete time TF coefficients
  //  and put into normalized form: 
  if (type < 1) { 
    Da0 = 1.0;
    Db0 = p_voltage_gain; //type = 0: gain stage
    if (type == -1 ) {
      //type is set to -1 if undefined types are supplied by user
      Db0 = 0.0; //returns silence
    }
    Db1 = Db2 = Da1 = Da2 = 0.0; //not used for type = 0 or type = -1
    //above is already in normalized form because Da0 = 1.0
  } else if (type < 20 ) {
    //convert the 1st order analog TF coefficients to z^-1 domain TF coefficients
    Db0 = Ab1*K + Ab0;
    Db1 = Ab0 - Ab1*K;
    Da0 = Aa1*K + Aa0;
    Da1 = Aa0 - Aa1*K;
    //convert to normalized form by dividing thru by Da0:
    Db0 /= Da0;
    Db1 /= Da0;
    Da1 /= Da0;
    Da2 = 0.0; //not used, set to zero
    Db2 = 0.0; //not used, set to zero
  } else {
    //convert the 2nd order analog TF coefficients to z^-1 domain TF coefficients
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
  }
  //for all types, copy results into the respective plugin filter variables  
  f->b0 = Db0;
  f->b1 = Db1;
  f->b2 = Db2;
  f->a1 = Da1;
  f->a2 = Da2;
  //save the transfer function parameters into the plugin filter object
	pluginData->filter = f;
/* ======= END CODE TO CALCULATE FILTER TRANSFER FUNCTION COEFFICIENTS =========== */
} //end activateACDf


void runACDf(LADSPA_Handle instance, unsigned long sample_count) {
  ACDf *pluginData = (ACDf *)instance;
  const LADSPA_Data *input = pluginData->input;
  LADSPA_Data *output = pluginData->output;
	biquad *f = pluginData->filter;
  double x,y;
	unsigned long pos;

  if ( f->a1 == 0.0  &&  f->a2 == 0.0 ) {
    //gain stage. 
  	for (pos = 0; pos < sample_count; pos++) {
      x = (double)input[pos];
      y = f->b0 * x + f->dn;
      f->dn = -f->dn;
      output[pos] = (LADSPA_Data)y;
  	}
    return;
  }

  if ( f->a2 == 0.0 ) {
    //first order transfer function, discrete form:
  	for (pos = 0; pos < sample_count; pos++) {
      x = (double)input[pos];
      y = f->b0 * x + f->b1 * f->x1 - f->a1 * f->y1 + f->dn;
      f->dn = -f->dn;
      f->x1 = x;
      f->y1 = y;
      output[pos] = (LADSPA_Data)y;
  	}
    return;
  }

  //second order transfer function, discrete form:
	for (pos = 0; pos < sample_count; pos++) {
    x = (double)input[pos];
    y = f->b0 * x + f->b1 * f->x1 + f->b2 * f->x2 - f->a1 * f->y1 - f->a2 * f->y2 + f->dn;
    f->dn = -f->dn;
    f->x2 = f->x1;
    f->x1 = x;
    f->y2 = f->y1;
    f->y1 = y;
    output[pos] = (LADSPA_Data)y;
	}
} //end runACDf.


void cleanupACDf(LADSPA_Handle instance) {
	ACDf *pluginData = (ACDf *)instance;
	free(pluginData->filter);
	free(instance);
}


static class Initialiser {
public:
  Initialiser() {
    char **port_names;
    LADSPA_PortDescriptor *port_descriptors;
    LADSPA_PortRangeHint *port_range_hints;
    ACDfDescriptor = (LADSPA_Descriptor *)malloc(sizeof(LADSPA_Descriptor));

    if (ACDfDescriptor) {
      std::string text;
      //plugin descriptor info
      ACDfDescriptor->UniqueID = 5221;
      ACDfDescriptor->Label = "ACDf";
      ACDfDescriptor->Properties = LADSPA_PROPERTY_HARD_RT_CAPABLE;
      text = "ACDf v4.0: Active Crossover Designer LADSPA filters";
      ACDfDescriptor->Name = strdup(text.c_str());
      ACDfDescriptor->Maker = "Charlie Laub, 2024";
      ACDfDescriptor->Copyright = "GPLv3";
      ACDfDescriptor->PortCount = 9;

      //create storage for port_descriptors, port_range_hints, and port_names        
      port_descriptors = (LADSPA_PortDescriptor *)calloc(9,sizeof(LADSPA_PortDescriptor));
      ACDfDescriptor->PortDescriptors = (const LADSPA_PortDescriptor *)port_descriptors;
      port_range_hints = (LADSPA_PortRangeHint *)calloc(9,sizeof(LADSPA_PortRangeHint));
      ACDfDescriptor->PortRangeHints = (const LADSPA_PortRangeHint *)port_range_hints;
      port_names = (char **)calloc(9, sizeof(char*));
      ACDfDescriptor->PortNames = (const char **)port_names;
      //done creating storage. now set the descriptor, range_hints, and name for each port:

      //port = ACDf_TYPE    
      port_descriptors[ACDf_TYPE] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "type";
      port_names[ACDf_TYPE] = strdup(text.c_str());
      port_range_hints[ACDf_TYPE].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_DEFAULT_0;
      port_range_hints[ACDf_TYPE].LowerBound = 0;
      port_range_hints[ACDf_TYPE].UpperBound = 77;

      //port = ACDf_POLARITY
      port_descriptors[ACDf_POLARITY] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "polarity";
      port_names[ACDf_POLARITY] = strdup(text.c_str());
      port_range_hints[ACDf_POLARITY].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_DEFAULT_1;
      port_range_hints[ACDf_POLARITY].LowerBound = -1;
      port_range_hints[ACDf_POLARITY].UpperBound = 1;

      //port = ACDf_GAIN    
      port_descriptors[ACDf_GAIN] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "db";
      port_names[ACDf_GAIN] = strdup(text.c_str());
      port_range_hints[ACDf_GAIN].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_DEFAULT_0;
      port_range_hints[ACDf_GAIN].LowerBound = -99;
      port_range_hints[ACDf_GAIN].UpperBound = 99;

      //port = ACDf_FP      
      port_descriptors[ACDf_FP] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "fp";
      port_names[ACDf_FP] = strdup(text.c_str());
      port_range_hints[ACDf_FP].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_DEFAULT_440;
      port_range_hints[ACDf_FP].LowerBound = 1;
      port_range_hints[ACDf_FP].UpperBound = 100000;

      //port = ACDf_QP      
      port_descriptors[ACDf_QP] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "qp";
      port_names[ACDf_QP] = strdup(text.c_str());
      port_range_hints[ACDf_QP].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_DEFAULT_1;
      port_range_hints[ACDf_QP].LowerBound = 0.01;
      port_range_hints[ACDf_QP].UpperBound = 100;

      //port = ACDf_FZ      
      port_descriptors[ACDf_FZ] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "fz";
      port_names[ACDf_FZ] = strdup(text.c_str());
      port_range_hints[ACDf_FZ].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_DEFAULT_440;
      port_range_hints[ACDf_FZ].LowerBound = 1;
      port_range_hints[ACDf_FZ].UpperBound = 100000;

      //port = ACDf_QZ      
      port_descriptors[ACDf_QZ] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
      text = "qz";
      port_names[ACDf_QZ] = strdup(text.c_str());
      port_range_hints[ACDf_QZ].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_DEFAULT_1;
      port_range_hints[ACDf_QZ].LowerBound = 0.01;
      port_range_hints[ACDf_QZ].UpperBound = 100;

      //port = ACDf_INPUT   
      port_descriptors[ACDf_INPUT] = LADSPA_PORT_INPUT | LADSPA_PORT_AUDIO;
      text = "Input";
      port_names[ACDf_INPUT] = strdup(text.c_str());
      //port_range_hints[ACDf_INPUT].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE;
      //port_range_hints[ACDf_INPUT].LowerBound = -1.0;
      //port_range_hints[ACDf_INPUT].UpperBound = +1.0;

      //port = ACDf_OUTPUT
      port_descriptors[ACDf_OUTPUT] = LADSPA_PORT_OUTPUT | LADSPA_PORT_AUDIO;
      text = "Output";
      port_names[ACDf_OUTPUT] = strdup(text.c_str());
      //port_range_hints[ACDf_OUTPUT].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE;
      //port_range_hints[ACDf_OUTPUT].LowerBound = -1.0;
      //port_range_hints[ACDf_OUTPUT].UpperBound = +1.0;

      ACDfDescriptor->activate = activateACDf;
      ACDfDescriptor->cleanup = cleanupACDf;
      ACDfDescriptor->connect_port = connectPortACDf;
      ACDfDescriptor->deactivate = NULL;
      ACDfDescriptor->instantiate = instantiateACDf;
      ACDfDescriptor->run = runACDf;
      ACDfDescriptor->run_adding = NULL;
      ACDfDescriptor->set_run_adding_gain = NULL;
    }
  }
  ~Initialiser() {
    if (ACDfDescriptor) {
      free((LADSPA_PortDescriptor *)ACDfDescriptor->PortDescriptors);
      free((char **)ACDfDescriptor->PortNames);
      free((LADSPA_PortRangeHint *)ACDfDescriptor->PortRangeHints);
      free(ACDfDescriptor);
    }
  }                                      
} g_theInitialiser;
  
