#define _POSIX_C_SOURCE 200809l
#define STB_TRUETYPE_IMPLEMENTATION
#define STBTT_STATIC

#include <sys/mman.h>

#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <errno.h>
#include <err.h>

#include "stb_truetype.h"
#include "ff.h"


const int font_size = 32;


void map_file(const unsigned char **str, int *size, const char *path)
{
	if (!path)
		err(EXIT_FAILURE, "NULL filename");
	FILE *fp = fopen(path, "r");
	if (!fp)
		err(EXIT_FAILURE, "Cannot open file %s", path);
	*size = lseek(fileno(fp), 0, SEEK_END);
	if (*size == (off_t)-1)
		err(EXIT_FAILURE, "lseek failed");
	*str = mmap(0, *size, PROT_READ, MAP_PRIVATE, fileno(fp), 0);
	if (*str == (void*)-1)
		err(EXIT_FAILURE, "mmap failed");
	if (fclose(fp))
		err(EXIT_FAILURE, "Error closing file");
}


int main(int argc, char *argv[])
{
	if (argc < 2)
		return EXIT_FAILURE;
	int len;
	const unsigned char *map;
	map_file(&map, &len, argv[1]);

	stbtt_fontinfo font;
	stbtt_InitFont(&font, map, stbtt_GetFontOffsetForIndex(map, 0));

	// all this is to get the font bounding box in pixels
	float font_scale = 1.0;
	font_scale = stbtt_ScaleForPixelHeight(&font, font_size);
	int ascent, descent, linegap;
	stbtt_GetFontVMetrics(&font, &ascent, &descent, &linegap);
	int x0,y0,x1,y1;
	int bound_w, bound_h;
	stbtt_GetFontBoundingBox(&font, &x0, &y0, &x1, &y1);

	printf("font_scale: %f\n", font_scale);
	printf("x0:%d y0:%d x1:%d y1:%d\n",x0,y0,x1,y1);

	int baseline = font_scale * -y0;
	bound_h = (baseline+font_scale*y1) - (baseline+font_scale*y0);
	bound_w = (font_scale*x1) - (font_scale*x0);
	baseline = bound_h - baseline;
	unsigned char *bitmap = malloc(bound_h*bound_w);
	if (!bitmap)
		err(EXIT_FAILURE, "Cannot allocate bitmap");

	printf("bounding h:%d w:%d\n", bound_h, bound_w);
	printf("baseline: %d\n", baseline);

	struct ff *image = ff_new(0, 0);

	// get all ascii
	int x = 0, y = 0, maxwidth = 64*bound_w;
	for (unsigned int i = 0; i <= 0x7F; i++) {
		int x0,y0,x1,y1,w,h,l,a, ox,oy;
		int g = stbtt_FindGlyphIndex(&font, i);

		stbtt_GetGlyphBitmapBoxSubpixel(&font, g, font_scale, font_scale, 0, 0, &x0, &y0, &x1, &y1);
		w = x1 - x0;
		h = y1 - y0;
		//printf("%d\n", y0);
		stbtt_GetGlyphHMetrics(&font, g, &a, &l);
		stbtt_MakeGlyphBitmapSubpixel(&font, bitmap, w, h, w, font_scale, font_scale, 0, 0, g);
		//printf("'%c' -> l*scale:%.0f, y0:%d\n", i, font_scale*l, bound_h+y0);
		ox = font_scale*l;
		oy = bound_h+y0;
		ff_overlay_8r(&image, bitmap, x+ox, y+oy, w, h);

		x += bound_w;
		if (x >= maxwidth) y += bound_h;
		x %= maxwidth;

	}

	FILE *fp = fopen("out.ff", "w");
	if (fp) {
		fwrite(image, 1, ff_bytes(image), fp);
		fclose(fp);
	}

	free(bitmap);
	ff_free(image);
	munmap((void *)map, len);
	return 0;
}
