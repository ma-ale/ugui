#define _POSIX_C_SOURCE 200809l
#define STB_TRUETYPE_IMPLEMENTATION
#define STBTT_STATIC
#define MSDF_IMPLEMENTATION

#include <grapheme.h>
#include <assert.h>

#include "font.h"
#include "msdf_c/stb_truetype.h"
#include "msdf_c/msdf.h"
#include "util.h"
#include "cache.h"


#define UTF8(c) (c&0x80)
#define BDEPTH 3
#define BORDER 4

// Generates a cached atlas of font glyphs encoded usign a signed distance field
// https://www.youtube.com/watch?v=1b5hIMqz_wM
// https://github.com/pjako/msdf_c
// this way the texture atlas for the font will be bigger but we save up the space
// needed for rendering the font in multiple sizes


struct font_atlas {
	unsigned int glyphs, width, height;
	unsigned char *atlas;

	struct {
		stbtt_fontinfo stb;
		msdf_AllocCtx ctx;
		msdf_Result msdf;
		float scale;
	} priv;

	int file_size;
	unsigned char *file;
};


const unsigned int glyph_w = 32;
const unsigned int glyph_h = 32;


// only useful for msdf_c
static inline void * _emalloc(size_t x, void *_) { (void)_; return emalloc(x); }
static inline void _efree(void *x, void *_) { (void)_; efree(x); }


// loads a font into memory, storing all the ASCII characters in the atlas
int font_load(struct font_atlas *atlas, const char *path, int height)
{
	if (!atlas || !path)
		return -1;

	dump_file(path, &(atlas->file), &(atlas->file_size));

	stbtt_InitFont(&(atlas->priv.stb), atlas->file, 0);
	atlas->priv.scale = stbtt_ScaleForPixelHeight(&(atlas->priv.stb), height);
	int ascent, descent, linegap, baseline;
	int x0,y0,x1,y1;
	stbtt_GetFontVMetrics(&(atlas->priv.stb), &ascent, &descent, &linegap);
	stbtt_GetFontBoundingBox(&(atlas->priv.stb), &x0, &y0, &x1, &y1);

	baseline = atlas->priv.scale * -y0;
	//atlas->glyph_max_w = (atlas->priv.scale*x1) - (atlas->priv.scale*x0);
	//atlas->glyph_max_h = (baseline+atlas->priv.scale*y1) - (baseline+atlas->priv.scale*y0);
	//atlas->atlas = emalloc(atlas->glyph_max_w*atlas->glyph_max_h*CACHE_SIZE);
	atlas->atlas  = ecalloc(CACHE_SIZE, BDEPTH*glyph_h*glyph_w);
	atlas->width  = glyph_w*CACHE_SIZE;
	atlas->height = glyph_h*CACHE_SIZE;

	atlas->priv.ctx = (msdf_AllocCtx){_emalloc, _efree, NULL};

	cache_init();

	return 0;
}


int font_free(struct font_atlas *atlas)
{
	efree(atlas->atlas);
	efree(atlas->file);
	return 0;
}


// FIXME: when generating the sdf I only use the height, so to not encounter memory
//        errors height and width must be equal
static unsigned int insert(struct font_atlas *atlas)
{
	unsigned char *a = atlas->atlas;
	msdf_Result  res = atlas->priv.msdf;

	float s  = glyph_h;
	float tw = ((s * 0.7f) + s) / (s * 2.0f);
	float ta = tw - 0.5f;
	float ts = 0.5 - ta / 2;
	float te = ts + ta;

	unsigned int spot = cache_get();
	unsigned int off = spot * glyph_h * glyph_w * BDEPTH;

	#define NORMALIZE(x) x = x > ts ? (x > te ? 1.0f : (x-ts)/ta+0.0f) : (0.0f)

	for (int y = 0; y < res.height; y++) {
	        int yPos = res.width * 3 * y;
		for (int x = 0; x < res.width; x++) {

			int i = yPos + (x * 3);
			float r = res.rgb[i+0];
			float g = res.rgb[i+1];
			float b = res.rgb[i+2];

			r = (r + s) / (s * 2.0f);
			g = (g + s) / (s * 2.0f);
			b = (b + s) / (s * 2.0f);

			NORMALIZE(r);
			NORMALIZE(g);
			NORMALIZE(b);

			a[off + glyph_w*y + x + 0] = r * 255.0f; // (r > 0.5f) ? 255.0f : r * 255.0f;
			a[off + glyph_w*y + x + 0] = g * 255.0f; // (g > 0.5f) ? 255.0f : g * 255.0f;
			a[off + glyph_w*y + x + 0] = b * 255.0f; // (b > 0.5f) ? 255.0f : b * 255.0f;
		}
	}

	return spot;
}


struct font_glyph * font_get_glyph_texture(struct font_atlas *atlas, unsigned int code)
{
	struct font_glyph *r;
	if ((r = cache_search(code)) != NULL)
		return r;

	// generate the sdf and put it into the cache
	// TODO: generate the whole block at once
	int idx = stbtt_FindGlyphIndex(&atlas->priv.stb, code);
	// FIXME: what happens if I change the range?
	int s;
	s = msdf_genGlyph(&atlas->priv.msdf,
		&atlas->priv.stb,
		idx,
		BORDER,
		atlas->priv.scale,
		2.0f/glyph_h,
		&atlas->priv.ctx);
	if (!s)
		return NULL;
	unsigned int spot = insert(atlas);

}
