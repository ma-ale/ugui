#ifndef _HASH_GENERIC
#define _HASH_GENERIC

#include <string.h>
#include <stdlib.h>
#include <stdint.h>


#define HASH_MAXSIZE 4096
// for fibonacci hashing, 2^{32,64}/<golden ratio>
#define HASH_RATIO32 ((uint64_t)2654435769u)
#define HASH_RATIO64 ((uint64_t)11400714819322457583u)
// salt for string hashing
#define HASH_SALT ((uint64_t)0xbabb0cac)


/* Ready-made compares */
static inline int hash_cmp_u32(uint32_t a, uint32_t b) { return a == b; }
static inline int hash_cmp_u64(uint64_t a, uint64_t b) { return a == b; }
static inline int hash_cmp_str(const char *a, const char *b) { return strcmp(a, b) == 0; }


/* Ready-made hashes */
static inline uint32_t hash_u64(uint64_t c)
{
	return (uint64_t)((((uint64_t)c+HASH_SALT)*HASH_RATIO64)>>32);
}
static inline uint32_t hash_u32(uint32_t c)
{
	return (uint32_t)((((uint64_t)c<<31)*HASH_RATIO64)>>32);
}
static inline uint32_t hash_str(const char *s)
{
	uint32_t h = HASH_SALT;
	const uint8_t *v = (const uint8_t *)(s);
	for (int x = *s; x; x--) {
		h += v[x-1];
		h += h << 10;
		h ^= h >> 6;
	}
	h += h << 3;
  	h ^= h >> 11;
  	h += h << 15;
	return h;
}


#define HASH_DECL(htname, codetype, datatype, hashfn, cmpfn)                   \
struct htname##_entry {                                                        \
	codetype code;                                                         \
	datatype data;                                                         \
};                                                                             \
\
struct htname##_ref {                                                          \
	uint32_t items, size, exp;                                             \
	struct htname##_entry bucket[];                                        \
};                                                                             \
\
\
struct htname##_ref * htname##_create(uint32_t size)                           \
{                                                                              \
	if (!size || size > HASH_MAXSIZE)                                      \
		return NULL;                                                   \
	/* round to the greater power of two */                                \
	/* FIXME: check for intger overflow here */                            \
	uint32_t exp = 32-__builtin_clz(size-1);                               \
	size = 1<<(exp);                                                       \
	/* FIXME: check for intger overflow here */                            \
	struct htname##_ref *ht = malloc(sizeof(struct htname##_ref)+sizeof(struct htname##_entry)*size); \
	if (ht) {                                                              \
		ht->items = 0;                                                 \
		ht->size  = size;                                              \
		ht->exp   = exp;                                               \
		memset(ht->bucket, 0, sizeof(struct htname##_entry)*size);     \
	}                                                                      \
	return ht;                                                             \
}                                                                              \
\
\
void htname##_destroy(struct htname##_ref *ht)                                 \
{                                                                              \
	if (ht) free(ht);                                                      \
}                                                                              \
\
\
static uint32_t htname##_lookup(struct htname##_ref *ht, uint32_t hash, uint32_t idx) \
{                                                                              \
	if (!ht) return 0;                                                     \
	uint32_t mask = ht->size-1;                                            \
	uint32_t step = (hash >> (32 - ht->exp)) | 1;                          \
	return (idx + step) & mask;                                            \
}                                                                              \
\
\
/* Find and return the element by code */                                      \
struct htname##_entry * htname##_search(struct htname##_ref *ht, codetype code)\
{                                                                              \
	if (!ht) return NULL;                                                  \
	uint32_t h = hashfn(code);                                             \
	for (uint32_t i=h, x=0; ; x++) {                                       \
		i = htname##_lookup(ht, h, i);                                 \
		if (x > (ht->size<<1)   ||                                     \
		    !ht->bucket[i].code ||                                     \
		    cmpfn(ht->bucket[i].code, code)                            \
		) {                                                            \
			return &(ht->bucket[i]);                               \
		}                                                              \
	}                                                                      \
	return NULL;                                                           \
}                                                                              \
\
\
/* FIXME: this simply overrides the found item */                              \
struct htname##_entry * htname##_insert(struct htname##_ref *ht, struct htname##_entry *entry) \
{                                                                              \
	struct htname##_entry *r = htname##_search(ht, entry->code);           \
	if (r) {                                                               \
		if (!r->code)                                                  \
			ht->items++;                                           \
		*r = *entry;                                                   \
	}                                                                      \
	return r;                                                              \
}                                                                              \
\
\
struct htname##_ref * htname##_remove(struct htname##_ref *ht, codetype code)  \
{                                                                              \
	if (!ht) return NULL;                                                  \
	struct htname##_entry *r = htname##_search(ht, code);                  \
	if (r) r->code = 0;                                                    \
	return r;                                                              \
}                                                                              \

#endif
