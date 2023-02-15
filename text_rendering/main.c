#include <stdlib.h>
#include <stdio.h>
#include <grapheme.h>

#include "cache.h"
#include "font.h"
#include "util.h"


int main(void)
{
	int err;
	struct font_atlas *at = font_init();
	err = font_load(at, "./monospace.ttf");
	ERROR(err, -1, printf("failed to load font\n"));

	const char *s = "ciao mamma";
	const struct font_glyph *g;
	size_t ret, off;
	uint_least32_t cp;
	for (off = 0; (ret = grapheme_decode_utf8(s+off, SIZE_MAX, &cp)) > 0 && cp != 0; off += ret) {
		printf("%.*s (%d) -> %d\n", (int)ret, s+off, (int)ret, cp);
		g = font_get_glyph_texture(at, cp);
		if (!g)
			printf("g is NULL\n");
	}

	font_dump(at, "./atlas.png");

	font_free(at);

	return 0;
}
