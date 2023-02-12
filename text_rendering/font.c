#define _POSIX_C_SOURCE 200809l
#define STB_TRUETYPE_IMPLEMENTATION
#define STBTT_STATIC

#include <grapheme.h>

#include "msdf_c/stb_truetype.h"
#include "msdf_c/msdf.h"
#include "util.h"
#include "font.h"


#define UTF8(c) (c&0x80)


// Generates a cached atlas of font glyphs encoded usign a signed distance field
// https://www.youtube.com/watch?v=1b5hIMqz_wM
// https://github.com/pjako/msdf_c
// this way the texture atlas for the font will be bigger but we save up the space
// needed for rendering the font in multiple sizes


struct font_atlas {
	unsigned int glyphs;
	unsigned char *atlas;

	struct {
		stbtt_fontinfo info;
		float scale;
	} stb;
	int file_size;
	unsigned char *file;
};


const unsigned int glyph_w = 32;
const unsigned int glyph_h = 32;


// loads a font into memory, storing all the ASCII characters in the atlas
int load_font(struct font_atlas *atlas, const char *path, int height)
{
	if (!atlas || !path)
		return -1;

	dump_file(path, &(atlas->file), &(atlas->file_size));

	stbtt_InitFont(&(atlas->stb.info), atlas->file, 0);
	atlas->stb.scale = stbtt_ScaleForPixelHeight(&(atlas->stb.info), height);
	int ascent, descent, linegap, baseline;
	int x0,y0,x1,y1;
	stbtt_GetFontVMetrics(&(atlas->stb.info), &ascent, &descent, &linegap);
	stbtt_GetFontBoundingBox(&(atlas->stb.info), &x0, &y0, &x1, &y1);

	baseline = atlas->stb.scale * -y0;
	//atlas->glyph_max_w = (atlas->stb.scale*x1) - (atlas->stb.scale*x0);
	//atlas->glyph_max_h = (baseline+atlas->stb.scale*y1) - (baseline+atlas->stb.scale*y0);
	//atlas->atlas = emalloc(atlas->glyph_max_w*atlas->glyph_max_h*CACHE_SIZE);
	atlas->atlas

	return 0;
}


int free_font(struct font_atlas *atlas)
{
	efree(atlas->atlas);
	efree(atlas->file);
	return 0;
}
