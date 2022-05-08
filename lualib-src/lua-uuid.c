#define LUA_LIB
#include "lua.h"
#include "lauxlib.h"

#include <stdint.h>

static uint32_t sid = 0;

static int lsid(lua_State *L)
{
    if (sid >= 0xffffffff)
	sid = 0;

    lua_pushinteger(L, ++sid);
    return 1;
}

LUAMOD_API int luaopen_uuid_core(lua_State *L)
{
    luaL_checkversion(L);

    const luaL_Reg l[] = {
	{"sid", lsid,},

	{NULL, NULL,},
    };

    luaL_newlib(L, l);
    return 1;
}
