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
#define SLICE_STEP   128

#define RESIZEALL     (                                                        \
                      UG_CNT_RESIZE_RIGHT  |                                   \
                      UG_CNT_RESIZE_BOTTOM |                                   \
                      UG_CNT_RESIZE_LEFT   |                                   \
                      UG_CNT_RESIZE_TOP                                        \
                      )

#define BTN_ANY       (                                                        \
                      UG_BTN_LEFT   |                                          \
                      UG_BTN_RIGHT  |                                          \
                      UG_BTN_MIDDLE |                                          \
                      UG_BTN_4      |                                          \
                      UG_BTN_5                                                 \
                      )

#define CNT_STATE_ALL (                                                        \
                      CNT_STATE_NONE     |                                     \
                      CNT_STATE_MOVING   |                                     \
		      CNT_STATE_RESIZE_T |                                     \
                      CNT_STATE_RESIZE_B |                                     \
                      CNT_STATE_RESIZE_L |                                     \
                      CNT_STATE_RESIZE_R                                       \
                      )

#define PPI_PPM(ppi, scale)  (ppi * scale * 0.03937008)
#define PPI_PPD(ppi, scale)  (PPI_PPM(ppi, scale) * 0.3528)
#define IS_VALID_UNIT(u)     (u==UG_UNIT_PX||u==UG_UNIT_MM||u==UG_UNIT_PT)
#define UG_ERR(...)          err(errno, "__FUNCTION__: " __VA_ARGS__)
#define BETWEEN(x, min, max) (x <= max && x >= min)
#define INTERSECTS(v, r)     (BETWEEN(v.x, r.x, r.x+r.w) && BETWEEN(v.y, r.y, r.y+r.h))
#define TEST(f, b)           (f & b)
#define MAX(a, b)            (a > b ? a : b)


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

static ug_style_t style_cache = {0};


/*=============================================================================*
 *                          Common Functions                                   *
 *=============================================================================*/


// grow a stack
#define GROW_STACK(S)                                                          \
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


#define DELETE_FROM_STACK(S, c)                                                     \
{                                                                                   \
	for (int i = 0; i < S.idx; i++) {                                           \
		if (c->id != S.items[i].id)                                         \
			continue;                                                   \
		memmove(&S.items[i], &S.items[i+1], (S.idx-i)*sizeof(S.items[0]));  \
		memset(&S.items[S.idx--], 0, sizeof(S.items[0]));                   \
	}                                                                           \
}


#define RESET_STACK(S)                                                         \
{                                                                              \
	memset(S.items, 0, S.idx*sizeof(*(S.items)));                          \
	S.idx = 0;                                                             \
}


#define MOUSEDOWN(ctx, btn) (~(ctx->mouse.hold & btn) & (ctx->mouse.update & btn))
#define MOUSEUP(ctx, btn)   ((ctx->mouse.hold & btn)  & (ctx->mouse.update & btn))
#define HELD(ctx, btn)      (ctx->mouse.hold & btn)


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


int size_to_px(ug_ctx_t *ctx, ug_size_t s)
{
	switch (s.unit) {
	case UG_UNIT_MM: return roundf(s.size.f * ctx->ppm);
	case UG_UNIT_PT: return roundf(s.size.f * ctx->ppd);
	case UG_UNIT_PX: return s.size.i;
	default: return 0;
	}
}

ug_rect_t div_to_rect(ug_ctx_t *ctx, ug_div_t *div)
{
	ug_rect_t r;
	r.x = size_to_px(ctx, div->x);
	r.y = size_to_px(ctx, div->y);
	r.w = size_to_px(ctx, div->w);
	r.h = size_to_px(ctx, div->h);
	return r;
}


// update the style cache with the correct sizes in pixels and colors
static void update_style_cache(ug_ctx_t *ctx)
{
	const ug_style_t *s = ctx->style;
	// FIME: use the correct units and convert, for now assume default style
	style_cache = *s;
}


/*=============================================================================*
 *                          Command Operations                                 *
 *=============================================================================*/


static void push_rect_command(ug_ctx_t *ctx, const ug_rect_t *rect, ug_color_t color)
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


// pushes a text command to the render command stack, str is a pointer to a valid
// string offered by the user, it must be valid at least until rendering is done 
static void push_text_command(ug_ctx_t *ctx, ug_vec2_t pos, int size, ug_color_t color, const char *str)
{
	ug_cmd_t *c;
	GET_FROM_STACK(ctx->cmd_stack, c);
	c->type       = UG_CMD_TEXT;
	c->text.x     = pos.x;
	c->text.y     = pos.y;
	c->text.size  = size;
	c->text.color = color;
	c->text.str   = str;
}


