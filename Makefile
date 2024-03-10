CFLAGS = -Wall -Wextra -pedantic -std=c11 -g -Iraylib/include
CC = gcc
LDFLAGS = -Lraylib/lib -lm

all: ugui

ugui: ugui.o vectree.o cache.o timer.o raylib/lib/libraylib.a

ugui.o: ugui.c ugui.h

vectree.o: vectree.c ugui.h

cache.o: cache.c ugui.h

timer.o: timer.c timer.h
