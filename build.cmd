@echo off

IF NOT DEFINED LNAME SET LNAME=liblite.lib
IF NOT DEFINED BIN SET BIN=lite-xl.exe
IF NOT DEFINED CC SET CC=gcc
IF NOT DEFINED AR SET AR=ar

SET LLSRCS=libs/lua/ltable.c libs/lua/liolib.c libs/lua/lmem.c libs/lua/loslib.c libs/lua/ldebug.c libs/lua/ltm.c libs/lua/loadlib.c libs/lua/linit.c libs/lua/lmathlib.c libs/lua/lctype.c libs/lua/lstate.c libs/lua/lopcodes.c libs/lua/lstrlib.c libs/lua/lgc.c libs/lua/llex.c libs/lua/lparser.c libs/lua/lbaselib.c libs/lua/ldblib.c libs/lua/ltablib.c libs/lua/ldo.c libs/lua/lbitlib.c libs/lua/lstring.c libs/lua/lauxlib.c libs/lua/lobject.c libs/lua/lvm.c libs/lua/lcode.c libs/lua/lundump.c libs/lua/lcorolib.c libs/lua/lapi.c libs/lua/ltests.c libs/lua/lzio.c libs/lua/lfunc.c libs/lua/ldump.c libs/pcre2/src/pcre2_substitute.c libs/pcre2/src/pcre2_convert.c libs/pcre2/src/pcre2_dfa_match.c libs/pcre2/src/pcre2_find_bracket.c libs/pcre2/src/pcre2_auto_possess.c libs/pcre2/src/pcre2_substring.c libs/pcre2/src/pcre2_match_data.c libs/pcre2/src/pcre2_xclass.c libs/pcre2/src/pcre2_study.c libs/pcre2/src/pcre2_ucd.c libs/pcre2/src/pcre2_maketables.c libs/pcre2/src/pcre2_compile.c libs/pcre2/src/pcre2_match.c libs/pcre2/src/pcre2_context.c libs/pcre2/src/pcre2_string_utils.c libs/pcre2/src/pcre2_tables.c libs/pcre2/src/pcre2_serialize.c libs/pcre2/src/pcre2_ord2utf.c libs/pcre2/src/pcre2_error.c libs/pcre2/src/pcre2_config.c libs/pcre2/src/pcre2_chartables.c libs/pcre2/src/pcre2_newline.c libs/pcre2/src/pcre2_jit_compile.c libs/pcre2/src/pcre2_fuzzsupport.c libs/pcre2/src/pcre2_valid_utf.c libs/pcre2/src/pcre2_extuni.c libs/pcre2/src/pcre2_script_run.c libs/pcre2/src/pcre2_pattern_info.c libs/freetype/src/smooth/smooth.c libs/freetype/src/truetype/truetype.c libs/freetype/src/autofit/autofit.c libs/freetype/src/pshinter/pshinter.c libs/freetype/src/psaux/psaux.c libs/freetype/src/psnames/psnames.c libs/freetype/src/sfnt/sfnt.c libs/freetype/src/base/ftsystem.c libs/freetype/src/base/ftinit.c libs/freetype/src/base/ftdebug.c libs/freetype/src/base/ftbase.c libs/freetype/src/base/ftbbox.c libs/freetype/src/base/ftglyph.c libs/freetype/src/base/ftbdf.c libs/freetype/src/base/ftbitmap.c libs/freetype/src/base/ftcid.c libs/freetype/src/base/ftfstype.c libs/freetype/src/base/ftgasp.c libs/freetype/src/base/ftgxval.c libs/freetype/src/base/ftmm.c libs/freetype/src/base/ftotval.c libs/freetype/src/base/ftpatent.c libs/freetype/src/base/ftpfr.c libs/freetype/src/base/ftstroke.c libs/freetype/src/base/ftsynth.c libs/freetype/src/base/fttype1.c libs/freetype/src/base/ftwinfnt.c libs/freetype/src/type1/type1.c libs/freetype/src/cff/cff.c libs/freetype/src/pfr/pfr.c libs/freetype/src/cid/type1cid.c libs/freetype/src/winfonts/winfnt.c libs/freetype/src/type42/type42.c libs/freetype/src/pcf/pcf.c libs/freetype/src/bdf/bdf.c libs/freetype/src/raster/raster.c libs/freetype/src/sdf/sdf.c libs/freetype/src/gzip/ftgzip.c libs/freetype/src/lzw/ftlzw.c
SET LLFLAGS=-Ilibs/pcre2/src -DFT2_BUILD_LIBRARY -Ilibs/freetype/include -DHAVE_CONFIG_H -DPCRE2_CODE_UNIT_WIDTH=8 -O3
COPY libs\pcre2\src\config.h.generic libs\pcre2\src\config.h > nul
COPY libs\pcre2\src\pcre2.h.generic libs\pcre2\src\pcre2.h > nul
COPY libs\pcre2\src\pcre2_chartables.c.dist libs\pcre2\src\pcre2_chartables.c > nul
IF EXIST %LNAME% GOTO :LITE

; Supporting library
ECHO Building %LNAME%. Can take a moment, but only needs to be done once.
CALL %CC% -c %LLFLAGS% %LLSRCS%
CALL %AR% -r -s %LNAME% *.o
DEL *.

; Main executable
:LITE
SET FLAGS=-Ilibs/freetype/include -Ilibs/lua -Ilibs/pcre2/src -Isrc -O3 -fno-strict-aliasing -DPCRE2_STATIC -L. -lm  -llite -static-libgcc -lSDL2main -lSDL2 -mwindows -Dmain=SDL_main -Ilibs/SDL/include
SET SRCS=src/*.c src/api/*.c
ECHO Building %BIN%...
CALL %CC% %SRCS% -o %BIN% %FLAGS%
ECHO Done.
