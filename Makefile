C3FLAGS = -g

main: src/main.c3 src/renderer.c3 $(wildcard lib/ugui/src/*.c3)
	make -C resources/shaders
	c3c build ${C3FLAGS}

test_renderer: test_renderer.c3 src/renderer.c3 resources/shaders/source/*
	scripts/compile_shaders.sh
	c3c compile -g -O0 test_renderer.c3 src/renderer.c3 --libdir lib --lib sdl3 --lib ugui
