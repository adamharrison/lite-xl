# Lite XL - Simplified

A lightweight text editor written in Lua, adapted from [lite-xl].

Intended to be nearly-fully compatible with Lite XL, from the perspective of Lua, while
massively simplifying the build system.

## Supporting Libraries

Supporting libraries are now git submodules. These must be pulled in with: 
`git submodule update --remote --init` after cloning the repository.

SDL2 should be installed as normal on Mac and Linux, or under msys. (You can use your
package manager).

## Building

**On Windows, if building using cmd.exe**, you should place `SDLmain.lib`, `SDL.lib`,
`SDL.dll` into the main folder project directory, before running a build. You can retrieve
these [here](https://www.libsdl.org/release/SDL2-devel-2.0.16-VC.zip). They're located under
lib/x64.

**To build**, simply run `build.cmd`; this should function on Mac, Windows and Linux.
**If you're running in `msys`**; you will have to type `bash build.cmd` to properly
initiate the build.

## Licenses

This project is free software; you can redistribute it and/or modify it under
the terms of the MIT license. Dependencies are licensed under various open
source licenses.  See [LICENSE] for details.

[lite-xl]:                    https://github.com/lite-xl/lite-xl
[LICENSE]:                    LICENSE
