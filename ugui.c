#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <err.h>

#include "ugui.h"


#define SALT         0xbabb0cac
#define DEF_SCALE    1.0
#define DEF_PPI      96.0
#define STACK_STEP   64

#define PPI_PPM(ppi, scale) (ppi * scale * 0.03937008)
#define PPI_PPD(ppi, scale) (PPI_PPM(ppi, scale) * 0.3528)
#define IS_VALID_UNIT(u)    (u==UG_UNIT_PX||u==UG_UNIT_MM||u==UG_UNIT_PT)
#define UG_ERR(...)         err(errno, "__FUNCTION__: " __VA_ARGS__)

// default style
// TODO: fill default style
static const ug_style_t default_style = {
	.text = {
		.color     = RGB_FORMAT(0xffffff),
		.alt_color = RGB_FORMAT(0xbbbbbb),
		.size      = SIZE_PX(16),
		.alt_size  = SIZE_PX(12),
	},
};

static const ug_vec2_t max_size = {10e6, 10e6};

static ug_style_t style_cache = {0};


/*=============================================================================*
 *                          Common Functions                                   *
 *=============================================================================*/


// grow a stack
#define grow(S)                                                                \
{                                                                              \
	S.items = realloc(S.items, (S.size+STACK_STEP)*sizeof(*(S.items)));    \
	if(!S.items)                                                           \
		UG_ERR("Could not allocate stack #S: %s", strerror(errno));    \
	memset(&(S.items[S.size]), 0, STACK_STEP*sizeof(*(S.items)));          \
	S.size += STACK_STEP;                                                  \
}


