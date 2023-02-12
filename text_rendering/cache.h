#ifndef _CACHE_H
#define _CACHE_H

void cache_init(void);
void cache_destroy(void);
struct font_glyph * cache_get(unsigned int code);
int cache_insert(struct font_glyph *g);


#endif
