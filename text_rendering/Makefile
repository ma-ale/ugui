LDFLAGS = -lm -lgrapheme -lSDL2 -lGLEW -lGL
CFLAGS = -g -Wall -Wextra -pedantic
SOURCE = main.c font.c cache.c hash.c util.c ren.c
HEADER = font.h hash.h cache.h util.h ren.h

test: ${HEADER} ${SOURCE}
	gcc ${CFLAGS} ${LDFLAGS} ${SOURCE} -o test
