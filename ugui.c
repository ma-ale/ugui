#include <stdlib.h>
#include <string.h>
#include <err.h>
#include <errno.h>

#include "ugui.h"

#define SALT         0xbabb0cac
#define DEF_SCALE    1.0
#define DEF_DPI      96.0
#define E_STACK_STEP (1024 * 128)

#define TO_PPM(dpi, scale) (dpi * scale * 0.03937008)

// https://en.wikipedia.org/wiki/Jenkins_hash_function
unsigned int hash(void *data, unsigned int size)
{
	if (!size)
		return 0;
	unsigned int hash = SALT;
	unsigned char *v = (unsigned char *)data;

	for (; size; size--) {
		hash += v[size-1];
		hash += hash << 10;
		hash ^= hash >> 6;
	}
	hash += hash << 3;
  	hash ^= hash >> 11;
  	hash += hash << 15;
	
	return hash;
}


static void grow_stack(ug_ctx_t *ctx)
{
	if (!ctx)
		err(EXIT_FAILURE, "__FUNCTION__:" "Cannot grow null context");
	ctx->e_size += E_STACK_STEP;
	ctx->e_stack = realloc(ctx->e_stack, ctx->e_size);
	if (!ctx->e_stack)
		err(errno, "__FUNCTION__:" "Could not grow stack: %s", strerror(errno));
}


// creates a new context, fills with default values, ctx is ready for ug_start()
ug_ctx_t *ug_new_ctx(void)
{
	ug_ctx_t *ctx = malloc(sizeof(ug_ctx_t));
	if (!ctx)
		err(errno, "__FUNCTION__:" "Could not allocate context: %s", strerror(errno));
	memset(ctx, 0, sizeof(ug_ctx_t));

	ctx->scale     = DEF_SCALE;
	ctx->dpi       = DEF_DPI;
	ctx->ppm       = TO_PPM(DEF_SCALE, DEF_DPI);
	
	return ctx;
}


void ug_free_ctx(ug_ctx_t *ctx)
{
	if (!ctx) {
		warn("__FUNCTION__:" "Trying to free a null context");
		return;
	}
	
	if (!ctx->e_stack) {
		warn("__FUNCTION__:" "Context has null element stack");
		return;
	}

	free(ctx->e_stack);
	free(ctx);
}


// updates the context with user information
int ug_update_ctx(ug_ctx_t *ctx,
                  unsigned int window_id,
	          float scale,
	          float dpi,
	          float ppm
	         )
{
	if (!ctx)
		return -1;
	ctx->window_id = window_id;

	if (scale)
		ctx->scale = scale;
	if (dpi)
		ctx->dpi = dpi;
	if (!ppm)
		ctx->ppm = TO_PPM(ctx->dpi, ctx->scale);
	else
		ctx->ppm = ppm;

	return 0;
}


/*=============================================================================*
 *                              INPUT FUNCTIONS                                *
 *=============================================================================*/

#define TEST_CTX(ctx) {                                                \
	if (!ctx) {                                                    \
		warn("__FUNCTION__:" "trying to use a null context");  \
		return;                                                \
	}                                                              \
}

void ug_input_mousemove(ug_ctx_t *ctx, int x, int y)
{
	TEST_CTX(ctx);
	ctx->mouse.pos = (struct ug_vec2){ .x = x, .y = y };
}

void ug_input_mousedown(ug_ctx_t *ctx, int x, int y, unsigned char btn)
{
	TEST_CTX(ctx);
	ug_input_mousemove(ctx, x, y);
	ctx->mouse.down_mask |= btn;
	ctx->mouse.press_mask |= btn;
}


void ug_input_mouseup(ug_ctx_t *ctx, int x, int y, unsigned char btn)
{
	TEST_CTX(ctx);
	ug_input_mousemove(ctx, x, y);
	ctx->mouse.down_mask &= ~btn;
}


void ug_input_scroll(ug_ctx_t *ctx, int x, int y)
{
	TEST_CTX(ctx);
	ctx->mouse.scroll_delta.x += x;
	ctx->mouse.scroll_delta.y += y;
}


void ug_input_keydown(ug_ctx_t *ctx, int key)
{
	TEST_CTX(ctx);
	ctx->key.down_mask |= key;
	ctx->key.press_mask |= key;
}


void ug_input_keyup(ug_ctx_t *ctx, int key)
{
	TEST_CTX(ctx);
	ctx->key.down_mask &= ~key;
}


// append in input text
void ug_input_text(ug_ctx_t *ctx, const char *text)
{
	TEST_CTX(ctx);
	int size = strlen(ctx->input_text);
	int len  = strlen(text);
	if ((unsigned long)(size+len) >= sizeof(ctx->input_text)) {
		warn("__FUNCTION__" "Input text exceeds context buffer");
		return;
	}
	memcpy(ctx->input_text + size, text, len);
}


/*=============================================================================*
 *                              BEGIN AND END                                  *
 *=============================================================================*/

#undef TEST_CTX
#define TEST_CTX(ctx) {                                                \
	if (!ctx) {                                                    \
		warn("__FUNCTION__:" "trying to use a null context");  \
		return -1;                                             \
	}                                                              \
}

int ug_begin(ug_ctx_t *ctx)
{
	// it is the beginning of a new frame
	TEST_CTX(ctx);

	// reset the command stack
	ctx->e_idx = 0;
	// next frame
	ctx->frame++;
	// update the mouse delta
	ctx->mouse.delta.x = ctx->mouse.pos.x - ctx->mouse.last_pos.x;
	ctx->mouse.delta.y = ctx->mouse.pos.y - ctx->mouse.last_pos.y;
	// TODO: other stuff
	return 0;
}


int ug_end(ug_ctx_t *ctx)
{
	// end of a frame, check that all went well
	TEST_CTX(ctx);

	// reset the inputs
	ctx->mouse.press_mask   = 0;
	ctx->mouse.scroll_delta = (struct ug_vec2){0};
	ctx->mouse.last_pos     = ctx->mouse.pos;
	ctx->key.press_mask     = 0;
	ctx->input_text[0]      = '\0';
	return 0;
}

/*=============================================================================*
 *                              UI ELEMENTS                                    *
 *=============================================================================*/

#undef TEST_CTX
#define TEST_CTX(ctx) {                                                \
	if (!ctx) {                                                    \
		warn("__FUNCTION__:" "trying to use a null context");  \
		return 0;                                              \
	}                                                              \
}

// Slider element, a rectangle with some text and another rectangle inside
// When used with a mouse the slider moves to the clicked area and stat gets
// updated, in that case a non-zero value gets returned
int ug_slider(ug_ctx_t *ctx, float *stat, float min, float max)
{
	TEST_CTX(ctx);
	ug_draw_rect(ctx)
}
