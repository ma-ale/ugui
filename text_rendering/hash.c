#define _POSIX_C_SOURCE 200809l
#define _DEFAULT_SOURCE

#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "hash.h"

#define MAXSIZE 4096


static unsigned int hash(unsigned int code)
{
	// identity map the ascii range
	if (code < 128) return code;
	return (uint32_t)((uint64_t)(code*2654435761)>>32);
}


struct hm_ref * hm_create(unsigned int size)
{
	if (!size || size > MAXSIZE)
		return NULL;

	// round to the greater power of two
	size = 1<<__builtin_clz(size);

	// FIXME: check for intger overflow here
	struct hm_ref *h = malloc(sizeof(struct hm_ref)+sizeof(struct hm_entry)*size);
	if (h) {
		h->items = 0;
		h->size  = size;
		memset(h->bucket, 0, sizeof(struct hm_ref)*size);
	}
	return h;
}


void hm_destroy(struct hm_ref *hm)
{
	free(hm);
}


static struct hm_entry * lookup(struct hm_ref *hm, unsigned int code)
{
	// fast modulo operation for power-of-2 size
	unsigned int mask = hm->size - 1;
	unsigned int i = hash(code);
	for (unsigned int j = 1; ; i += j++) {
		if (!hm->bucket[i&mask].code || hm->bucket[i].code == code)
			return &(hm->bucket[i&mask]);
	}
	return NULL;
}


struct hm_entry * hm_search(struct hm_ref *hm, unsigned int code)
{
	struct hm_entry *r = lookup(hm, code);
	if (r) {
		if (r->code == code)
			return r;
		return NULL;
	}
	return r;
}


struct hm_entry * hm_insert(struct hm_ref *hm, struct hm_entry *entry)
{
	struct hm_entry *r = lookup(hm, entry->code);
	if (r) *r = *entry;
	return r;
}
