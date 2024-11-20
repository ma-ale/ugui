module ugui;

import cache;
//#include <grapheme.h>
//#include <assert.h>

//#include "stb_truetype.h"
//#include "stbimage_write.h"

// unicode code point, different type for a different hash
def Codepoint = uint;

/* width and height of a glyph contain the kering advance
 * (u,v)
 *   +-------------*---+ -
 *   |       ^     |   | ^
 *   |       |oy   |   | |
 *   |       v     |   | |
 *   |      .ii.   |   | |
 *   |     @@@@@@. |<->| |
 *   |    V@Mio@@o |adv| |h
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
struct Glyph {
    Codepoint code;
	uint u, v;
	ushort w, h, a, x, y;
}

def GlyphCache = cache::Cache(<Codepoint, Glyph, 1024>);

// identity map the ASCII range
fn uint Codepoint.hash(Codepoint code) => code < 128 ? code : ((uint)code).hash();

struct FontAtlas {
	uint width, height;
	char* atlas;
	uint glyph_max_w, glyph_max_h;
	int size;
	int file_size;
	char *file;
	void *priv;
}


macro is_utf8(char c) => c & 0x80;
const uint BDEPTH = 1;
const uint BORDER = 4;

// FIXME: as of now only monospaced fonts look decent since no
//        kerning information is stored

struct Priv @private {
	stbtt_fontinfo stb;
	float scale;
	int baseline;
	unsigned char *bitmap;
	struct cache c;
}
//#define PRIV(x) ((struct priv *)x->priv)


struct font_atlas * font_init(void)
{
	struct font_atlas *p = emalloc(sizeof(struct font_atlas));
	memset(p, 0, sizeof(struct font_atlas));
	p->priv = emalloc(sizeof(struct priv));
	memset(p->priv, 0, sizeof(struct priv));
	PRIV(p)->c = cache_init();
	return p;
}


// loads a font into memory, storing all the ASCII characters in the atlas, each font
// atlas structure holds glyphs of a specific size in pixels
// NOTE: size includes ascend and descend (so 12 does not mean that 'A' is 12px tall)
int font_load(struct font_atlas *atlas, const char *path, int size)
{
	if (!atlas || !path)
		return -1;

	int err;

	dump_file(path, &(atlas->file), &(atlas->file_size));

	err = stbtt_InitFont(&(PRIV(atlas)->stb), (unsigned char *)atlas->file, 0);
	if (err == 0) return -1;

	int ascent, descent, linegap, baseline;
	int x0,y0,x1,y1;
	float scale;
	stbtt_GetFontVMetrics(&(PRIV(atlas)->stb), &ascent, &descent, &linegap);
	stbtt_GetFontBoundingBox(&(PRIV(atlas)->stb), &x0, &y0, &x1, &y1);
	scale = stbtt_ScaleForPixelHeight(&(PRIV(atlas)->stb), size);
	baseline = scale * -y0;
	atlas->glyph_max_w = (scale*x1) - (scale*x0);
	atlas->glyph_max_h = (baseline+scale*y1) - (baseline+scale*y0);
	atlas->atlas = emalloc(CACHE_SIZE*BDEPTH*atlas->glyph_max_w*atlas->glyph_max_h);
	memset(atlas->atlas, 0, CACHE_SIZE*BDEPTH*atlas->glyph_max_w*atlas->glyph_max_h);
	PRIV(atlas)->baseline = atlas->glyph_max_h - baseline;
	PRIV(atlas)->scale = scale;
	PRIV(atlas)->bitmap = emalloc(BDEPTH*atlas->glyph_max_w*atlas->glyph_max_h);
	// FIXME: make this a square atlas
	atlas->width  = atlas->glyph_max_w*CACHE_SIZE/4;
	atlas->height = atlas->glyph_max_h*4;
	atlas->size = size;

	// preallocate all ascii characters
	for (char c = ' '; c <= '~'; c++) {
		if (!font_get_glyph_texture(atlas, c, NULL))
			return -1;
	}

	return 0;
}


int font_free(struct font_atlas *atlas)
{
	efree(atlas->atlas);
	efree(atlas->file);
	efree(PRIV(atlas)->bitmap);
	cache_free(&PRIV(atlas)->c);
	efree(atlas->priv);
	efree(atlas);
	return 0;
}


// TODO: time and take the median of the time it takes to generate the cache and
//       the time it takes to draw the glyph
const struct font_glyph * font_get_glyph_texture(struct font_atlas *atlas, unsigned int code, int *updated)
{
	int _u = 0;
	if (!updated) updated = &_u;

	const struct font_glyph *r;
	if ((r = cache_search(&PRIV(atlas)->c, code)) != NULL) {
		*updated = 0;
		return r;
	}

	*updated = 1;
	// generate the sdf and put it into the cache
	// TODO: generate the whole block at once
	int idx = stbtt_FindGlyphIndex(&PRIV(atlas)->stb, code);
	int x0,y0,x1,y1,gw,gh,l,off_x,off_y,adv,base;
	base = atlas->glyph_max_h - PRIV(atlas)->baseline;
	stbtt_GetGlyphBitmapBoxSubpixel(
		&PRIV(atlas)->stb,
		idx,
		PRIV(atlas)->scale,
		PRIV(atlas)->scale,
		0,0,
		&x0,&y0,
		&x1, &y1);
	gw = x1 - x0;
	gh = y1 - y0;
	stbtt_GetGlyphHMetrics(&PRIV(atlas)->stb, idx, &adv, &l);
	adv *= PRIV(atlas)->scale;
	off_x = PRIV(atlas)->scale*l;
	off_y = atlas->glyph_max_h+y0;
	stbtt_MakeGlyphBitmapSubpixel(
		&PRIV(atlas)->stb,
		PRIV(atlas)->bitmap,
		atlas->glyph_max_w,
		atlas->glyph_max_h,
		atlas->glyph_max_w,
		PRIV(atlas)->scale,
		PRIV(atlas)->scale,
		0, 0,
		idx);

	// TODO: bounds check usign atlas height
	// TODO: clear spot area in the atlas before writing on it
	unsigned int spot = cache_get_free_spot(&PRIV(atlas)->c);
	unsigned int ty   = ((atlas->glyph_max_w * spot) / atlas->width) * atlas->glyph_max_h;
	unsigned int tx   = (atlas->glyph_max_w * spot) % atlas->width;
	unsigned int w    = atlas->width;

	unsigned char *a = (void *)atlas->atlas;

	//printf("max:%d %d spot:%d : %d %d %d %d\n", atlas->glyph_max_w, atlas->glyph_max_h, spot, tx, ty, off_x, off_y);

	for (int y = 0; y < gh; y++) {
		for (int x = 0; x < gw; x++) {
			int c, r;
			r = (ty+y)*w;
			c = tx+x;
			a[r+c] = PRIV(atlas)->bitmap[y*atlas->glyph_max_w+x];
		}
	}

	struct font_glyph g = {
		.codepoint = code,
		.u = tx,
		.v = ty,
		.w = gw,
		.h = gh,
		.x = off_x,
		.y = off_y-base,
		.a = adv,
	};
	return cache_insert_at(&PRIV(atlas)->c, &g, g.codepoint, spot);
}


void font_dump(const struct font_atlas *atlas, const char *path)
{
	stbi_write_png(
		path,
		atlas->width,
		atlas->height,
		BDEPTH,
		atlas->atlas,
		BDEPTH*atlas->width);
}
