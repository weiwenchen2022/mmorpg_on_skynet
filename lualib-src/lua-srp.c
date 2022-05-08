#define LUA_LIB
#include "lua.h"
#include "lauxlib.h"

#include "openssl/srp.h"
#include "openssl/rand.h"

#include <assert.h>

#define KEY_SIZE 32 // 32 bytes == 256 bits

static inline void push_bn(lua_State *L, BIGNUM *bn)
{
    unsigned char bin[1024];
    int len = BN_bn2bin(bn, bin);
    assert(len < sizeof(bin));

    lua_pushlstring(L, (const char *)bin, len);
}

static int lcreate_verifier(lua_State *L)
{
    SRP_gN *GN = SRP_get_default_gN("1024");
    BIGNUM *s = NULL;
    BIGNUM *v = NULL;

    const char *I = luaL_checkstring(L, 1);
    const char *p = luaL_checkstring(L, 2);
    if (!SRP_create_verifier_BN(I, p, &s, &v, GN->N, GN->g))
	return 0;

    push_bn(L, s);
    push_bn(L, v);
    BN_free(s);
    BN_clear_free(v);

    return 2;
}

static inline BIGNUM *random_key(void)
{
    unsigned char bin[KEY_SIZE];
    RAND_bytes(bin, sizeof(bin));

    return BN_bin2bn(bin, sizeof(bin), NULL);
}

static int lcreate_client_key(lua_State *L)
{
    SRP_gN *GN = SRP_get_default_gN("1024");
    BIGNUM *a;
    BIGNUM *A;

    while (1) {
	a = random_key();
	A = SRP_Calc_A(a, GN->N, GN->g);

	if (!SRP_Verify_A_mod_N(A, GN->N)) {
	    BN_clear_free(a);
	    BN_free(A);
	} else
	    break;
    }

    push_bn(L, a);
    push_bn(L, A);
    BN_clear_free(a);
    BN_free(A);

    return 2;
}

static inline BIGNUM *lua_tobn(lua_State *L, int index)
{
    size_t len;
    const char *s = luaL_checklstring(L, index, &len);
    return BN_bin2bn((unsigned char *)s, len, NULL);
}

static int lcreate_server_session_key(lua_State *L)
{
    SRP_gN *GN = SRP_get_default_gN("1024");
    BIGNUM *v = lua_tobn(L, 1);
    BIGNUM *A = lua_tobn(L, 2);

    BIGNUM *b;
    BIGNUM *B;

    for (;;) {
	b = random_key();
	B = SRP_Calc_B(b, GN->N, GN->g, v);

	if (!SRP_Verify_B_mod_N(B, GN->N)) {
	    BN_clear_free(b);
	    BN_free(B);
	} else
	    break;
    }

    BIGNUM *u = SRP_Calc_u(A, B, GN->N);
    BIGNUM *K = SRP_Calc_server_key(A, v, u, b, GN->N);

    push_bn(L, K);
    push_bn(L, b);
    push_bn(L, B);

    BN_clear_free(b);
    BN_free(B);

    BN_clear_free(v);
    BN_free(A);

    BN_clear_free(u);
    BN_clear_free(K);

    return 3;
}

static int lcreate_client_session_key(lua_State *L)
{
    SRP_gN *GN = SRP_get_default_gN("1024");
    const char *I = luaL_checkstring(L, 1);
    const char *p = luaL_checkstring(L, 2);
    BIGNUM *s = lua_tobn(L, 3);
    BIGNUM *a = lua_tobn(L, 4);
    BIGNUM *A = lua_tobn(L, 5);
    BIGNUM *B = lua_tobn(L, 6);

    BIGNUM *u = SRP_Calc_u(A, B, GN->N);
    BIGNUM *x = SRP_Calc_x(s, I, p);
    BIGNUM *K = SRP_Calc_client_key(GN->N, B, GN->g, x, a, u);

    push_bn(L, K);

    BN_clear_free(a);
    BN_free(s);
    BN_free(A);
    BN_free(B);
    BN_clear_free(u);
    BN_clear_free(x);
    BN_clear_free(K);

    return 1;
}

static int lrandom(lua_State *L)
{
    BIGNUM *bn = random_key();
    push_bn(L, bn);
    BN_free(bn);

    return 1;
}

LUAMOD_API int luaopen_srp(lua_State *L)
{
    luaL_checkversion(L);

    const luaL_Reg l[] = {
	{"create_verifier", lcreate_verifier,},
	{"create_client_key", lcreate_client_key,},
	{"create_server_session_key", lcreate_server_session_key,},
	{"create_client_session_key", lcreate_client_session_key,},
	{"random", lrandom,},

	{NULL, NULL,},
    };

    luaL_newlib(L, l);
    return 1;
}
