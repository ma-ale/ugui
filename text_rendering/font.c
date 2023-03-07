#define _POSIX_C_SOURCE 200809l
#define STB_TRUETYPE_IMPLEMENTATION
#define STBTT_STATIC
#define STB_IMAGE_WRITE_IMPLEMENTATION

#include <grapheme.h>
#include <assert.h>

#include "font.h"
#include "stb_truetype.h"
#include "stb_image_write.h"
#include "util.h"

// generic cache type
#include "generic_cache.h"
CACHE_DECL(cache, struct font_glyph)


#define UTF8(c) (c&0x80)
#define BDEPTH 1
#define BORDER 4

// FIXME: as of now only monospaced fonts work correctly since no kerning information
// is stored


struct priv {
	stbtt_fontinfo stb;
	float scale;
	int baseline;
	unsigned char *bitmap;
	struct cache c;
};
#define PRIV(x) ((struct priv *)x->priv)


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
	ERROR(err == 0, -1);

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


// FIXME: when generating the sdf I only use the height, so to not encounter memory
//        errors height and width must be equal
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
	unsigned int spot = cache_get(&PRIV(atlas)->c);
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

	// FIXME: get the advance
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
	return cache_insert(&PRIV(atlas)->c, &g, g.codepoint, spot);
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
