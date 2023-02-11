#define _POSIX_C_SOURCE 200809l
#define _GNU_SOURCE

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <search.h>

#define CACHE_SIZE 512

static struct hsearch_data hash_table;
struct data {
	unsigned int glyph;
	unsigned int w, h, u, v;
};
static struct data cache_array[CACHE_SIZE] = {0};

// bitmap size is aligned to word
#define _BSIZE (CACHE_SIZE+0x3f)&(~0x3f)
static uint64_t bitmap[_BSIZE] = {0};

// bitmap operations
#define B_RESET() memset(bitmap, 0, _BSIZE*sizeof(uint64_t))
#define B_SET(x)  bitmap[(x)/_BSIZE] = 1<<((x)%_BSIZE)
#define B_TEST(x) (bitmap[(x)/_BSIZE]&(1<<((x)%_BSIZE)))

// reset the bitmap every n cycles
#define NCYCLES (CACHE_SIZE/2)
static int cycles = 0;


void cache_init()
{
	hcreate_r(CACHE_SIZE, &hash_table);
}


void cache_destroy()
{
	hdestroy_r(&hash_table);
}


// d->glyph already contains the right glyph 
struct data * cache_get(uint32_t glyph)
{
	static char gstr[5] = {0};
	static ENTRY e, *r;
	memcpy(gstr, &glyph, 4);
	e.data = gstr;
	hsearch_r(e, FIND, &r, &hash_table);
	
	// miss
	if (!r)
		return NULL;
	
	// hit
	cycles = (cycles+1)%NCYCLES;
	if (!cycles) B_RESET();
	B_SET((struct data *)(r->data)-cache_array);
	return (struct data *)(r->data);
}


int cache_insert(struct data *d)
{
	struct data *spot = NULL;
	uint32_t x = 0;
	for (; x < CACHE_SIZE; x++)
		if (!B_TEST(x))
			break;
}
