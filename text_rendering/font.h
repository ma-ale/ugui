#ifndef _FONT_H
#define _FONT_H


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

struct font_atlas * font_init(void);
int font_load(struct font_atlas *atlas, const char *path);
int font_free(struct font_atlas *atlas);
const struct font_glyph * font_get_glyph_texture(struct font_atlas *atlas, unsigned int code);
void font_dump(const struct font_atlas *atlas, const char *path);

#endif
