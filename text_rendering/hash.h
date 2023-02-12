#ifndef _HASH_H
#define _HASH_H

struct hm_entry {
	unsigned long code;
	void *data;
};


struct hm_ref {
	unsigned int items, size;
	struct hm_entry bucket[];
};


struct hm_ref * hm_create(unsigned int size);
void hm_destroy(struct hm_ref *hm);
struct hm_entry * hm_search(struct hm_ref *hm, unsigned int code);
struct hm_entry * hm_insert(struct hm_ref *hm, struct hm_entry *entry);

#endif
