#ifndef _HASH_GENERIC
#define _HASH_GENERIC

#include <string.h>
#include <stdlib.h>


#define HASH_MAXSIZE 4096
// for fibonacci hashing, 2^{32,64}/<golden ratio>
#define HASH_RATIO32 (unsigned int)2654435769u
#define HASH_RATIO64 (unsigned long long int)11400714819322457583u
// salt for string hashing
#define HASH_STRSALT 0xbabb0cac


/* Ready-made compares */
int hash_compare_u32(unsigned int a, unsigned int b) { return a == b; }
int hash_compare_u64(unsigned long long int a, unsigned long long int b) { return a == b; }
int hash_compare_str(const char *a, const char *b) { return strcmp(a, b) == 0; }


/* Ready-made hashes */
unsigned int hash_u64(unsigned long long int c)
{
	return (unsigned long long int)((unsigned long long int)(c*HASH_RATIO64)>>32);
}
unsigned int hash_u32(unsigned int c)
{
	return (unsigned int)((unsigned long long int)(c*HASH_RATIO32)>>32);
}
unsigned int hash_str(const char *s)
{
	unsigned int h = HASH_STRSALT;
	const unsigned char *v = (const unsigned char *)(s);
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


#define HASH_DECL(hashname, codetype, datatype)                                \
struct hashname##_entry {                                                      \
	codetype code;                                                         \
	datatype data;                                                         \
};                                                                             \
\
struct hashname##_ref {                                                        \
	unsigned int items, size;                                              \
	/* Function pointer to hash function */                                \
	unsigned int (*hash)(codetype);                                        \
	/* Compare codetype function, return true if equal */                  \
	int (*compare)(codetype, codetype);                                    \
	struct hashname##_entry bucket[];                                      \
};                                                                             \
\
\
struct hashname##_ref * hashname##_create(unsigned int size, unsigned int (*hash)(codetype), int (*compare)(codetype, codetype)) \
{                                                                              \
	if (!size || size > HASH_MAXSIZE)                                      \
		return NULL;                                                   \
	if (!hash || !compare)                                                 \
		return NULL;                                                   \
	/* round to the greater power of two */                                \
	/* FIXME: check for intger overflow here */                            \
	size = 1<<__builtin_clz(size);                                         \
	/* FIXME: check for intger overflow here */                            \
	struct hashname##_ref *h = malloc(sizeof(struct hashname##_ref)+sizeof(struct hashname##_entry)*size); \
	if (h) {                                                               \
		h->items   = 0;                                                \
		h->size    = size;                                             \
		h->hash    = hash;                                             \
		h->compare = compare;                                          \
		memset(h->bucket, 0, sizeof(struct hashname##_ref)*size);      \
	}                                                                      \
	return h;                                                              \
}                                                                              \
\
\
void hashname##_destroy(struct hashname##_ref *hm)                             \
{                                                                              \
	if (hm)                                                                \
		free(hm);                                                      \
}                                                                              \
\
\
static struct hashname##_entry * hashname##lookup(struct hashname##_ref *hm, codetype code) \
{                                                                              \
	if (!hm)                                                               \
		return NULL;                                                   \
	/* fast modulo operation for power-of-2 size */                        \
	unsigned int mask = hm->size - 1;                                      \
	unsigned int i = hm->hash(code);                                       \
	for (unsigned int j = 1; ; i += j++) {                                 \
		if (!hm->bucket[i&mask].code || hm->compare(hm->bucket[i].code, code)) \
			return &(hm->bucket[i&mask]);                          \
	}                                                                      \
	return NULL;                                                           \
}                                                                              \
\
\
/* Find and return the element by code */                                      \
struct hashname##_entry * hashname##_search(struct hashname##_ref *hm, codetype code) \
{                                                                              \
	if (!hm)                                                               \
		return NULL;                                                   \
	struct hashname##_entry *r = hashname##lookup(hm, code);               \
	if (r && hm->compare(r->code, code))                                   \
			return r;                                              \
	return NULL;                                                           \
}                                                                              \
\
\
/* FIXME: this simply overrides the found item */                              \
struct hashname##_entry * hashname##_insert(struct hashname##_ref *hm, struct hashname##_entry *entry) \
{                                                                              \
	struct hashname##_entry *r = hashname##lookup(hm, entry->code);        \
	if (r) {                                                               \
		if (!r->code)                                                  \
			hm->items++;                                           \
		*r = *entry;                                                   \
	}                                                                      \
	return r;                                                              \
}                                                                              \
\
\
/* returns the number of removed items */                                      \
int hashname##_remove(struct hashname##_ref *hm, codetype code)                \
{                                                                              \
	if (!hm)                                                               \
		return -1;                                                     \
	unsigned int mask = hm->size - 1;                                      \
	unsigned int s = hm->hash(code)&mask, inc = 0;                         \
	struct hashname##_entry *r;                                            \
	/* Flag for removal */                                                 \
	while (hm->items > 0 && (r = hashname##lookup(hm, code)) && r->code) { \
		/* FIXME: this cast may not work */                            \
		r->code = (codetype)(-1);                                      \
		hm->items--;                                                   \
	}                                                                      \
	/* Remove */                                                           \
	for (unsigned int i = s; i < hm->items; i++) {                         \
		if (hm->bucket[i].code == (codetype)(-1)) {                    \
			hm->bucket[i] = (struct hashname##_entry){0};          \
			inc++;                                                 \
		}                                                              \
	}                                                                      \
	return inc;                                                            \
}                                                                              \

#endif
