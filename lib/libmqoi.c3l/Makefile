all: thirdparty/mini-qoi/mqoi.a
	cp thirdparty/mini-qoi/mqoi.a linux-x64/libmqoi.a

thirdparty/mini-qoi/mqoi.a:
	gcc -O2 -c -o thirdparty/mini-qoi/mqoi.o thirdparty/mini-qoi/src/mini_qoi.c
	ar -rc thirdparty/mini-qoi/mqoi.a thirdparty/mini-qoi/mqoi.o
