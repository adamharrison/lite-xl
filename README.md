# Lite XL - Simplified

A lightweight text editor written in Lua, adapted from [lite-xl]. Makes it easier to build
on different platforms if you're having trouble with meson.

## Supporting Libraries

The 4 supporting libraries of lite are now git submodules. These **must** be pulled in with: 
`git submodule update --remote --init` after cloning the repository.

SDL2 should be installed as normal on Mac and Linux, or under msys. (You can use your
package manager).

## Building

**On Windows, if building using cmd.exe**, you should place `SDLmain.lib`, `SDL.lib`,
`SDL.dll` into the main folder project directory, before running a build. You can retrieve
these [here](https://www.libsdl.org/release/SDL2-devel-2.0.16-VC.zip). They're located under
lib/x64.

**To build**, simply run `build.sh`; this should function on Mac, Linux and MSYS command line.
**If you're running on windows on the command line; you should use `build.cmd`.

## Cross Compiling

From Linux, to compile a windows executable, all you need to do is:

`CC=i686-w64-mingw32-gcc AR=i686-w64-mingw32-gcc-ar SDL_CONFIG=/usr/local/cross-tools/i686-w64-mingw32/bin/sdl2-config ./build.cmd`

As long as you've compiled SDL with your mingw compiler. You can compile SDL by going to the
lib folder, and running:

`CC=i686-w64-mingw32-gcc ./configure --host=i686-w64-mingw32 && make && sudo make install`

## Licenses

This project is free software; you can redistribute it and/or modify it under
the terms of the MIT license. Dependencies are licensed under various open
source licenses.  See [LICENSE] for details.

[lite-xl]:                    https://github.com/lite-xl/lite-xl
[LICENSE]:                    LICENSE
