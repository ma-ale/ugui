#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <err.h>

#include "ugui.h"


#define SALT         0xbabb0cac
#define DEF_SCALE    1.0
#define DEF_PPI      96.0
#define STACK_STEP   64

#define PPI_PPM(ppi, scale)  (ppi * scale * 0.03937008)
#define PPI_PPD(ppi, scale)  (PPI_PPM(ppi, scale) * 0.3528)
#define IS_VALID_UNIT(u)     (u==UG_UNIT_PX||u==UG_UNIT_MM||u==UG_UNIT_PT)
#define UG_ERR(...)          err(errno, "__FUNCTION__: " __VA_ARGS__)
#define BETWEEN(x, min, max) (x <= max && x >= min)


// default style
// TODO: fill default style
static const ug_style_t default_style = {
	.text = {
		.color     = RGB_FORMAT(0xffffff),
		.alt_color = RGB_FORMAT(0xbbbbbb),
		.size      = SIZE_PX(16),
		.alt_size  = SIZE_PX(12),
	},
	.cnt = {
		.bg_color          = RGB_FORMAT(0xaaaaaa),
		.border.t          = SIZE_PX(3),
		.border.b          = SIZE_PX(3),
		.border.l          = SIZE_PX(3),
		.border.r          = SIZE_PX(3),
		.titlebar.height   = SIZE_PX(20),
		.titlebar.bg_color = RGB_FORMAT(0xbababa),
	},
};

static const ug_vec2_t max_size = {{10e6}, {10e6}};

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


#define mousedown(ctx, btn) (ctx->mouse.press_mask &  ctx->mouse.down_mask & btn)
#define mouseup(ctx, btn)   (ctx->mouse.press_mask & ~ctx->mouse.down_mask & btn)


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
	for (int i = 0; i < ctx->cnt_stack.idx; i++) {
		if (ctx->cnt_stack.items[i].id == id) {
			c = &(ctx->cnt_stack.items[i]);
			break;
		}
	}
	// if the container was not already there allocate a new one
	if (!c) {
		if(ctx->cnt_stack.idx >= ctx->cnt_stack.size)
			grow(ctx->cnt_stack);
		c = &(ctx->cnt_stack.items[ctx->cnt_stack.idx++]);
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

	/*
	 * Container style:
	 * 
	 * rect_abs(0,0)
	 * v
	 * +-----------------------------------------------+
	 * |          Titlebar                             |
	 * +-----------------------------------------------+
	 * |+---------------------------------------------+|
	 * ||\              ^ Border Top ^                ||
	 * || \_ rect(0,0)                                ||
	 * ||                                             ||
	 * ||                                             ||
	 * ||                                             ||
	 * ||                                             ||
	 * ||                                             ||
	 * ||                                             ||
	 * ||                                             ||
	 * || < Border Left                               ||
	 * ||                              Border Right > ||
	 * ||                                             ||
	 * ||                                             ||
	 * ||                                             ||
	 * ||                                             ||
	 * |+---------------------------------------------+|
	 * +-----------------------------------------------+
	 *                  ^ Border Bottom ^ 
	 */
	
	const ug_style_t *s = ctx->style_px;
	// 0 -> take all the space, <0 -> take absolute
	if (rect_abs.w < 0)  rect_abs.w = -rect_abs.w;
	if (rect_abs.h < 0)  rect_abs.h = -rect_abs.h;

	if (rect_abs.w == 0) rect_abs.w = ctx->size.w          - 
	                                  s->cnt.border.l.size -
					  s->cnt.border.r.size ;
	if (rect_abs.h == 0) rect_abs.h = ctx->size.h          -
	                                  s->cnt.border.t.size -
					  s->cnt.border.b.size ;
        if (cnt->flags & UG_CNT_MOVABLE) 
		rect_abs.h -= s->cnt.titlebar.height.size;

	// <0 -> relative to the right margin
	if (rect_abs.x < 0) rect_abs.x = ctx->size.x - rect_abs.w + rect_abs.x;
	if (rect_abs.y < 0) rect_abs.y = ctx->size.y - rect_abs.h + rect_abs.y;

	// if we had focus the frame before, then do shit
	// FIXME: if this is a brand new container then do we need to handle user
	//        inputs, since all inputs lag one frame, then it would make no sense
	if (ctx->hover.cnt == cnt->id) {
		// mouse pressed handle resize, for simplicity containers can only 
		// be resized from the bottom and right border
		if (mousedown(ctx, UG_BTN_RIGHT)) {
			ug_vec2_t mpos = ctx->mouse.pos;
			int minx, maxx, miny, maxy;
			
			// handle movable windows
			minx = rect_abs.x;
			maxx = rect_abs.x + rect_abs.w - s->cnt.border.r.size;
			miny = rect_abs.y;
			maxy = rect_abs.y + s->cnt.titlebar.height.size;
			if (cnt->flags & UG_CNT_MOVABLE &&
			    BETWEEN(mpos.x, minx, maxx) &&
			    BETWEEN(mpos.y, miny, maxy)) {
				rect_abs.x  += ctx->mouse.delta.x;
				rect_abs.y  += ctx->mouse.delta.y;
				cnt->rect.x += ctx->mouse.delta.x;
				cnt->rect.y += ctx->mouse.delta.y;
			}

			// right border resize
			minx = rect_abs.x + rect_abs.w - s->cnt.border.r.size;
			maxx = rect_abs.x + rect_abs.w;
			miny = rect_abs.y;
			maxy = rect_abs.y + rect_abs.h;
			if (BETWEEN(mpos.x, minx, maxx) && BETWEEN(mpos.y, miny, maxy)) {
				rect_abs.w  += ctx->mouse.delta.x;
				cnt->rect.w += ctx->mouse.delta.x;
			}		

			// bottom border resize
			minx = rect_abs.x;
			maxx = rect_abs.x + rect_abs.w;
			miny = rect_abs.y + rect_abs.h - s->cnt.border.b.size;
			maxy = rect_abs.y + rect_abs.h;
			if (BETWEEN(mpos.x, minx, maxx) && BETWEEN(mpos.y, miny, maxy)) {
				rect_abs.h  += ctx->mouse.delta.y;
				cnt->rect.h += ctx->mouse.delta.y;
			}
		}
		// TODO: what if I want to close a floating container?
		//       Maybe add a UG_CNT_CLOSABLE flag?

		// TODO: what about scrolling? how do we know if we need to draw
		//       a scroll bar? Maybe add that information inside the
		//       container structure
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
