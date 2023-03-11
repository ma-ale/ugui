#ifndef CACHE_GENERIC_H
#define CACHE_GENERIC_H


#include "generic_hash.h"

#define CACHE_SIZE 512
#define CACHE_NCYCLES (CACHE_SIZE/2)
#define CACHE_BSIZE (((CACHE_SIZE+0x3f)&(~0x3f))>>6)
#define CACHE_BRESET(b)   for (int i = 0; i < CACHE_BSIZE; b[i++] = 0);
#define CACHE_BSET(b, x)  b[(x)>>6] |= (uint64_t)1<<((x)%64)
#define CACHE_BTEST(b, x) (b[(x)>>6]&((uint64_t)1<<((x)%64)))

// FIXME: this cache implementation is not really generic since it expects an unsigned
//        as the code and not a generic type

#define CACHE_SET(c, x)                                                        \
{                                                                              \
	c->cycles = (c->cycles+1)%CACHE_NCYCLES;                               \
	if (!c->cycles) CACHE_BRESET(c->bitmap);                               \
	CACHE_BSET(c->bitmap, x);                                              \
}


#define CACHE_DECL(name, type, hashfn, cmpfn)                                  \
HASH_DECL(name##table, uint32_t, void *, hashfn, cmpfn)                        \
struct name {                                                                  \
	struct name##table_ref *table;                                         \
	type *array;                                                           \
	uint64_t *bitmap;                                                      \
	int cycles;                                                            \
};                                                                             \
\
\
struct name name##_init(void)                                                  \
{                                                                              \
	struct name##table_ref *t = name##table_create(CACHE_SIZE);            \
	type *a = malloc(sizeof(type)*CACHE_SIZE);                             \
	uint64_t *b = malloc(sizeof(uint64_t)*CACHE_BSIZE);                    \
	CACHE_BRESET(b);                                                       \
	return (struct name){ .table = t, .array = a, .bitmap = b, 0};         \
}                                                                              \
\
\
void name##_free(struct name *cache)                                           \
{                                                                              \
	if (cache) {                                                           \
		name##table_destroy(cache->table);                             \
		free(cache->array);                                            \
		free(cache->bitmap);                                           \
	}                                                                      \
}                                                                              \
\
\
const type * name##_search(struct name *cache, uint32_t code)                  \
{                                                                              \
	if (!cache) return NULL;                                               \
	struct name##table_entry *r;                                           \
	r = name##table_search(cache->table, code);                            \
	/* MISS */                                                             \
	if (!r || !cmpfn(code, r->code))                                       \
		return NULL;                                                   \
	/* HIT, set as recently used */                                        \
	CACHE_SET(cache, (type *)(r->data)-(cache->array));                    \
	return (const type *)(r->data);                                        \
}                                                                              \
\
\
int name##_get(struct name *cache)                                             \
{                                                                              \
	if (!cache) return -1;                                                 \
	int x = 0;                                                             \
	for (int b = 0; b < CACHE_BSIZE; b++) {                                \
		if (cache->bitmap[b] == 0) x = 64;                             \
		else x = __builtin_clzll(cache->bitmap[b]);                    \
		x = 64-x;                                                      \
		if (!CACHE_BTEST(cache->bitmap, x+64*b))                       \
			return x+64*b;                                         \
	}                                                                      \
	return 0;                                                              \
}                                                                              \
\
\
const type * name##_insert(struct name *cache, const type *g, uint32_t code, int x)\
{                                                                              \
	if (!cache) return NULL;                                               \
	type *spot = NULL;                                                     \
	/* x is the index to the cache array, it has to come from the user */  \
	/* check if the spot is free */                                        \
	if (x < 0 || CACHE_BTEST(cache->bitmap, x))                            \
		return NULL;                                                   \
	CACHE_SET(cache, x)                                                    \
	spot = &(cache->array[x]);                                             \
	*spot = *g;                                                            \
	struct name##table_entry e = { .code = code, .data = spot};            \
	if (!name##table_insert(cache->table, &e))                             \
		return NULL;                                                   \
	return spot;                                                           \
}                                                                              \


#endif
