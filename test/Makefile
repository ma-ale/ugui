CFLAGS  = -Wall -Wextra -Wpedantic -std=c11 -g
LDFLAGS = -lSDL2 -lm

test: main.c ../ugui.c ../ugui.h ../def_style.h
	gcc ${CFLAGS} -c ../ugui.c -o ugui.o
	gcc ${CFLAGS} -c main.c    -o main.o
	gcc ${LDFLAGS} main.o ugui.o -o test

clean:
	rm -f main.o ugui.o
