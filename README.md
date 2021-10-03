# Lite XL - Simplified

A lightweight text editor written in Lua, adapted from [lite-xl].

Intended to be nearly-fully compatible with Lite XL, from the perspective of Lua, while
massively slimming down the Lite XL core, rendering and build systems, without
sacrificing quality or performance.

I've also used standard git submodules to pull in the only 4 supporting libraries,
should they be necessary, freetype2, lua5.2, SDL2, and pcre2. These can be pulled in with
`git submodule update --remote --init`.

To build a copy, simply run `./build.cmd`; this should function on Mac, Windows and Linux.
If you're running in `msys`; you will have to type `bash build.cmd`.

## Licenses

This project is free software; you can redistribute it and/or modify it under
the terms of the MIT license. Dependencies are licensed under various open
source licenses.  See [LICENSE] for details.

[lite-xl]:                    https://github.com/lite-xl/lite-xl
[LICENSE]:                    LICENSE
