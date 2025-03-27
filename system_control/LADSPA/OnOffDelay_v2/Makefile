INSTALL_PLUGINS_DIR	=	/usr/local/lib/ladspa/

CC		=	g++
LD		=	g++

# NOTE: set these flags to be specific to the hardware you are compiling for. See https://gcc.gnu.org for more information
CFLAGS		=	-c -O3 -march=native -fPIC -DPIC -Wno-unused-result
LDFLAGS		= 	-shared 

PLUGINS		=	OnOffDelay.so

all: $(PLUGINS)

%.o: %.cpp
	$(CC) $(CFLAGS) -o $@ $<

%.so: %.o
	$(LD) $(LDFLAGS) -o $@ $<

install: targets
	test -d $(INSTALL_PLUGINS_DIR) || mkdir $(INSTALL_PLUGINS_DIR)
	cp *.so $(INSTALL_PLUGINS_DIR)

targets:	$(PLUGINS)

always:	

clean:
	-rm -f `find . -name "*.so"`
	-rm -f `find . -name "*.o"`
	-rm -f `find . -name "*~"`

