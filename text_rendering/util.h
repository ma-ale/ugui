#ifndef _UTIL_H
#define _UTIL_H

#include <stdio.h>


void * emalloc(unsigned long int size);
void * ecalloc(unsigned long int nmemb, unsigned long int size);
void * erealloc(void *ptr, unsigned long int size);
void efree(void *ptr);

void map_file(const unsigned char **str, int *size, const char *path);
void dump_file(const char *path, char **buf, int *buf_len);

void print_byte(unsigned char byte);

void stopwatch_start(void);
double stopwatch_get(void);

#define TIME_SEC(f)                                                            \
{                                                                              \
	stopwatch_start();                                                     \
	f;                                                                     \
	printf("\"%s\" took %f seconds", #f, stopwatch_get());                 \
}

#define TIME_MS(f)                                                             \
{                                                                              \
	stopwatch_start();                                                     \
	f;                                                                     \
	printf("\"%s\" took %f ms", #f, stopwatch_get()*1000.0f);              \
}

#endif
