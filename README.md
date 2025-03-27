# GSASysCon
 the GStreamer Streaming Audio System Controller

The installation instructions can be found in the file system_control/docs/SetupGuide.txt
After downloading the repository, follow the instructions in the Setup Guide and run a "first test" to confirm success.

This app is designed to run on Linux OSes in the bash terminal environment. It can also be run under WSL2.

ABOUT GSASysCon:
GSASysCon is designed for the DIYer who wishes to use software based IIR DSP processing for e.g. loudspeaker crossovers or other audio processing and uses the command line version of GStreamer to carry out all audio tasks.

Gstreamer is a powerful multi-media platform that is continually undergoing development and improvement. Because Gstreamer pipelines are difficult to write from scratch, I wrote the GSASysCon application to generate them based on the contents of a user input file that describes the DSP processing. GSASysCon can be used to turn your computer into a “preamp” with input switching and volume control plus everything you need to do DSP processing. 

Here is a quick overview of the behavior and features:

• Control of and Interaction with the program is 100% text based via simple input files and a text-based user-interface.
• Filtering and routing is easy to configure via an intuitive configuration file structure
• Variable substitution, file insertion, and channel duplication capabilities make it easy to describe the DSP processing for complicated, multichannel setups.
• The control interface can turn systems on and off and control playback volume. These features can be controlled remotely over your LAN via SSH.
• Gstreamer provides several source and sink TIME (not rate) based synchronization mechanisms. This makes it possible for synchronized playback of multiple, disparate sinks and adaptive rate playback.
• Can be run under Debian/Ubuntu based OSes (including Rasberry Pi OS) or Windows 11 WSL2 in which the bash shell is available.
• Input audio can be from a live source, Pipewire/PulseAudio monitor, or ALSA Loopback (use VB-Audio Virtual Cable under Windows)
• The Gstreamer command string for any pipeline can captured and run outside of the app, if desired.
• GSASysCon can create playback systems made up of multiple remote clients. Audio is sent using RTP over the local network (hardcable or WiFi) to one or more playback endpoints (computer+audio device/DAC). Tight playback synchronization between endpoints can be achieved when their clocks are synchronized using chrony (NTP).
• In GSASysCon, DSP is exclusively IIR filtering via LADSPA as filter-chains. FIR filtering is not currently available.
• GSASysCon was designed for music playback without any particular concerns for latency. Buffer size is fixed at 1024 samples.
• Gstreamer pipelines created with GSASysCon run at a fixed audio rate that is chosen by the user. There is a high quality resampler built into Gstreamer that handles SR conversions.


The combination of Gstreamer and LADSPA is a robust and reliable DSP platform for DIY audio processing under Linux, or WSL2 under Windows. I've been using this to implement IIR DSP crossovers in tandem with my ACDf LADSPA plugin since 2016. ACDf implements all the first and second order filter types – it’s all you need for loudspeaker crossovers and PEQ duty.
