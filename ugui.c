#include <stdlib.h>
#include <stdio.h>
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
#define INTERSECTS(v, r) (BETWEEN(v.x, r.x, r.x+r.w) && BETWEEN(v.y, r.y, r.y+r.h))


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
		.bg_color          = RGB_FORMAT(0x0000ff),
		.border.t          = SIZE_PX(3),
		.border.b          = SIZE_PX(3),
		.border.l          = SIZE_PX(3),
		.border.r          = SIZE_PX(3),
		.border.color      = RGB_FORMAT(0x00ff00),
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
#define GROW_STACK(S)                                                                \
{                                                                              \
	S.items = realloc(S.items, (S.size+STACK_STEP)*sizeof(*(S.items)));    \
	if(!S.items)                                                           \
		UG_ERR("Could not allocate stack #S: %s", strerror(errno));    \
	memset(&(S.items[S.size]), 0, STACK_STEP*sizeof(*(S.items)));          \
	S.size += STACK_STEP;                                                  \
}


#define GET_FROM_STACK(S, c)                                                   \
{                                                                              \
	if (S.idx >= S.size)                                                   \
		GROW_STACK(S);                                                 \
	c = &(S.items[S.idx++]);                                               \
}


#define RESET_STACK(S)                                                         \
{                                                                              \
	memset(S.items, 0, S.idx*sizeof(*(S.items)));                          \
	S.idx = 0;                                                             \
}


#define MOUSEDOWN(ctx, btn) (ctx->mouse.press_mask &  ctx->mouse.down_mask & btn)
#define MOUSEUP(ctx, btn)   (ctx->mouse.press_mask & ~ctx->mouse.down_mask & btn)


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
	// FIME: use the correct units and convert, for now assume default style
	style_cache = *s;
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


void push_rect_command(ug_ctx_t *ctx, const ug_rect_t *rect, ug_color_t color)
{
	ug_cmd_t *c;
	GET_FROM_STACK(ctx->cmd_stack, c);
	c->type       = UG_CMD_RECT;
	c->rect.x     = rect->x;
	c->rect.y     = rect->y;
	c->rect.w     = rect->w;
	c->rect.h     = rect->h;
	c->rect.color = color;
}


/*=============================================================================*
 *                          Context Operations                                 *
 *=============================================================================*/


// creates a new context, fills with default values, ctx is ready for ug_start()
ug_ctx_t *ug_ctx_new(void)
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


