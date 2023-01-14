#include "ugui.h"

/*=============================================================================*
 *                            Input Handling                                   *
 *=============================================================================*/


#define TEST_CTX(ctx) { if (!ctx) return -1; }


int ug_input_mousemove(ug_ctx_t *ctx, int x, int y)
{
	TEST_CTX(ctx)
	if (x < 0 || y < 0)
		return 0;
	
	ctx->mouse.pos = (ug_vec2_t){.x = x, .y = y};

	return 0;
}


int ug_input_mousedown(ug_ctx_t *ctx, unsigned int mask)
{
	TEST_CTX(ctx);

	ctx->mouse.update  |= mask;

	return 0;
}


int ug_input_mouseup(ug_ctx_t *ctx, unsigned int mask)
{
	TEST_CTX(ctx);

	ctx->mouse.update |= mask;

	return 0;
}
