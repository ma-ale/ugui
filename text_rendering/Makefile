CC      = gcc
LDFLAGS = -lm -lgrapheme -lSDL2 -lGLEW -lGL
CFLAGS  = -g -Wall -Wextra -pedantic

.PHONY: clean all
all: test

font.o: font.c font.h stb_truetype.h stb_image_write.h util.h \
 generic_cache.h hash.h
hash.o: hash.c hash.h util.h
main.o: main.c ren.h util.h
ren.o: ren.c util.h font.h ren.h stack.h
util.o: util.c util.h
test:  font.o hash.o main.o ren.o util.o
	${CC} ${LDFLAGS} -o test  font.o hash.o main.o ren.o util.o
clean: 
	rm -f test  font.o hash.o main.o ren.o util.o