ug_cmd_t *ug_cmd_next(ug_ctx_t *ctx)
{
	if(!ctx)
		return NULL;
	if (ctx->cmd_it < ctx->cmd_stack.idx)
		return &ctx->cmd_stack.items[ctx->cmd_it++];
	return NULL;
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

	ctx->style     = &default_style;
	ctx->style_px  = &style_cache;
	// NOTE: this fixes a bug where for the first frame the container stack
	//       doesn't get sorted, but it is kind of a botch
	ctx->last_active.cnt = 1;
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

	// NOTE: do not free style since the default style is statically allocated,
	// let the user take care of it instead
}


// TODO: add error codes
#define TEST_CTX(ctx) { if (!ctx) return -1; }
#define TEST_STR(s)   { if (!s || !s[0]) return -1; }


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


/*=============================================================================*
 *                          Container Operations                               *
 *=============================================================================*/


// search a container by id int the stack and get it's address
static ug_container_t *search_container(ug_ctx_t *ctx, ug_id_t id)
{
	ug_container_t *c = NULL;
	for (int i = 0; i < ctx->cnt_stack.idx; i++) {
		if (ctx->cnt_stack.items[i].id == id) {
			c = &(ctx->cnt_stack.items[i]);
			break;
		}
	}
	return c;
}


// get a new or existing container handle
static ug_container_t *get_container(ug_ctx_t *ctx, ug_id_t id)
{
	ug_container_t *c = search_container(ctx, id);
	// if the container was not already there allocate a new one
	if (!c) {
		GET_FROM_STACK(ctx->cnt_stack, c);
		ctx->cnt_stack.sorted = 0;
	}

	return c;
}


// sort the conatiner stack so that floating conatiners always stay on top and
// the active floating conatiner i son top of everything
static void sort_containers(ug_ctx_t *ctx)
{
	if (ctx->cnt_stack.sorted)
		return;
	int tot = ctx->cnt_stack.idx;
	if (!tot)
		return;

	for (int i = 0; i < tot; i++) {
		ug_container_t *cnt = &ctx->cnt_stack.items[i];
		// move floating containers to the top
		// FIXME: this is really shit
		if (TEST(cnt->flags, UG_CNT_FLOATING)) {
			int y = tot;

			ug_container_t *s = ctx->cnt_stack.items;
			ug_container_t c = *cnt;
			
			if (ctx->active.cnt != c.id)
				for (; y > 0 && TEST(s[y-1].flags, UG_CNT_FLOATING); y--);

			if (i >= y)
				continue;
			
			memmove(&s[i], &s[i+1], (y - i) * sizeof(ug_container_t));
			s[y-1] = c;
		}
	}
	ctx->cnt_stack.sorted = 1;
}


// update the container position in the context area
static int position_container(ug_ctx_t *ctx, ug_container_t *cnt)
{
	if (!TEST(cnt->flags, UG_CNT_FLOATING))
		// if there is no space left propagate the error
		if (ctx->origin.w <= 0 || ctx->origin.h <= 0)
			return -1;

	ug_rect_t *rect, *rca;
	rect = &cnt->rect;
	rca  = &cnt->rca;

	if (ctx->ppi != ctx->last_ppi) {
		// if the scale has been updated than we need to scale the container
		// as well
		float scale = ctx->ppi / ctx->last_ppi;
		rect->x = roundf(rect->x * scale);
		rect->y = roundf(rect->y * scale);
		rect->w = roundf(rect->w * scale);
		rect->h = roundf(rect->h * scale);
	}

	*rca = *rect;

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
	int bl = s->cnt.border.l.size.i;
	int br = s->cnt.border.r.size.i;
	int bt = s->cnt.border.t.size.i;
	int bb = s->cnt.border.b.size.i;
	int hh = s->cnt.titlebar.height.size.i;
	int cx = ctx->origin.x;
	int cy = ctx->origin.y;
	int cw = ctx->origin.w;
	int ch = ctx->origin.h;

	// handle relative sizes
	if (rect->w == 0) rca->w = cw;
	else rca->w += bl + br;
	if (rect->h == 0) rca->h = ch;
	else if (TEST(cnt->flags, UG_CNT_MOVABLE)) rca->h += hh + 2*bt + bb;
	else rca->h += bt + bb;


	// if the container is not fixed than it can have positions outside of the
	// main window, thus negative
	if (!TEST(cnt->flags, UG_CNT_FLOATING)) {
		// <0 -> relative to the right margin
		if (rect->x < 0) rca->x = cx + cw - rca->w + rca->x + 1;
		else rca->x = cx;
		if (rect->y < 0) rca->y = cy + ch - rca->h + rca->y + 1;
		else rca->y = cy;
		
		// if the container is fixed than update the available space in
		// the context
		if (rect->w) {
			ctx->origin.x = rect->x >= 0 ? rca->x + rca->w : ctx->origin.x;
			ctx->origin.w -= rca->w;
		} else if (rect->h) {
			ctx->origin.y = rect->y >= 0 ? rca->y + rca->h : ctx->origin.y;
			ctx->origin.h -= rca->h;
		} else {
			// width and height zero means fill everything
			ctx->origin.w = ctx->origin.h = 0;
		}
	}
	return 0;
}