// https://en.wikipedia.org/wiki/Jenkins_hash_function
static ug_id_t hash(const void *data, unsigned int size)
{
	if (!size)
		return 0;
	ug_id_t hash = SALT;
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


// update the style cache with the correct sizes in pixels and colors
static void update_style_cache(ug_ctx_t *ctx)
{
	const ug_style_t *s = ctx->style;
	// TODO: do this shit
	(void)s;
}


ug_rect_t rect_to_px(ug_ctx_t *ctx, ug_rect_t rect)
{
	float scale = 1.0;
	
	switch (ctx->unit) {
	case UG_UNIT_PX:
		return rect;
	case UG_UNIT_MM:
		scale = ctx->ppm;
		break;
	case UG_UNIT_PT:
		scale = ctx->ppd;
		break;
	}

	rect.x *= scale;
	rect.y *= scale;
	rect.w *= scale;
	rect.h *= scale;

	return rect;
}


/*=============================================================================*
 *                          Context Operations                                 *
 *=============================================================================*/


// creates a new context, fills with default values, ctx is ready for ug_start()
ug_ctx_t *ug_new_ctx(void)
{
	ug_ctx_t *ctx = malloc(sizeof(ug_ctx_t));
	if (!ctx)
		err(errno, "__FUNCTION__:" "Could not allocate context: %s", strerror(errno));
	memset(ctx, 0, sizeof(ug_ctx_t));

	ctx->scale     = DEF_SCALE;
	ctx->ppi       = DEF_PPI;
	ctx->ppm       = PPI_PPM(DEF_SCALE, DEF_PPI);
	ctx->ppd       = PPI_PPD(DEF_SCALE, DEF_PPI);
	
	ctx->unit      = UG_UNIT_PX;
	ctx->style     = &default_style;
	ctx->style_px  = &style_cache;

	// TODO: allocate stacks
	return ctx;
}


void ug_free_ctx(ug_ctx_t *ctx)
{
	if (!ctx) {
		warn("__FUNCTION__:" "Trying to free a null context");
		return;
	}

	// TODO: free stacks
	free(ctx);

	// NOTE: do not free style since the default is statically allocated, let
	// the user take care of it instead
}


#define TEST_CTX(ctx) { if (!ctx) return -1; }

int ug_ctx_set_displayinfo(ug_ctx_t *ctx, float scale, float ppi)
{
	TEST_CTX(ctx);
	if (scale <= 0 || ppi < 20.0)
		return -1;
	
	ctx->ppm   = PPI_PPM(scale, ppi);
	ctx->ppd   = PPI_PPM(scale, ppi);
	ctx->scale = scale;
	ctx->ppi   = ppi;
	
	update_style_cache(ctx);

	return 0;
}


int ug_ctx_set_drawableregion(ug_ctx_t *ctx, ug_vec2_t size)
{
	TEST_CTX(ctx);
	if (size.w <= 0 || size.h <= 0)
		return -1;
	
	ctx->size.w = size.w;
	ctx->size.h = size.h;

	// FIXME: do I need to do something like update_container_size() here?
	//        maybe it is redundant since each frame not every conatiner is
	//        re-added
	return 0;
}


int ug_ctx_set_style(ug_ctx_t *ctx, const ug_style_t *style)
{
	TEST_CTX(ctx);
	if (!style)
		return -1;
	// TODO: validate style

	ctx->style = style;
	update_style_cache(ctx);
	
	return 0;
}


int ug_ctx_set_unit(ug_ctx_t *ctx, ug_unit_t unit)
{
	TEST_CTX(ctx);
	if (!IS_VALID_UNIT(unit))
		return -1;
	
	ctx->unit = unit;

	return 0;
}


/*=============================================================================*
 *                          Container Operations                               *
 *=============================================================================*/


// get a new or existing container handle
static ug_container_t *get_container(ug_ctx_t *ctx, ug_id_t id)
{
	ug_container_t *c = NULL;
	for (int i = 0; i < ctx->container_stack.idx; i++) {
		if (ctx->container_stack.items[i].id == id) {
			c = &(ctx->container_stack.items[i]);
			break;
		}
	}
	// if the container was not already there allocate a new one
	if (!c) {
		if(ctx->container_stack.idx >= ctx->container_stack.size)
			grow(ctx->container_stack);
		c = &(ctx->container_stack.items[ctx->container_stack.idx++]);
	}

	return c;
}


// update the container dimensions and position according to the context information,
// also handle resizing, moving, ect. if allowed by the container
static void update_container(ug_ctx_t *ctx, ug_container_t *cnt)
{
	// if the container was just initialized the unit might not be pixels, this
	// is a problem since all mouse events are in pixels and convering back
	// and forth accumulates error and in heavy on the cpu
	if (cnt->unit != UG_UNIT_PX) {
		// FIXME: this takes the unit from the context but it should be fine
		cnt->rect = rect_to_px(ctx, cnt->rect);
		cnt->unit = UG_UNIT_PX;
	}

	// recalculate position
	// FIXME: this is the right place to do some optimization, what if the 
	//        context didn't change?
	// the absoulute position of the container
	ug_rect_t rect_abs = cnt->rect;
	
	// 0 -> take all the space, <0 -> take absolute
	if (rect_abs.w == 0)     rect_abs.w = ctx->size.w;
	else if (rect_abs.w < 0) rect_abs.w = -rect_abs.w;
	if (rect_abs.h == 0)     rect_abs.h = ctx->size.h;
	else if (rect_abs.h < 0) rect_abs.h = -rect_abs.h;

	// <0 -> relative to the right margin
	if (rect_abs.x < 0) rect_abs.x = ctx->size.x - rect_abs.w + rect_abs.x;
	if (rect_abs.y < 0) rect_abs.y = ctx->size.y - rect_abs.h + rect_abs.y;

	// if we had focus the frame before, then do shit
	if (ctx->hover.cnt == cnt->id) {
		// TODO: do stuff
	}

	// push the appropriate rectangles to the drawing stack
	// TODO: ^ This ^
}


// a floating container can be placed anywhere and can be resized, acts like a
// window inside another window
int ug_container_floating(ug_ctx_t *ctx, const char *name, ug_rect_t rect)
{	
	TEST_CTX(ctx);
	// TODO: verify rect

	ug_id_t id = name ? hash(name, strlen(name)) : hash(&rect, sizeof(ug_rect_t));
	ug_container_t *cnt = get_container(ctx, id);
	
	if (cnt->id) {
		// nothing? maybe we can skip updating all dimensions and stuff
	} else {
		cnt->id = id;
		cnt->max_size = max_size;
		cnt->rect = rect;
		cnt->unit = ctx->unit;
		cnt->flags = UG_CNT_MOVABLE   |
		             UG_CNT_RESIZABLE |
			     UG_CNT_SCROLL_X  |
			     UG_CNT_SCROLL_Y  ;
	}

	update_container(ctx, cnt);
	
	return 0;
}