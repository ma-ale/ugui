CC      = gcc
LDFLAGS = -lm -lgrapheme -lSDL2 -lGLEW -lGL
CFLAGS  = -g -Wall -Wextra -pedantic

.PHONY: clean all
all: test

cache.o: cache.c cache.h hash.h font.h util.h
font.o: font.c font.h stb_truetype.h stb_image_write.h util.h cache.h
hash.o: hash.c hash.h util.h
main.o: main.c ren.h util.h
ren.o: ren.c util.h font.h ren.h stack.h
util.o: util.c util.h
test:  cache.o font.o hash.o main.o ren.o util.o
	${CC} ${LDFLAGS} -o test  cache.o font.o hash.o main.o ren.o util.o
clean: 
	rm -f test  cache.o font.o hash.o main.o ren.o util.o
