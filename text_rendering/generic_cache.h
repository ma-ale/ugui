#ifndef CACHE_GENERIC_H
#define CACHE_GENERIC_H


#include "generic_hash.h"

#define CACHE_SIZE 512
#define CACHE_NCYCLES (CACHE_SIZE*2/3)
#define CACHE_BSIZE (((CACHE_SIZE+0x3f)&(~0x3f))>>6)
#define CACHE_BRESET(b)   for (int i = 0; i < CACHE_BSIZE; b[i++] = 0);
#define CACHE_BSET(b, x)  b[(x)>>6] |= (uint64_t)1<<((x)&63)
#define CACHE_BTEST(b, x) (b[(x)>>6]&((uint64_t)1<<((x)&63)))

// FIXME: this cache implementation is not really generic since it expects an unsigned
//        as the code and not a generic type


#define CACHE_USED(c, x)                                                       \
{                                                                              \
	if (++(c->cycles) > CACHE_NCYCLES) {                                   \
		for (int i = 0; i < CACHE_BSIZE; i++) {                        \
			c->present[i] &= c->used[i];                           \
			c->used[i] = 0;                                        \
		}                                                              \
		c->cycles = 0;                                                 \
	}                                                                      \
	CACHE_BSET(c->used, x);                                                \
}


#define CACHE_DECL(name, type, hashfn, cmpfn)                                  \
HASH_DECL(name##table, uint32_t, uint32_t, hashfn, cmpfn)                      \
struct name {                                                                  \
	struct name##table_ref *table;                                         \
	type *array;                                                           \
	uint64_t *present, *used;                                              \
	int cycles;                                                            \
};                                                                             \
\
\
/* FIXME: check for allocation errors */                                       \
struct name name##_init(void)                                                  \
{                                                                              \
	struct name##table_ref *t = name##table_create(CACHE_SIZE);            \
	type *a = malloc(sizeof(type)*CACHE_SIZE);                             \
	uint64_t *p = malloc(sizeof(uint64_t)*CACHE_BSIZE);                    \
	uint64_t *u = malloc(sizeof(uint64_t)*CACHE_BSIZE);                    \
	CACHE_BRESET(p);                                                       \
	CACHE_BRESET(u);                                                       \
	return (struct name){.table=t, .array=a, .present=p, .used=u, 0};      \
}                                                                              \
\
\
void name##_free(struct name *cache)                                           \
{                                                                              \
	if (cache) {                                                           \
		name##table_destroy(cache->table);                             \
		free(cache->array);                                            \
		free(cache->present);                                          \
		free(cache->used);                                             \
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
	/* MISS, the data is not valid (not present) */                        \
	if (!CACHE_BTEST(cache->present, r->data))                             \
		return NULL;                                                   \
	/* HIT, set as recently used */                                        \
	CACHE_USED(cache, r->data);                                            \
	return (&cache->array[r->data]);                                       \
}                                                                              \
\
\
/* Look for a free spot in the present bitmap and return its index */          \
int name##_get(struct name *cache)                                             \
{                                                                              \
	if (!cache) return -1;                                                 \
	int x = 0;                                                             \
	for (int b = 0; b < CACHE_BSIZE; b++) {                                \
		if (cache->present[b] == 0) x = 64;                            \
		else x = __builtin_clzll(cache->present[b]);                   \
		x = 64-x;                                                      \
		if (!CACHE_BTEST(cache->present, x+64*b))                      \
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
	if (x < 0 || CACHE_BTEST(cache->present, x))                           \
		return NULL;                                                   \
	/* Set used and present */                                             \
	CACHE_USED(cache, x)                                                   \
	CACHE_BSET(cache->present, x);                                         \
	CACHE_BSET(cache->used, x);                                            \
	spot = &(cache->array[x]);                                             \
	*spot = *g;                                                            \
	struct name##table_entry e = { .code = code, .data = x};               \
	if (!name##table_insert(cache->table, &e))                             \
		return NULL;                                                   \
	return spot;                                                           \
}                                                                              \


#endif
