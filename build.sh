#!/bin/bash

: ${CC=gcc}
: ${AR=ar}
: ${SDL_CONFIG=sdl2-config}
if [[ $OSTYPE == 'msys' ]]; then
  : ${BIN=lite-xl.exe}
  : ${LNAME=liblite.lib}
else
  : ${BIN=lite-xl}
  : ${LNAME=liblite.a}
fi

# Supporting library
LLSRCS="lib/lua/ltable.c lib/lua/liolib.c lib/lua/lmem.c lib/lua/loslib.c lib/lua/ldebug.c lib/lua/ltm.c lib/lua/loadlib.c lib/lua/linit.c lib/lua/lmathlib.c lib/lua/lctype.c lib/lua/lstate.c lib/lua/lopcodes.c lib/lua/lstrlib.c lib/lua/lgc.c lib/lua/llex.c lib/lua/lparser.c lib/lua/lbaselib.c lib/lua/ldblib.c lib/lua/ltablib.c lib/lua/ldo.c lib/lua/lbitlib.c lib/lua/lstring.c lib/lua/lauxlib.c lib/lua/lobject.c lib/lua/lvm.c lib/lua/lcode.c lib/lua/lundump.c lib/lua/lcorolib.c lib/lua/lapi.c lib/lua/ltests.c lib/lua/lzio.c lib/lua/lfunc.c lib/lua/ldump.c lib/pcre2/src/pcre2_substitute.c lib/pcre2/src/pcre2_convert.c lib/pcre2/src/pcre2_dfa_match.c lib/pcre2/src/pcre2_find_bracket.c lib/pcre2/src/pcre2_auto_possess.c lib/pcre2/src/pcre2_substring.c lib/pcre2/src/pcre2_match_data.c lib/pcre2/src/pcre2_xclass.c lib/pcre2/src/pcre2_study.c lib/pcre2/src/pcre2_ucd.c lib/pcre2/src/pcre2_maketables.c lib/pcre2/src/pcre2_compile.c lib/pcre2/src/pcre2_match.c lib/pcre2/src/pcre2_context.c lib/pcre2/src/pcre2_string_utils.c lib/pcre2/src/pcre2_tables.c lib/pcre2/src/pcre2_serialize.c lib/pcre2/src/pcre2_ord2utf.c lib/pcre2/src/pcre2_error.c lib/pcre2/src/pcre2_config.c lib/pcre2/src/pcre2_chartables.c lib/pcre2/src/pcre2_newline.c lib/pcre2/src/pcre2_jit_compile.c lib/pcre2/src/pcre2_fuzzsupport.c lib/pcre2/src/pcre2_valid_utf.c lib/pcre2/src/pcre2_extuni.c lib/pcre2/src/pcre2_script_run.c lib/pcre2/src/pcre2_pattern_info.c lib/freetype/src/smooth/smooth.c lib/freetype/src/truetype/truetype.c lib/freetype/src/autofit/autofit.c lib/freetype/src/pshinter/pshinter.c lib/freetype/src/psaux/psaux.c lib/freetype/src/psnames/psnames.c lib/freetype/src/sfnt/sfnt.c lib/freetype/src/base/ftsystem.c lib/freetype/src/base/ftinit.c lib/freetype/src/base/ftdebug.c lib/freetype/src/base/ftbase.c lib/freetype/src/base/ftbbox.c lib/freetype/src/base/ftglyph.c lib/freetype/src/base/ftbdf.c lib/freetype/src/base/ftbitmap.c lib/freetype/src/base/ftcid.c lib/freetype/src/base/ftfstype.c lib/freetype/src/base/ftgasp.c lib/freetype/src/base/ftgxval.c lib/freetype/src/base/ftmm.c lib/freetype/src/base/ftotval.c lib/freetype/src/base/ftpatent.c lib/freetype/src/base/ftpfr.c lib/freetype/src/base/ftstroke.c lib/freetype/src/base/ftsynth.c lib/freetype/src/base/fttype1.c lib/freetype/src/base/ftwinfnt.c lib/freetype/src/type1/type1.c lib/freetype/src/cff/cff.c lib/freetype/src/pfr/pfr.c lib/freetype/src/cid/type1cid.c lib/freetype/src/winfonts/winfnt.c lib/freetype/src/type42/type42.c lib/freetype/src/pcf/pcf.c lib/freetype/src/bdf/bdf.c lib/freetype/src/raster/raster.c lib/freetype/src/sdf/sdf.c lib/freetype/src/gzip/ftgzip.c lib/freetype/src/lzw/ftlzw.c"
LLFLAGS="-Ilib/pcre2/src -DFT2_BUILD_LIBRARY -Ilib/freetype/include -DHAVE_CONFIG_H -DPCRE2_CODE_UNIT_WIDTH=8 -O3"
cp -f lib/pcre2/src/config.h.generic lib/pcre2/src/config.h
cp -f lib/pcre2/src/pcre2.h.generic lib/pcre2/src/pcre2.h
cp -f lib/pcre2/src/pcre2_chartables.c.dist lib/pcre2/src/pcre2_chartables.c
if [ ! -f $LNAME ]; then
  echo "Building $LNAME... (Can take a moment, but only needs to be done once)"
  $CC -c $LLFLAGS $LLSRCS
  $AR -r -s $LNAME *.o
  rm -f *.o
fi

# Main executable
FLAGS="$FLAGS $@ -Ilib/freetype/include -Ilib/dmon -Ilib/lua -Ilib/pcre2/src -Isrc -O3 -fno-strict-aliasing -DPCRE2_STATIC -L. -lm  -llite -static-libgcc `$SDL_CONFIG --cflags` `$SDL_CONFIG --libs` -lpthread"
SRCS="src/*.c src/api/*.c"
if [[ $OSTYPE == 'darwin'* ]]; then
  FLAGS=$FLAGS -DLITE_USE_SDL_RENDERER -Framework CoreServices -Framework Foundation
  SRCS=$SRCS src/*.m
fi

echo "Building $BIN..."
$CC $SRCS -o $BIN $FLAGS
echo "Done."