// TODO: make a set of fixed return values for the different states
// handle moving and resizing, return 1 if it had focus, 0 otherwise, negative
// return values represent errors
static int handle_container(ug_ctx_t *ctx, ug_container_t *cnt)
{
	// if we are not the currently active container than definately we are not
	// being moved or resized
	if (ctx->active.cnt != cnt->id) {
		cnt->flags &= ~CNT_STATE_ALL;
		return 0;
	}

	// mouse pressed handle resize, for simplicity containers can only 
	// be resized from the bottom and right border
	// TODO: change return value to indicate this case
	if (!HELD(ctx, UG_BTN_LEFT) ||
	    !TEST(cnt->flags, (RESIZEALL | UG_CNT_MOVABLE)))
		return 1;
	
	ug_rect_t *rect, *rca;
	rect = &cnt->rect;
	rca  = &cnt->rca;

	const ug_style_t *s = ctx->style_px;
	int bl = s->cnt.border.l.size.i;
	int br = s->cnt.border.r.size.i;
	int bt = s->cnt.border.t.size.i;
	int bb = s->cnt.border.b.size.i;
	int hh = s->cnt.titlebar.height.size.i;

	ug_vec2_t mpos = ctx->mouse.pos;
	int minx, maxx, miny, maxy;
	
	// handle movable windows
	if (TEST(cnt->flags, UG_CNT_MOVABLE)) {
		minx = rca->x + bl;
		maxx = rca->x + rca->w - br;
		miny = rca->y + bt;
		maxy = rca->y + bt + hh;
		if ((cnt->flags & CNT_STATE_ALL) == CNT_STATE_MOVING ||
		    ((cnt->flags & CNT_STATE_ALL) == 0                 &&
		     BETWEEN(mpos.x, minx, maxx)                       &&
		     BETWEEN(mpos.y, miny, maxy))) {
			cnt->flags |= CNT_STATE_MOVING;
			rect->x += ctx->mouse.delta.x;
			rect->y += ctx->mouse.delta.y;
			rca->x  += ctx->mouse.delta.x;
			rca->y  += ctx->mouse.delta.y;
		}
	}

	// right border resize
	if (TEST(cnt->flags, UG_CNT_RESIZE_RIGHT)) {
		minx = rca->x + rca->w - br;
		maxx = rca->x + rca->w;
		miny = rca->y;
		maxy = rca->y + rca->h;
		if ((cnt->flags & CNT_STATE_ALL) == CNT_STATE_RESIZE_R ||
		    ((cnt->flags & CNT_STATE_ALL) == 0                 &&
		     BETWEEN(mpos.x, minx, maxx)                       &&
		     BETWEEN(mpos.y, miny, maxy))) {
			cnt->flags |= CNT_STATE_RESIZE_R;
			rect->w = MAX(10, rect->w + ctx->mouse.delta.x);
			rca->w  = MAX(10, rca->w + ctx->mouse.delta.x);
		}
	}

	// left border resize
	if (TEST(cnt->flags, UG_CNT_RESIZE_LEFT)) {
		minx = rca->x;
		maxx = rca->x + bl;
		miny = rca->y;
		maxy = rca->y + rca->h;
		if ((cnt->flags & CNT_STATE_ALL) == CNT_STATE_RESIZE_L ||
		    ((cnt->flags & CNT_STATE_ALL) == 0                 &&
		     BETWEEN(mpos.x, minx, maxx)                       &&
		     BETWEEN(mpos.y, miny, maxy))) {
			cnt->flags |= CNT_STATE_RESIZE_L;

			if (rect->w - ctx->mouse.delta.x >= 10) {
				rect->w -= ctx->mouse.delta.x;
				if (TEST(cnt->flags, UG_CNT_MOVABLE))
					rect->x += ctx->mouse.delta.x;
			}
			if (rca->w - ctx->mouse.delta.x >= 10) {
				rca->w  -= ctx->mouse.delta.x;
				rca->x  += ctx->mouse.delta.x;
			}			
		}
	}

	// bottom border resize
	if (TEST(cnt->flags, UG_CNT_RESIZE_BOTTOM)) {
		minx = rca->x;
		maxx = rca->x + rca->w;
		miny = rca->y + rca->h - bb;
		maxy = rca->y + rca->h;
		if ((cnt->flags & CNT_STATE_ALL) == CNT_STATE_RESIZE_B ||
		    ((cnt->flags & CNT_STATE_ALL) == 0                 &&
		     BETWEEN(mpos.x, minx, maxx)                       &&
		     BETWEEN(mpos.y, miny, maxy))) {
			cnt->flags |= CNT_STATE_RESIZE_B;
			rect->h += ctx->mouse.delta.y;
			rca->h  += ctx->mouse.delta.y;
		}
	}

	// top border resize
	if (TEST(cnt->flags, UG_CNT_RESIZE_TOP)) {
		minx = rca->x;
		maxx = rca->x + rca->w;
		miny = rca->y;
		maxy = rca->y + bt;
		if ((cnt->flags & CNT_STATE_ALL) == CNT_STATE_RESIZE_T ||
		    ((cnt->flags & CNT_STATE_ALL) == 0                 &&
		     BETWEEN(mpos.x, minx, maxx)                       &&
		     BETWEEN(mpos.y, miny, maxy))) {
			cnt->flags |= CNT_STATE_RESIZE_T;

			if (rect->h - ctx->mouse.delta.y >= 10) {
				rect->h -= ctx->mouse.delta.y;
				if (TEST(cnt->flags, UG_CNT_MOVABLE))
					rect->y += ctx->mouse.delta.y;
			}
			if (rca->h - ctx->mouse.delta.y >= 10) {
				rca->h  -= ctx->mouse.delta.y;
				rca->y  += ctx->mouse.delta.y;
			}
		}
	}

	// if we were not resized but we are still active it means we are doing 
	// something to the contained elements, as such set state to none
	if ((cnt->flags & CNT_STATE_ALL) == 0)
		cnt->flags |= CNT_STATE_NONE;

	// TODO: what if I want to close a floating container?
	//       Maybe add a UG_CNT_CLOSABLE flag?

	// TODO: what about scrolling? how do we know if we need to draw
	//       a scroll bar? Maybe add that information inside the
	//       container structure
	return 1;
}


