#define LUA_LIB
#include "lua.h"
#include "lauxlib.h"

#include "openssl/evp.h"
#include "openssl/aes.h"

static int lencrypt(lua_State *L)
{
    size_t len;
    const unsigned char *text = (const unsigned char *)luaL_checklstring(L, 1, &len);
    const unsigned char *key = (const unsigned char *)luaL_checkstring(L, 2);

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    unsigned char iv[16] = {0,};
    unsigned char output[len + AES_BLOCK_SIZE];
    int olen1;
    int olen2;

    EVP_EncryptInit(ctx, EVP_aes_128_cbc(), key, iv);
    EVP_EncryptUpdate(ctx, output, &olen1, text, len);
    int ok = EVP_EncryptFinal(ctx, output + olen1, &olen2);
    EVP_CIPHER_CTX_free(ctx);

    if (!ok)
	return 0;

    lua_pushlstring(L, (const char *)output, olen1 + olen2);
    return 1;
}

static int ldecrypt(lua_State *L)
{
    size_t len;
    const unsigned char *text = (const unsigned char *)luaL_checklstring(L, 1, &len);
    const unsigned char *key = (const unsigned char *)luaL_checkstring(L, 2);

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    unsigned char iv[16] = {0,};
    unsigned char output[len];
    int olen1;
    int olen2;

    EVP_DecryptInit(ctx, EVP_aes_128_cbc(), key, iv);
    EVP_DecryptUpdate(ctx, output, &olen1, text, len);
    int ok = EVP_DecryptFinal(ctx, output + olen1, &olen2);
    EVP_CIPHER_CTX_free(ctx);

    if (!ok)
	return 0;

    lua_pushlstring(L, (const char *)output, olen1 + olen2);
    return 1;
}

LUAMOD_API int luaopen_aes(lua_State *L)
{
    luaL_checkversion(L);

    const luaL_Reg l[] = {
	{"encrypt", lencrypt,},
	{"decrypt", ldecrypt,},

	{NULL, NULL,},
    };

    luaL_newlib(L, l);
    return 1;
}
