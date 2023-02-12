#define _POSIX_C_SOURCE 200809l

#include <sys/mman.h>

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <err.h>

#include "util.h"


const char *bit_rep[16] = {
    [ 0] = "0000", [ 1] = "0001", [ 2] = "0010", [ 3] = "0011",
    [ 4] = "0100", [ 5] = "0101", [ 6] = "0110", [ 7] = "0111",
    [ 8] = "1000", [ 9] = "1001", [10] = "1010", [11] = "1011",
    [12] = "1100", [13] = "1101", [14] = "1110", [15] = "1111",
};



void * emalloc(unsigned long int size)
{
	void *r = malloc(size);
	if (!r)
		err(EXIT_FAILURE, "malloc() of size %ld", size);
	return r;
}


void * ecalloc(unsigned long int nmemb, unsigned long int size)
{
	void *r = calloc(nmemb, size);
	if (!r)
		err(EXIT_FAILURE, "calloc() of size %ld, nmemb %ld", size, nmemb);
	return r;
}


void efree(void *ptr)
{
	if (ptr)
		free(ptr);
}


void map_file(const unsigned char **str, int *size, const char *path)
{
	if (!path) {
		errno = EINVAL;
		err(EXIT_FAILURE, "NULL filename");
	}
	FILE *fp = fopen(path, "r");
	if (!fp)
		err(EXIT_FAILURE, "Cannot open file %s", path);
	*size = lseek(fileno(fp), 0, SEEK_END);
	if (*size == (off_t)-1)
		err(EXIT_FAILURE, "lseek() failed");
	*str = mmap(0, *size, PROT_READ, MAP_PRIVATE, fileno(fp), 0);
	if (*str == (void*)-1)
		err(EXIT_FAILURE, "mmap() failed");
	if (fclose(fp))
		err(EXIT_FAILURE, "Error closing file");
}


void dump_file(const char *path, unsigned char **buf, int *buf_len)
{
	if (!path) {
		errno = EINVAL;
		err(EXIT_FAILURE, "NULL filename");
	}
	if (!buf) {
		errno = EINVAL;
		err(EXIT_FAILURE, "No buffer specified");
	}
	if (!buf_len) {
		errno = EINVAL;
		err(EXIT_FAILURE, "Nowhere to store buffer size");
	}
	FILE *fp = fopen(path, "r");
	if (!fp)
		err(EXIT_FAILURE, "Cannot open file %s", path);
	*buf_len = lseek(fileno(fp), 0, SEEK_END);
	if (*buf_len == (off_t)-1)
		err(EXIT_FAILURE, "lseek() failed");
	*buf = emalloc(*buf_len);
	*buf_len = fread(*buf, 1, *buf_len, fp);
	if (fclose(fp))
		err(EXIT_FAILURE, "Error closing file");
}


void print_byte(unsigned char byte)
{
	printf("%s%s", bit_rep[byte >> 4], bit_rep[byte & 0x0F]);
}