static void draw_container(ug_ctx_t *ctx, ug_container_t *cnt, const char *text)
{
	ug_rect_t draw_rect;
	const ug_style_t *s = ctx->style_px;
	int bl = s->cnt.border.l.size.i;
	int br = s->cnt.border.r.size.i;
	int bt = s->cnt.border.t.size.i;
	int bb = s->cnt.border.b.size.i;
	int hh = s->cnt.titlebar.height.size.i;
	int ts = s->text.size.size.i;
	
	// push outline
	draw_rect = cnt->rca;
	push_rect_command(ctx, &draw_rect, s->cnt.border.color);
	
	// titlebar
	if (TEST(cnt->flags, UG_CNT_MOVABLE)) {
		draw_rect.x += bl;
		draw_rect.y += bt;
		draw_rect.w -= bl + br;
		draw_rect.h  = hh;
		push_rect_command(ctx, &draw_rect, s->cnt.titlebar.bg_color);
		if (text) {
			// TODO: center the text horizontally
			push_text_command(ctx,
			                 (ug_vec2_t){.x = draw_rect.x + bl,
					             .y = draw_rect.y + bt + ts/2},
					 ts, s->text.color, text);
		}
	}
	
	// push main body
	draw_rect = cnt->rca;
	draw_rect.x += bl;
	draw_rect.y += bt;
	draw_rect.w -= bl + br;
	draw_rect.h -= bt + bb;
	if (TEST(cnt->flags, UG_CNT_MOVABLE)) {
		draw_rect.y += bt + hh;
		draw_rect.h -= bt + hh;
	}
	push_rect_command(ctx, &draw_rect, s->cnt.bg_color);
	// TODO: push other rects
}


