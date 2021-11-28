#include "api.h"
#include "dirmonitor.h"

#ifdef _WIN32
  #include <windows.h>
  #define PATH_MAX MAX_PATH
#elif __APPLE__
  #include <sys/event.h>
#elif __linux__
  #include <sys/inotify.h>
#endif
#include <string.h>
#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>

int luaopen_system(lua_State *L);
int luaopen_renderer(lua_State *L);
int luaopen_regex(lua_State *L);
int luaopen_process(lua_State *L);
int luaopen_dirmonitor(lua_State* L);

static const luaL_Reg libs[] = {
  { "system",     luaopen_system     },
  { "renderer",   luaopen_renderer   },
  { "regex",      luaopen_regex   },
  { "process",    luaopen_process    },
  { "dirmonitor", luaopen_dirmonitor },
  { NULL, NULL }
};


void api_load_libs(lua_State *L) {
  for (int i = 0; libs[i].name; i++)
    luaL_requiref(L, libs[i].name, libs[i].func, 1);
}

static int f_check_dir_callback(int watch_id, void* L) {
  lua_pcall(L, 1, 1, 0);
  int result = lua_toboolean(L, -1);
  lua_pop(L, 1);
  return !result;
}

static int f_dirmonitor_new(lua_State* L) {
  struct dirmonitor** monitor = lua_newuserdata(L, sizeof(struct dirmonitor*));
  *monitor = init_dirmonitor();
  return 1;
}

static int f_dirmonitor_gc(lua_State* L) {
  struct dirmonitor** monitor = luaL_checkudata(L, 1, "dirmonitor");
  deinit_dirmonitor(*monitor);
  return 0;
}

static int f_dirmonitor_watch(lua_State *L) {
  lua_pushnumber(L, add_dirmonitor(luaL_checkudata(L, 1, "dirmonitor"), luaL_checkstring(L, 2)) == 0);
  return 1;
}

static int f_dirmonitor_check(lua_State* L) {
  lua_pushboolean(L, check_dirmonitor(luaL_checkudata(L, 1, "dirmonitor"), f_check_dir_callback, L) == 0);
  return 1;
}
static const luaL_Reg dirmonitor_lib[] = {
  { "new",      f_dirmonitor_new          },
  { "__gc",     f_dirmonitor_gc          },
  { "watch",    f_dirmonitor_watch          },
  { "check",    f_dirmonitor_check          },
};

int luaopen_dirmonitor(lua_State* L) {
  luaL_newmetatable(L, "dirmonitor");
  luaL_setfuncs(L, dirmonitor_lib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  return 1;
}
