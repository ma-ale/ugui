#ifndef _FONT_H
#define _FONT_H

#define CACHE_SIZE 512

/* width and height of a glyph contain the kering advance
 * (u,v)
 *   +----------*---+ -
 *   |   .ii.   |   | ^
 *   |  @@@@@@. |<->| |
 *   | V@Mio@@o |adv| |
 *   | :i.  V@V |   | |
 *   |   :oM@@M |   | |
 *   | :@@@MM@M |   | |
 *   | @@o  o@M |   | |
 *   |:@@.  M@M |   | |
 *   | @@@o@@@@ |   | |
 *   | :M@@V:@@.|   | v
 *   +----------*---+ -
 *   |<------------->|
 *           w
 */
struct font_glyph {
	unsigned int codepoint;
	unsigned int u, v, w, h;
};


struct font_atlas;

int load_font(struct font_atlas *atlas, const char *path, int height);
int free_font(struct font_atlas *atlas);

void cache_init(void);
void cache_destroy(void);
struct font_glyph * cache_get(unsigned int code);
int cache_insert(struct font_glyph *g);


#endif
