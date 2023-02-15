LDFLAGS = -lm -lgrapheme
CFLAGS = -g -Wall -Wextra -pedantic
SOURCE = main.c font.c cache.c hash.c util.c
HEADER = font.h hash.h cache.h util.h

test: ${HEADER} ${SOURCE}
	gcc ${CFLAGS} ${LDFLAGS} ${SOURCE} -o test
