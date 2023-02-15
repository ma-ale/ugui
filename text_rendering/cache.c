#define _POSIX_C_SOURCE 200809l
#define _GNU_SOURCE

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include "cache.h"
#include "hash.h"
#include "font.h"
#include "util.h"


static struct hm_ref *hash_table;
static struct font_glyph cache_array[CACHE_SIZE] = {0};

// bitmap size is aligned to word
#define _BSIZE ((CACHE_SIZE+0x3f)&(~0x3f))
static uint64_t bitmap[_BSIZE] = {0};

// bitmap operations
#define B_RESET() memset(bitmap, 0, _BSIZE*sizeof(uint64_t))
#define B_SET(x)  bitmap[(x)/_BSIZE] |= 1<<((x)%_BSIZE)
#define B_TEST(x) (bitmap[(x)/_BSIZE]&(1<<((x)%_BSIZE)))

// reset the bitmap every n cycles
#define NCYCLES (CACHE_SIZE/2)
static int cycles = 0;


static inline void set_bit(unsigned int x)
{
//	printf("cycles: %d, set: %d\n", cycles, x);
	cycles = (cycles+1)%NCYCLES;
	if (!cycles) B_RESET();
	B_SET(x);
}


void cache_init(void)
{
	hash_table = hm_create(CACHE_SIZE);
}


void cache_destroy(void)
{
	hm_destroy(hash_table);
}


const struct font_glyph * cache_search(unsigned int code)
{
	struct hm_entry *r = hm_search(hash_table, code);

	// miss
	if (!r)
		return NULL;

	// hit
	set_bit((struct font_glyph *)(r->data)-cache_array);
	return (struct font_glyph *)(r->data);
}


// return the first free spot into the cache
unsigned int cache_get(void)
{
	uint32_t x = 0;
	// find an open spot in the cache
	// TODO: use __builtin_clz to speed this up
	for (; x < CACHE_SIZE; x++) {
		if (!B_TEST(x))
			break;
	}
	return x;
}


// inserts the font glyph into the cache
const struct font_glyph * cache_insert(const struct font_glyph *g, unsigned int x)
{
	struct font_glyph *spot = NULL;

	// allocation in cache failed
	if (B_TEST(x))
		return NULL;

	set_bit(x);
	spot = &cache_array[x];
	*spot = *g;

/*
	for (int i = 0; i < _BSIZE; i++) {
		//print_byte(bitmap[i]);
		//print_byte(bitmap[i]>>8);
		//print_byte(bitmap[i]>>16);
		//print_byte(bitmap[i]>>24);
		//print_byte(bitmap[i]>>32);
		//print_byte(bitmap[i]>>40);
		//print_byte(bitmap[i]>>48);
		//print_byte(bitmap[i]>>56);
		printf("%lx", bitmap[i]);
	}
	printf("\n");
*/

	struct hm_entry e = { .code  = g->codepoint, .data = spot};
	if (!hm_insert(hash_table, &e))
		return NULL;

	return spot;
}
