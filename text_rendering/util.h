#ifndef _UTIL_H
#define _UTIL_H


#define ERROR(expr, ret, ...) if (expr) { __VA_ARGS__; return ret; }


void * emalloc(unsigned long int size);
void * ecalloc(unsigned long int nmemb, unsigned long int size);
void efree(void *ptr);

void map_file(const unsigned char **str, int *size, const char *path);
void dump_file(const char *path, char **buf, int *buf_len);

void print_byte(unsigned char byte);

#endif
