CFLAGS = -Wall -Wextra -pedantic -std=c11 -g -Iraylib/src
CC = gcc
LDFLAGS = -Lraylib/src -lm

all: ugui

raylib/src/libraylib.a: raylib/src/Makefile
	cd raylib/src; $(MAKE) PLATFORM=PLATFORM_DESKTOP

ugui: ugui.o vectree.o raylib/src/libraylib.a

ugui.o: ugui.c ugui.h

vectree.o: vectree.c ugui.h