// a floating container can be placed anywhere and can be resized, acts like a
// window inside another window
int ug_container_floating(ug_ctx_t *ctx, const char *name, ug_div_t div)
{	
	TEST_CTX(ctx);
	TEST_STR(name);
	// TODO: verify div

	ug_id_t id = hash(name, strlen(name));
	ug_container_t *cnt = get_container(ctx, id);
	
	// maybe the name address was changed so always overwrite it
	cnt->name = name;
	if (cnt->id) {
		// nothing? maybe we can skip updating all dimensions and stuff
	} else {
		cnt->id = id;
		cnt->rect = div_to_rect(ctx, &div);
		cnt->flags = UG_CNT_FLOATING | RESIZEALL | UG_CNT_MOVABLE |
			     UG_CNT_SCROLL_X | UG_CNT_SCROLL_Y;
	}

	// TODO:  what about error codes and meaning?
	if (position_container(ctx, cnt)) {
		DELETE_FROM_STACK(ctx->cnt_stack, cnt);
		return -1;
	}
	
	// Select current conatiner
	ctx->selected_cnt = id;

	return handle_container(ctx, cnt);
}


int ug_container_popup(ug_ctx_t *ctx, const char *name, ug_div_t div)
{
	TEST_CTX(ctx);
	TEST_STR(name);
	// TODO: verify div

	ug_id_t id = hash(name, strlen(name));
	ug_container_t *cnt = get_container(ctx, id);
	
	// maybe the name address was changed so always overwrite it
	cnt->name = name;
	if (cnt->id) {
		// nothing? maybe we can skip updating all dimensions and stuff
	} else {
		cnt->id = id;
		cnt->rect = div_to_rect(ctx, &div);
		cnt->flags = UG_CNT_FLOATING;
	}

	// TODO:  what about error codes and meaning?
	if (position_container(ctx, cnt)) {
		DELETE_FROM_STACK(ctx->cnt_stack, cnt);
		return -1;
	}
	
	// Select current conatiner
	ctx->selected_cnt = id;

	return handle_container(ctx, cnt);
}


int ug_container_sidebar(ug_ctx_t *ctx, const char *name, ug_size_t size, int side)
{
	TEST_CTX(ctx);
	TEST_STR(name);

	ug_id_t id = hash(name, strlen(name));
	ug_container_t *cnt = get_container(ctx, id);

	// maybe the name address was changed so always overwrite it
	cnt->name = name;
	if (cnt->id) {
		// nothing? maybe we can skip updating all dimensions and stuff
	} else {
		cnt->id = id;
		cnt->flags = UG_CNT_SCROLL_X | UG_CNT_SCROLL_Y;
		ug_rect_t rect = {0};
		switch (side) {
		case UG_SIDE_BOTTOM:
			cnt->flags |= UG_CNT_RESIZE_TOP;
			// FIXME: we do not support relative zero position yet
			rect.y = -1;
			rect.h = size_to_px(ctx, size);
			break;
		case UG_SIDE_TOP:
			cnt->flags |= UG_CNT_RESIZE_BOTTOM;
			rect.h = size_to_px(ctx, size);
			break;
		case UG_SIDE_RIGHT:  
			cnt->flags |= UG_CNT_RESIZE_LEFT;
			rect.x = -1;
			rect.w = size_to_px(ctx, size);
			break;
		case UG_SIDE_LEFT:
			cnt->flags |= UG_CNT_RESIZE_RIGHT;
			rect.w = size_to_px(ctx, size);
			break;
		default: return -1;
		}
		cnt->rect = rect;
	}

	if (position_container(ctx, cnt)) {
		DELETE_FROM_STACK(ctx->cnt_stack, cnt);
		return -1;
	}
	
	// Select current conatiner
	ctx->selected_cnt = id;

	return handle_container(ctx, cnt);
}

