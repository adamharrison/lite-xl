#include "api.h"


int luaopen_system(lua_State *L);
int luaopen_renderer(lua_State *L);
int luaopen_regex(lua_State *L);
int luaopen_process(lua_State *L);

static const luaL_Reg libs[] = {
  { "system",    luaopen_system     },
  { "renderer",  luaopen_renderer   },
  { "regex",     luaopen_regex   },
  { "process",   luaopen_process    },
  { NULL, NULL }
};

#if LUA_VERSION_NUM <= 501
static void luaL_requiref (lua_State *L, char const* modname,
                    lua_CFunction openf, int glb) {
  luaL_checkstack(L, 3, "not enough stack slots");
  lua_pushcfunction(L, openf);
  lua_pushstring(L, modname);
  lua_call(L, 1, 1);
  lua_getglobal(L, "package");
  lua_getfield(L, -1, "loaded");
  lua_replace(L, -2);
  lua_pushvalue(L, -2);
  lua_setfield(L, -2, modname);
  lua_pop(L, 1);
  if (glb) {
    lua_pushvalue(L, -1);
    lua_setglobal(L, modname);
  }
}
static int bit32_extract(lua_State* L) {
  int bits = (int)luaL_checknumber(L, 1);
  int offset = (int)luaL_checknumber(L, 2);
  int length = (int)luaL_checknumber(L, 3);
  lua_pushnumber(L, (bits & (((1 << (length+1)) - 1) << offset)) >> offset);
  return 1;
}

static int bit32_replace(lua_State* L) {
  int bits = (int)luaL_checknumber(L, 1);
  int number = (int)luaL_checknumber(L, 2);
  int offset = (int)luaL_checknumber(L, 3);
  int length = (int)luaL_checknumber(L, 4);
  int mask = (((1 << (length+1)) - 1) << offset);
  lua_pushnumber(L, (bits & ~mask) | ((number << offset) & mask));
  return 1;
}

#endif

void api_load_libs(lua_State *L) {
  for (int i = 0; libs[i].name; i++)
    luaL_requiref(L, libs[i].name, libs[i].func, 1);
  #if LUA_VERSION_NUM <= 501
  lua_newtable(L);
  lua_pushcfunction(L, bit32_extract);
  lua_setfield(L, -2, "extract");
  lua_pushcfunction(L, bit32_replace);
  lua_setfield(L, -2, "replace");
  lua_setglobal(L, "bit32");
  #endif
}
