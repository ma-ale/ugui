#ifndef _CACHE_H
#define _CACHE_H

#define CACHE_SIZE 512

void cache_init(void);
void cache_destroy(void);
const struct font_glyph * cache_search(unsigned int code);
unsigned int cache_get(void);
const struct font_glyph * cache_insert(struct font_glyph *g, unsigned int idx);


#endif
