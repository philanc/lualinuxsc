
# ----------------------------------------------------------------------
# adjust the following to the location of your Lua directory
# or include files and executable

LUADIR= ../lua
LUAINC= -I$(LUADIR)/include
LUAEXE= $(LUADIR)/bin/lua

# ----------------------------------------------------------------------

CC= gcc
AR= ar

CFLAGS= -Os -fPIC $(LUAINC) 
LDFLAGS= -fPIC

OBJS= lsccore.o

lsccore.so:  lsccore.c
	$(CC) -c $(CFLAGS) lsccore.c
	$(CC) -shared $(LDFLAGS) -o lsccore.so $(OBJS)
	strip lsccore.so

test: lsccore.so
	$(LUAEXE) ./test.lua

clean:
	rm -f *.o *.a *.so

.PHONY: clean test


