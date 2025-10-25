C3FLAGS = -g

main: src/main.c3 $(wildcard lib/ugui.c3l/src/*.c3) $(wildcard lib/ugui_sdl.c3l/)
	make -C resources/shaders
	c3c build ${C3FLAGS}
