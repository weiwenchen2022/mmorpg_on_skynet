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
	   cjson \
	   srp \
	   aes \
	   uuid \

all : \
  $(foreach v, $(LUA_CLIB), $(LUA_CLIB_PATH)/$(v).so)

$(LUA_CLIB_PATH)/cjson.so : | $(LUA_CLIB_PATH)
	cd 3rd/lua-cjson && $(MAKE)
	cp -f 3rd/lua-cjson/cjson.so $@

$(LUA_CLIB_PATH)/cmsgpack.so : 3rd/lua-cmsgpack/Makefile | $(LUA_CLIB_PATH)
	cd 3rd/lua-cmsgpack/build && $(MAKE)
	cp -f 3rd/lua-cmsgpack/build/cmsgpack.so $@

3rd/lua-cmsgpack/Makefile :
	cd 3rd/lua-cmsgpack; mkdir build; cd build; cmake ..

$(LUA_CLIB_PATH)/srp.so : lualib-src/lua-srp.c $(OPENSSL_STATICLIB) | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) -I$(OPENSSL_INC) -o $@ $^ -pthread

$(LUA_CLIB_PATH)/aes.so : lualib-src/lua-aes.c $(OPENSSL_STATICLIB) | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) -I$(OPENSSL_INC) -o $@ $^ -pthread

$(LUA_CLIB_PATH)/uuid.so : lualib-src/lua-uuid.c | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) -o $@ $^

$(LUA_CLIB_PATH) :
	-mkdir $@

$(OPENSSL_STATICLIB) :
	cd 3rd/openssl && ./Configure && $(MAKE)

clean :
	rm -f $(LUA_CLIB_PATH)/*.so
