#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <err.h>
#include <math.h>

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
#define INTERSECTS(v, r)     (BETWEEN(v.x, r.x, r.x+r.w) && BETWEEN(v.y, r.y, r.y+r.h))
#define CAP(x, s)            { if (x < s) x = s; }


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

	ctx->unit      = UG_UNIT_PX;
	ctx->style     = &default_style;
	ctx->style_px  = &style_cache;
	ug_ctx_set_displayinfo(ctx, DEF_SCALE, DEF_PPI);

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
	
	ctx->last_ppi = ctx->ppi;
	ctx->last_ppm = ctx->ppd;
	ctx->last_ppd = ctx->ppm;

	ctx->ppm   = PPI_PPM(scale, ppi);
	ctx->ppd   = PPI_PPM(scale, ppi);
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
	// if the container is new it has never been converted to pixels
	if (cnt->unit != UG_UNIT_PX) {
		float scale = 1.0;
		switch (ctx->unit) {
		case UG_UNIT_MM: scale = ctx->ppm; break;
		case UG_UNIT_PT: scale = ctx->ppd; break;
		default: break;
		}
		cnt->rect.x = roundf(cnt->rect.fx * scale);
		cnt->rect.y = roundf(cnt->rect.fy * scale);
		cnt->rect.w = roundf(cnt->rect.fw * scale);
		cnt->rect.h = roundf(cnt->rect.fh * scale);

		cnt->unit = UG_UNIT_PX;
	} else if (ctx->ppi != ctx->last_ppi) {
		// if the scale has been updated than we need to scale the container
		// as well
		float scale = ctx->ppi / ctx->last_ppi;
		cnt->rect.x = roundf(cnt->rect.x * scale);
		cnt->rect.y = roundf(cnt->rect.y * scale);
		cnt->rect.w = roundf(cnt->rect.w * scale);
		cnt->rect.h = roundf(cnt->rect.h * scale);
	}

	cnt->rca = cnt->rect;

	/*
	 * Container style:
	 * 
	 * rca
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
	int bl = s->cnt.border.l.size;
	int br = s->cnt.border.r.size;
	int bt = s->cnt.border.t.size;
	int bb = s->cnt.border.b.size;
	int hh = s->cnt.titlebar.height.size;
	int cw = ctx->size.w;
	int ch = ctx->size.h;

	// 0 -> take all the space, <0 -> take absolute
	if (cnt->rect.w < 0)  cnt->rca.w = -cnt->rect.w;
	if (cnt->rect.h < 0)  cnt->rca.h = -cnt->rect.h;

	// handle relative position
	// and move to fit borders
	if (cnt->rect.w == 0) cnt->rca.w = cw - br - bl;
	else cnt->rca.w += bl + br;
	if (cnt->rect.h == 0) cnt->rca.h = ch - bt - bb;
	else if (cnt->flags & UG_CNT_MOVABLE) cnt->rca.h += hh + 2*bt + bb;
	else cnt->rca.h += bt + bb;


	// the window may have been resized so cap the position to the window size
	// FIXME: is MAX(cw - bl, 0) better?
	if (cnt->rect.x > cw) cnt->rca.x = cw;
	if (cnt->rect.y > ch) cnt->rca.y = ch;

	// <0 -> relative to the right margin
	if (cnt->rect.x < 0) cnt->rca.x = cw - cnt->rca.w + cnt->rca.x;
	if (cnt->rect.y < 0) cnt->rca.y = ch - cnt->rca.h + cnt->rca.y;

	// if we had focus the frame before, then do shit
	if (ctx->hover.cnt_last != cnt->id)
		goto cnt_draw;

	// mouse pressed handle resize, for simplicity containers can only 
	// be resized from the bottom and right border
	// TODO: bring selected container to the top of the stack
	if (!(ctx->mouse.down_mask & UG_BTN_LEFT) ||
	    !(cnt->flags & (UG_CNT_RESIZABLE | UG_CNT_MOVABLE)))
		goto cnt_draw;
	
	ug_vec2_t mpos = ctx->mouse.pos;
	int minx, maxx, miny, maxy;
	
	// handle movable windows
	if (cnt->flags & UG_CNT_MOVABLE) {
		minx = cnt->rca.x;
		maxx = cnt->rca.x + cnt->rca.w - br;
		miny = cnt->rca.y;
		maxy = cnt->rca.y + bt + hh;
		if (BETWEEN(mpos.x, minx, maxx) && BETWEEN(mpos.y, miny, maxy)) {
			cnt->rect.x += ctx->mouse.delta.x;
			cnt->rect.y += ctx->mouse.delta.y;
			cnt->rca.x += ctx->mouse.delta.x;
			cnt->rca.y += ctx->mouse.delta.y;
		}
	}

	if (cnt->flags & UG_CNT_RESIZABLE) {
		// right border resize
		minx = cnt->rca.x + cnt->rca.w - br;
		maxx = cnt->rca.x + cnt->rca.w;
		miny = cnt->rca.y;
		maxy = cnt->rca.y + cnt->rca.h;
		if (BETWEEN(mpos.x, minx, maxx) && BETWEEN(mpos.y, miny, maxy)) {
			cnt->rect.w += ctx->mouse.delta.x;
			cnt->rca.w += ctx->mouse.delta.x;
		}

		// bottom border resize
		minx = cnt->rca.x;
		maxx = cnt->rca.x + cnt->rca.w;
		miny = cnt->rca.y + cnt->rca.h - bb;
		maxy = cnt->rca.y + cnt->rca.h;
		if (BETWEEN(mpos.x, minx, maxx) && BETWEEN(mpos.y, miny, maxy)) {
			cnt->rect.h += ctx->mouse.delta.y;
			cnt->rca.h += ctx->mouse.delta.y;
		}
	}

	// TODO: what if I want to close a floating container?
	//       Maybe add a UG_CNT_CLOSABLE flag?

	// TODO: what about scrolling? how do we know if we need to draw
	//       a scroll bar? Maybe add that information inside the
	//       container structure

	// push the appropriate rectangles to the drawing stack
	ug_rect_t draw_rect;
	cnt_draw:
	
	// push outline
	draw_rect = cnt->rca;
	push_rect_command(ctx, &draw_rect, s->cnt.border.color);
	
	// titlebar
	if (cnt->flags & UG_CNT_MOVABLE) {
		draw_rect.x += bl;
		draw_rect.y += bt;
		draw_rect.w -= bl + br;
		draw_rect.h  = hh;
		push_rect_command(ctx, &draw_rect, s->cnt.titlebar.bg_color);
	}
	
	// push main body
	draw_rect = cnt->rca;
	draw_rect.x += bl;
	draw_rect.y += bt;
	draw_rect.w -= bl + br;
	draw_rect.h -= bt + bb;
	if (cnt->flags & UG_CNT_MOVABLE) {
		draw_rect.y += bt + hh;
		draw_rect.h -= bt + hh;
	}
	push_rect_command(ctx, &draw_rect, s->cnt.bg_color);
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
		ug_rect_t r = ctx->cnt_stack.items[i].rca;
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

	ctx->last_ppi = ctx->ppi;
	ctx->last_ppm = ctx->ppm;
	ctx->last_ppd = ctx->ppd;

	ctx->frame++;

	return 0;
}

