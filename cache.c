// LRU cache:
/*
 * The cache uses a pool (array) containing all the elements and a hash table
 * associating the position in the pool with the element id
 */

#include <stdlib.h>
#include <string.h>

#include "ugui.h"

// To have less collisions TABLE_SIZE has to be larger than the cache size
#define CACHE_SIZE    265
#define TABLE_SIZE    (CACHE_SIZE * 1.5f)
#define CACHE_NCYCLES (CACHE_SIZE * 2 / 3)
#define CACHE_BSIZE   (((CACHE_SIZE + 0x3f) & (~0x3f)) >> 6)
#define CACHE_BRESET(b)                                                             \
	for (int i = 0; i < CACHE_BSIZE; b[i++] = 0)                                \
		;
#define CACHE_BSET(b, x)  b[(x) >> 6] |= (uint64_t)1 << ((x)&63)
#define CACHE_BTEST(b, x) (b[(x) >> 6] & ((uint64_t)1 << ((x)&63)))

/* Hash Table Implementation ----------------------------------------------------- */

#define HASH_MAXSIZE 4096

// hash table (id -> cache index)
typedef struct {
	UgId id;
	uint32_t index;
} IdElem;

typedef struct _IdTable {
	uint32_t items, size, exp;
	IdElem   bucket[];
} IdTable;

IdTable *table_create(uint32_t size)
{
	if (!size || size > HASH_MAXSIZE) {
		return NULL;
	}
	/* round to the greater power of two */
	/* FIXME: check for intger overflow here */
	uint32_t exp = 32 - __builtin_clz(size - 1);
	size         = 1 << (exp);
	/* FIXME: check for intger overflow here */
	IdTable *ht  = malloc(sizeof(IdTable) + sizeof(IdElem) * size);
	if (ht) {
		ht->items = 0;
		ht->size  = size;
		memset(ht->bucket, 0, sizeof(IdTable) * size);
	}
	return ht;
}

void table_destroy(IdTable *ht)
{
	if (ht) {
		free(ht);
	}
}

// Find and return the element by pointer
IdElem *table_search(IdTable *ht, UgId id)
{
	if (!ht) {
		return NULL;
	}

	// In this case id is the hash
	uint32_t idx = id % ht->size;

	for (uint32_t x = 0, i; x < ht->size; x++) {
		i = (idx + x) % ht->size;
		if (ht->bucket[i].id == 0 || ht->bucket[i].id == id) {
			return &(ht->bucket[i]);
		}
	}
	return NULL;
}

// FIXME: this simply overrides the found item
IdElem *table_insert(IdTable *ht, IdElem entry)
{
	IdElem *r = table_search(ht, entry.id);
	if (r != NULL) {
		if (r->id != 0) {
			ht->items++;
		}
		*r = entry;
	}
	return r;
}

IdElem *table_remove(IdTable *ht, UgId id)
{
	if (!ht) {
		return NULL;
	}
	IdElem *r = table_search(ht, id);
	if (r) {
		r->id = 0;
	}
	return r;
}

/* Cache Implementation ---------------------------------------------------------- */

// Every CACHE_CYCLES operations mark not-present the unused elements
#define CACHE_CYCLE(c)                                                              \
	do {                                                                        \
		if (++(c->cycles) > CACHE_NCYCLES) {                                \
			for (int i = 0; i < CACHE_BSIZE; i++) {                     \
				c->present[i] &= c->used[i];                        \
				c->used[i] = 0;                                     \
			}                                                           \
			c->cycles = 0;                                              \
		}                                                                   \
	} while (0)

/* FIXME: check for allocation errors */
UgElemCache ug_cache_init(void)
{
	IdTable  *t = table_create(TABLE_SIZE);
	UgElem   *a = malloc(sizeof(UgElem) * CACHE_SIZE);
	uint64_t *p = malloc(sizeof(uint64_t) * CACHE_BSIZE);
	uint64_t *u = malloc(sizeof(uint64_t) * CACHE_BSIZE);
	CACHE_BRESET(p);
	CACHE_BRESET(u);
	return (UgElemCache) {.table = t, .array = a, .present = p, .used = u, 0};
}

void ug_cache_free(UgElemCache *cache)
{
	if (cache) {
		table_destroy(cache->table);
		free(cache->array);
		free(cache->present);
		free(cache->used);
	}
}

UgElem *ug_cache_search(UgElemCache *cache, UgId id)
{
	if (!cache) {
		return NULL;
	}
	IdElem *r;
	r = table_search(cache->table, id);
	/* MISS */
	if (!r || id != r->id) {
		return NULL;
	}
	/* MISS, the data is not valid (not present) */
	if (!CACHE_BTEST(cache->present, r->index)) {
		return NULL;
	}
	/* HIT, set as recently used */
	CACHE_BSET(cache->used, r->index);
	return (&cache->array[r->index]);
}

/* Look for a free spot in the present bitmap and return its index */
/* If there is no free space left then just return the first position */
int ug_cache_get_free_spot(UgElemCache *cache)
{
	if (!cache) {
		return -1;
	}
	int x = 0;
	for (int b = 0; b < CACHE_BSIZE; b++) {
		if (cache->present[b] == 0) {
			x = 64;
		} else {
			x = __builtin_clzll(cache->present[b]);
		}
		x = 64 - x;
		if (!CACHE_BTEST(cache->present, x + 64 * b)) {
			return x + 64 * b;
		}
	}
	return 0;
}

UgElem *ug_cache_insert_at(UgElemCache *cache, const UgElem *g, uint32_t index)
{
	if (!cache) {
		return NULL;
	}
	UgElem *spot = NULL;

	/* Set used and present */
	CACHE_BSET(cache->present, index);
	CACHE_BSET(cache->used, index);
	CACHE_CYCLE(cache);
	spot     = &(cache->array[index]);
	*spot    = *g;
	IdElem e = {.id = g->id, .index = index};
	if (!table_insert(cache->table, e)) {
		return NULL;
	}
	return spot;
}

// Insert an element in the cache
UgElem *ug_cache_insert(UgElemCache *cache, const UgElem *g, uint32_t *index)
{
	*index = ug_cache_get_free_spot(cache);
	return ug_cache_insert_at(cache, g, *index);
}