void ug_ctx_free(ug_ctx_t *ctx)
{
	if (!ctx) {
		warn("__FUNCTION__:" "Trying to free a null context");
		return;
	}

	free(ctx->cmd_stack.items);
	free(ctx->cnt_stack.items);

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
	if (!c)
		GET_FROM_STACK(ctx->cnt_stack, c);

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
	cnt->rect_abs = cnt->rect;

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
	if (cnt->rect_abs.w < 0)  cnt->rect_abs.w = -cnt->rect_abs.w;
	if (cnt->rect_abs.h < 0)  cnt->rect_abs.h = -cnt->rect_abs.h;

	if (cnt->rect_abs.w == 0) cnt->rect_abs.w = ctx->size.w          - 
	                                  s->cnt.border.l.size -
					  s->cnt.border.r.size ;
	if (cnt->rect_abs.h == 0) cnt->rect_abs.h = ctx->size.h          -
	                                  s->cnt.border.t.size -
					  s->cnt.border.b.size ;
        if (cnt->flags & UG_CNT_MOVABLE) 
		cnt->rect_abs.h += s->cnt.titlebar.height.size;

	// <0 -> relative to the right margin
	if (cnt->rect_abs.x < 0) 
		cnt->rect_abs.x = ctx->size.x - cnt->rect_abs.w + cnt->rect_abs.x;
	if (cnt->rect_abs.y < 0) 
		cnt->rect_abs.y = ctx->size.y - cnt->rect_abs.h + cnt->rect_abs.y;

	// if we had focus the frame before, then do shit
	// FIXME: if this is a brand new container then do we need to handle user
	//        inputs, since all inputs lag one frame, then it would make no sense
	if (ctx->hover.cnt_last == cnt->id) {
		// mouse pressed handle resize, for simplicity containers can only 
		// be resized from the bottom and right border

#define BIN_PATTERN "%c%c%c%c%c%c%c%c"
#define BYTE_TO_BINARY(byte)  \
  (byte & 0x80 ? '1' : '0'), \
  (byte & 0x40 ? '1' : '0'), \
  (byte & 0x20 ? '1' : '0'), \
  (byte & 0x10 ? '1' : '0'), \
  (byte & 0x08 ? '1' : '0'), \
  (byte & 0x04 ? '1' : '0'), \
  (byte & 0x02 ? '1' : '0'), \
  (byte & 0x01 ? '1' : '0') 

		printf("mousemask = "BIN_PATTERN"\n", BYTE_TO_BINARY(ctx->mouse.down_mask));
		if (ctx->mouse.down_mask & UG_BTN_LEFT) {
			printf("MOUSEDOWN\n");
			ug_vec2_t mpos = ctx->mouse.pos;
			int minx, maxx, miny, maxy;
			
			// handle movable windows
			minx = cnt->rect_abs.x;
			maxx = cnt->rect_abs.x + cnt->rect_abs.w - s->cnt.border.r.size;
			miny = cnt->rect_abs.y;
			maxy = cnt->rect_abs.y + s->cnt.titlebar.height.size;
			if (cnt->flags & UG_CNT_MOVABLE &&
			    BETWEEN(mpos.x, minx, maxx) &&
			    BETWEEN(mpos.y, miny, maxy)) {
				cnt->rect_abs.x  += ctx->mouse.delta.x;
				cnt->rect_abs.y  += ctx->mouse.delta.y;
				cnt->rect.x += ctx->mouse.delta.x;
				cnt->rect.y += ctx->mouse.delta.y;
			}

			// right border resize
			minx = cnt->rect_abs.x + cnt->rect_abs.w - s->cnt.border.r.size;
			maxx = cnt->rect_abs.x + cnt->rect_abs.w;
			miny = cnt->rect_abs.y;
			maxy = cnt->rect_abs.y + cnt->rect_abs.h;
			if (BETWEEN(mpos.x, minx, maxx) && BETWEEN(mpos.y, miny, maxy)) {
				cnt->rect_abs.w  += ctx->mouse.delta.x;
				cnt->rect.w += ctx->mouse.delta.x;
			}		

			// bottom border resize
			minx = cnt->rect_abs.x;
			maxx = cnt->rect_abs.x + cnt->rect_abs.w;
			miny = cnt->rect_abs.y + cnt->rect_abs.h - s->cnt.border.b.size;
			maxy = cnt->rect_abs.y + cnt->rect_abs.h;
			if (BETWEEN(mpos.x, minx, maxx) && BETWEEN(mpos.y, miny, maxy)) {
				cnt->rect_abs.h  += ctx->mouse.delta.y;
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
	// push outline
	push_rect_command(ctx, &cnt->rect_abs, s->cnt.border.color);
	// push titlebar
	ug_rect_t titlebar = {
		.x = (cnt->rect_abs.x + s->cnt.border.l.size),
		.y = (cnt->rect_abs.y + s->cnt.border.t.size),
		.w = (cnt->rect_abs.w - s->cnt.border.r.size - s->cnt.border.l.size),
		.h = s->cnt.titlebar.height.size,
	};
	push_rect_command(ctx, &titlebar, s->cnt.titlebar.bg_color);
	// push main body
	ug_rect_t body = {
		.x = (cnt->rect_abs.x + s->cnt.border.l.size),
		.y = (cnt->rect_abs.y + s->cnt.border.t.size),
		.w = (cnt->rect_abs.w - s->cnt.border.l.size - s->cnt.border.r.size),
		.h = (cnt->rect_abs.h - s->cnt.border.t.size - s->cnt.border.b.size),
	};
	if (cnt->flags & UG_CNT_MOVABLE) {
		body.y += s->cnt.titlebar.height.size + s->cnt.border.t.size;
		body.h -= s->cnt.titlebar.height.size + s->cnt.border.t.size;
	}
	push_rect_command(ctx, &body, s->cnt.bg_color);
	// TODO: push other rects
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
		cnt->flags = UG_CNT_MOVABLE  | UG_CNT_RESIZABLE |
			     UG_CNT_SCROLL_X | UG_CNT_SCROLL_Y  ;
	}

	update_container(ctx, cnt);
	
	return 0;
}


/*=============================================================================*
 *                            Input Handling                                   *
 *=============================================================================*/


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

	ctx->mouse.press_mask |= mask;
	ctx->mouse.down_mask  |= mask;

	return 0;
}


int ug_input_mouseup(ug_ctx_t *ctx, unsigned int mask)
{
	TEST_CTX(ctx);

	ctx->mouse.down_mask &= ~mask;

	return 0;
}



/*=============================================================================*
 *                            Frame Handling                                   *
 *=============================================================================*/


// At the beginning of a frame assume that all input has been passed to the context
// update the mouse delta and reset the command stack
int ug_frame_begin(ug_ctx_t *ctx)
{
	TEST_CTX(ctx);

	// TODO: add a way to mark a container for removal from the stack, and then
	//       remove it here to save space

	// update mouse delta
	ctx->mouse.delta.x = ctx->mouse.pos.x - ctx->mouse.last_pos.x;
	ctx->mouse.delta.y = ctx->mouse.pos.y - ctx->mouse.last_pos.y;
	
	// clear command stack
	RESET_STACK(ctx->cmd_stack);

	// update hover index
	ug_vec2_t v = ctx->mouse.pos;
//	printf("mouse: x=%d, y=%d\n", ctx->mouse.pos.x, ctx->mouse.pos.x);
	for (int i = 0; i < ctx->cnt_stack.idx; i++) {
		ug_rect_t r = ctx->cnt_stack.items[i].rect_abs;
		if (INTERSECTS(v, r)) {
			ctx->hover.cnt = ctx->cnt_stack.items[i].id;
//			printf("intersects! %.8x\n", ctx->hover.cnt);
		}
	}

	return 0;
}


// At the end of a frame reset inputs
int ug_frame_end(ug_ctx_t *ctx)
{
	TEST_CTX(ctx);

	ctx->input_text[0]      = '\0';
	ctx->key.press_mask     = 0;
	ctx->mouse.press_mask   = 0;
	ctx->mouse.scroll_delta = (ug_vec2_t){0};
	ctx->mouse.last_pos     = ctx->mouse.pos;

	// reset hover, it has to be calculated at frame beginning
	ctx->hover.cnt_last  = ctx->hover.cnt;
	ctx->hover.elem_last = ctx->hover.elem;
	ctx->hover.cnt       = 0;
	ctx->hover.elem      = 0;

	return 0;
}

