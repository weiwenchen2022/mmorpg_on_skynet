SKYNET_ROOT ?= skynet/

LUA_CLIB_PATH ?= luaclib

CC ?= gcc
CFLAGS = -g -O2 -Wall -I$(LUA_INC)
SHARED := -fPIC --shared

# lua
LUA_INC ?= $(SKYNET_ROOT)3rd/lua

# openssl
OPENSSL_STATICLIB := 3rd/openssl/libcrypto.a
OPENSSL_INC := 3rd/openssl/include

LUA_CLIB = \
	   cmsgpack \
	   srp \
	   aes \
	   uuid \

all : \
  $(SKYNET_ROOT)/skynet \
  $(foreach v, $(LUA_CLIB), $(LUA_CLIB_PATH)/$(v).so)

# skynet
$(SKYNET_ROOT)/skynet : $(SKYNET_ROOT)/Makefile
	$(MAKE) -C $(SKYNET_ROOT) linux

$(SKYNET_ROOT)/Makefile :
	git submodule update --init

# cmsgpack
$(LUA_CLIB_PATH)/cmsgpack.so : 3rd/lua-cmsgpack/build/Makefile | $(LUA_CLIB_PATH)
	cd 3rd/lua-cmsgpack/build && $(MAKE)
	cp -f 3rd/lua-cmsgpack/build/cmsgpack.so $@

3rd/lua-cmsgpack/build/Makefile : | 3rd/lua-cmsgpack/CMakeLists.txt
	cd 3rd/lua-cmsgpack; mkdir build; cd build; cmake ..

3rd/lua-cmsgpack/CMakeLists.txt :
	git submodule update --init

$(LUA_CLIB_PATH)/srp.so : lualib-src/lua-srp.c $(OPENSSL_STATICLIB) | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) -I$(OPENSSL_INC) -o $@ $^ -pthread

$(LUA_CLIB_PATH)/aes.so : lualib-src/lua-aes.c $(OPENSSL_STATICLIB) | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) -I$(OPENSSL_INC) -o $@ $^ -pthread

$(LUA_CLIB_PATH)/uuid.so : lualib-src/lua-uuid.c | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) -o $@ $^

$(LUA_CLIB_PATH) :
	-mkdir $@

$(OPENSSL_STATICLIB) : 3rd/openssl/Makefile
	cd 3rd/openssl && $(MAKE)

3rd/openssl/Makefile : | 3rd/openssl/Configure
	cd 3rd/openssl && ./Configure

3rd/openssl/Configure :
	git submodule update --init

clean :
	rm -f $(LUA_CLIB_PATH)/*.so
