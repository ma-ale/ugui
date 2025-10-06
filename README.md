# UGUI

Immediate mode ui library for C3. (Name subject to change).

This repo contains the library itself, a renderer based on SLD3's new GPU API and a test program.
The library is located at `lib/ugui.c3l`.

The layout algorithm is similar to flexbox. A graphical description of the layout algorithm is located in the [LAYOUT](lib/ugui.c3l/LAYOUT) file. The structure of the library is (was) described in the [ARCHITECTURE](ARCHITECTURE.md) file, most of it is now irrelevant and will be updated in the future.

## Dependencies

* `shaderc` for `glslc`
* `c3c` version >0.7.5
* `SDL3`
* A C compiler

## Building

1. Clone the repo and all dependencies
```sh
git clone https://github.com/ma-ale/ugui
cd ugui
git submodule update --recursive --init
```

2. Build libgrapheme
```sh
cd lib/grapheme.c3l
make
cd ../..
```

3. Compile libschrift
```sh
cd lib/schrift.c3l
make
cd ../..
```

4. Build and run the project
```sh
make && build/ugui
```