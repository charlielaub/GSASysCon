INSTALL_PLUGINS_DIR	=	/usr/local/lib/ladspa/

CC		=	g++
LD		=	g++

CFLAGS		=	-I. -Ofast -Wall -c -fPIC -DPIC
LDFLAGS		= -shared

PLUGINS		=	ACDf.so

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

