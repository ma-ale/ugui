#include <stdlib.h>
#include <stdio.h>
#include <grapheme.h>

#include "cache.h"
#include "font.h"


int main(void)
{
	cache_init();

	struct font_glyph *g, b;
	b.codepoint = 'a';
	b.u = b.v = 10;
	b.w = b.h = 20;

	g = cache_get('a');
	if (!g)	printf("no element\n");
	g = cache_get(0xa3c0);
	if (!g) printf("not present\n");

	const char *s = "κόσμε ciao mamma @à``²`²aas³³²";
	size_t ret, off;
	uint_least32_t cp;
	for (off = 0; (ret = grapheme_decode_utf8(s+off, SIZE_MAX, &cp)) > 0 && cp != 0; off += ret) {
		printf("%.*s (%d) -> %d\n", (int)ret, s+off, (int)ret, cp);
		b.codepoint = cp;
		if (cache_insert(&b)) printf("failed insert %d\n", b.codepoint);
		if ((g = cache_get(cp))) printf("got %d\n", g->codepoint);
	}

	cache_destroy();
	return 0;
}
