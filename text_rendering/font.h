#ifndef _FONT_H
#define _FONT_H


/* width and height of a glyph contain the kering advance
 * (u,v)
 *   +-------------*---+ -
 *   |       ^     |   | ^
 *   |       |oy   |   | |
 *   |       v     |   | |
 *   |      .ii.   |   | |
 *   |     @@@@@@. |<->| |
 *   |    V@Mio@@o |adv| |
 *   |    :i.  V@V |   | |
 *   |      :oM@@M |   | |
 *   |    :@@@MM@M |   | |
 *   |    @@o  o@M |   | |
 *   |<->:@@.  M@M |   | |
 *   |ox  @@@o@@@@ |   | |
 *   |    :M@@V:@@.|   | v
 *   +-------------*---+ -
 *   |<------------->|
 *           w
 */
// TODO: the advance isn't unique for every pair of characters
struct font_glyph {
	unsigned int codepoint;
	unsigned int u, v;
	unsigned short int w, h, a, x, y;
};

struct font_atlas {
	unsigned int width, height;
	unsigned char *atlas;
	unsigned int glyph_max_w, glyph_max_h;
	int size;
	int file_size;
	char *file;
	void *priv;
};


struct font_atlas * font_init(void);
int font_load(struct font_atlas *atlas, const char *path, int size);
int font_free(struct font_atlas *atlas);
const struct font_glyph * font_get_glyph_texture(struct font_atlas *atlas, unsigned int code, int *updated);
void font_dump(const struct font_atlas *atlas, const char *path);

#endif
