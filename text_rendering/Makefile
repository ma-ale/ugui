CC      = gcc
LDFLAGS = -lm -lgrapheme -lSDL2 -lGLEW -lGL
CFLAGS  = -ggdb3 -Wall -Wextra -pedantic -fno-omit-frame-pointer

.PHONY: clean all
all: test

font.o: font.c font.h stb_truetype.h stb_image_write.h util.h \
 generic_cache.h generic_hash.h
main.o: main.c ren.h util.h
ren.o: ren.c util.h font.h ren.h generic_stack.h
util.o: util.c util.h
test:  font.o main.o ren.o util.o
	${CC} ${LDFLAGS} -o test  font.o main.o ren.o util.o
clean: 
	rm -f test  font.o main.o ren.o util.o