int ug_container_menu_bar(ug_ctx_t *ctx, const char *name, ug_size_t height)
{
	TEST_CTX(ctx);
	TEST_STR(name);

	ug_id_t id = hash(name, strlen(name));
	ug_container_t *cnt = get_container(ctx, id);
	
	// maybe the name address was changed so always overwrite it
	cnt->name = name;
	if (cnt->id) {
		// nothing? maybe we can skip updating all dimensions and stuff
	} else {
		cnt->id = id;
		cnt->flags = 0;
		ug_rect_t rect = {
			.x = 0, .y = 0,
			.w = 0, .h = size_to_px(ctx, height),
		};
		cnt->rect = rect;
	}

	if (position_container(ctx, cnt)) {
		DELETE_FROM_STACK(ctx->cnt_stack, cnt);
		return -1;
	}
	
	// Select current conatiner
	ctx->selected_cnt = id;

	return handle_container(ctx, cnt);
}


int ug_container_body(ug_ctx_t *ctx, const char *name)
{
	TEST_CTX(ctx);
	TEST_STR(name);

	ug_id_t	id = hash(name, strlen(name));
	ug_container_t *cnt = get_container(ctx, id);
	
	// maybe the name address was changed so always overwrite it
	cnt->name = name;
	if (cnt->id) {
		// nothing? maybe we can skip updating all dimensions and stuff
	} else {
		cnt->id = id;
		cnt->flags = 0;
		cnt->rect = (ug_rect_t){0};
	}

	if (position_container(ctx, cnt)) {
		DELETE_FROM_STACK(ctx->cnt_stack, cnt);
		return -1;
	}
	
	// Select current conatiner
	ctx->selected_cnt = id;

	return handle_container(ctx, cnt);
}


// TODO: return an error indicating that no container exists with that name 
int ug_container_remove(ug_ctx_t *ctx, const char *name)
{
	TEST_CTX(ctx);
	TEST_STR(name);

	ug_id_t id = hash(name, strlen(name));
	ug_container_t *c = search_container(ctx, id);
	if (c) {
		c->flags |= CNT_STATE_DELETE;
		return 0;
	} else return -1;
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

	ctx->mouse.update  |= mask;

	return 0;
}


int ug_input_mouseup(ug_ctx_t *ctx, unsigned int mask)
{
	TEST_CTX(ctx);

	ctx->mouse.update |= mask;

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

	// update mouse delta
	ctx->mouse.delta.x = ctx->mouse.pos.x - ctx->mouse.last_pos.x;
	ctx->mouse.delta.y = ctx->mouse.pos.y - ctx->mouse.last_pos.y;
	
	// clear command stack
	RESET_STACK(ctx->cmd_stack);

	// update the origin
	ctx->origin.x = 0;
	ctx->origin.y = 0;
	ctx->origin.w = ctx->size.w;
	ctx->origin.h = ctx->size.h;

	// update hover index
	printf("Container Stack: active %x\n", ctx->active.cnt);
	ug_vec2_t v = ctx->mouse.pos;
	for (int i = 0; i < ctx->cnt_stack.idx; i++) {
		ug_container_t *c = &ctx->cnt_stack.items[i];

		printf("[%d]: %x\n", i, c->id);
		if (TEST(c->flags, CNT_STATE_DELETE)) {
			DELETE_FROM_STACK(ctx->cnt_stack, c);
			// FIXME: this should be fine since all elements in the
			//        stack are moved back and c now points to the
			//        container that would be next
		}

		ug_rect_t r = c->rca;
		if (INTERSECTS(v, r))
			ctx->hover.cnt = c->id;
	}
	printf("\n");

	if (ctx->last_active.cnt && ctx->active.cnt != ctx->last_active.cnt)
		ctx->cnt_stack.sorted = 0;

	// update active container
	if (MOUSEDOWN(ctx, UG_BTN_LEFT)) {
		ctx->active.cnt = ctx->hover.cnt;
	} else if (MOUSEUP(ctx, UG_BTN_LEFT)) {
		ctx->last_active.cnt = ctx->active.cnt;
		ctx->active.cnt = 0;
	}

	return 0;
}


// At the end of a frame reset inputs
int ug_frame_end(ug_ctx_t *ctx)
{
	TEST_CTX(ctx);

	// before drawing floating contaners need to be drawn on top of the others
	sort_containers(ctx);
	for (int i = 0; i < ctx->cnt_stack.idx; i++) {
		ug_container_t *c = &ctx->cnt_stack.items[i];
		draw_container(ctx, c, c->name);
	}

	ctx->input_text[0]      = '\0';
	ctx->key.update         = 0;
	ctx->mouse.hold        ^= ctx->mouse.update;
	ctx->mouse.update       = 0;
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

	// deselect container
	ctx->selected_cnt = 0;

	ctx->cmd_it = 0;

	return 0;
}
