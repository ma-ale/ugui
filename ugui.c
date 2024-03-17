#define _DEFAULT_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "raylib.h"
#include "ugui.h"
#include "timer.h"

#define RGBA(u)                                                                     \
	(UgColor)                                                                   \
	{                                                                           \
		.r = (u >> 24) & 0xff, .g = (u >> 16) & 0xff, .b = (u >> 8) & 0xff, \
		.a = (u >> 0) & 0xff                                                \
	}
#define DIV_FILL                                                                    \
	(UgRect) { .x = 0, .y = 0, .w = 0, .h = 0 }

#define MARK()                                                                      \
	do {                                                                        \
		printf("================== lmao ==================\n");             \
	} while (0)

#define BIT(x)             (1 << (x))
#define FTEST(e, f)        ((e)->flags & (f))
#define MAX(a, b)          ((a) > (b) ? (a) : (b))
#define MIN(a, b)          ((a) < (b) ? (a) : (b))
#define ABS(a)             ((a) < 0 ? -(a) : (a))
#define CLAMP(x, min, max) ((x) < (min) ? (min) : ((x) > (max) ? (max) : (x)))

#define STACK_STEP 10
#define MAX_ELEMS  128
#define MAX_CMDS   256
#define ROOT_ID    1

typedef struct _UgCmd {
	enum {
		CMD_RECT = 0,
	} type;

	union {
		struct {
			UgRect  rect;
			UgColor color;
		} rect;
	};
} UgCmd;

typedef struct _UgFifo {
	int    size, in, out, count;
	UgCmd *vec;
} UgFifo;

int ug_fifo_init(UgFifo *fifo, uint32_t size);
int ug_fifo_free(UgFifo *fifo);
int ug_fifo_enqueue(UgFifo *fifo, UgCmd *cmd);
int ug_fifo_dequeue(UgFifo *fifo, UgCmd *cmd);

int ug_fifo_init(UgFifo *fifo, uint32_t size)
{
	if (fifo == NULL) {
		return -1;
	}

	fifo->size  = size;
	fifo->in    = 0;
	fifo->out   = 0;
	fifo->count = 0;
	fifo->vec   = calloc(size, sizeof(UgCmd));

	if (fifo->vec == NULL) {
		return -1;
	}

	return 0;
}

int ug_fifo_free(UgFifo *fifo)
{
	if (fifo != NULL && fifo->vec != NULL) {
		free(fifo->vec);
		fifo->size  = 0;
		fifo->in    = 0;
		fifo->out   = 0;
		fifo->count = 0;
	}
	return 0;
}

#define FIFO_STEP 10

int ug_fifo_enqueue(UgFifo *fifo, UgCmd *cmd)
{
	if (fifo == NULL || cmd == NULL) {
		return -1;
	}

	if (fifo->count >= fifo->size) {
		//	UgCmd *tmp = reallocarray(fifo->vec, fifo->size +
		// fifo_STEP, sizeof(UgCmd)); 	if (tmp == NULL) { return -1;
		//	}
		//	fifo->vec = tmp;
		//	fifo->size += fifo_STEP;
		return -1;
	}

	fifo->vec[fifo->in] = *cmd;

	fifo->in = (fifo->in + 1) % fifo->size;
	fifo->count++;

	return 0;
}

int ug_fifo_dequeue(UgFifo *fifo, UgCmd *cmd)
{
	if (fifo == NULL || cmd == NULL) {
		return -1;
	}

	if (fifo->count <= 0) {
		//	UgCmd *tmp = reallocarray(fifo->vec, fifo->size +
		// fifo_STEP, sizeof(UgCmd)); 	if (tmp == NULL) { return -1;
		//	}
		//	fifo->vec = tmp;
		//	fifo->size += fifo_STEP;
		return -1;
	}

	*cmd = fifo->vec[fifo->out];

	fifo->out = (fifo->out + 1) % fifo->size;
	fifo->count--;

	return 0;
}

enum InputEventFlags {
	INPUT_CTX_SIZE      = 1 << 0, // window size was changed
	INPUT_CTX_FOCUS     = 1 << 1, // window focus changed
	INPUT_CTX_MOUSEMOVE = 1 << 2, // mouse was moved
	INPUT_CTX_MOUSEBTN  = 1 << 3, // mouse button pressed or released
};

struct _UgCtx {
	enum {
		row = 0,
		column,
		floating,
	} layout;

	UgTree      tree;
	UgElemCache cache;
	UgFifo      fifo;

	struct {
		int width, height;
	} size;

	struct { // css box model
		UgRect  padding;
		UgRect  border;
		UgRect  margin;
		UgColor bgcolor; // background color
		UgColor fgcolor; // foreground color
		UgColor bcolor;  // border color
	} style;

	// input structure, it describes the events received between frames
	struct {
		// flags: lists which input events have been received
		uint32_t flags;
		int      has_focus;
		UgPoint  mouse_pos, mouse_delta;
		// mouse_down:      bitmap of mouse buttons that are held
		// mouse_updated:   bitmap of mouse buttons that have been updated
		// mouse_released = mouse_updated & ~mouse_down
		// mouse_pressed  = mouse_updated & mouse_down
		uint32_t mouse_down;
		uint32_t mouse_updated;
	} input;

	int div_using; // tree node indicating the current active div
};

// layouting
int ug_layout_set_row(UgCtx *ctx);
int ug_layout_set_column(UgCtx *ctx);
int ug_layout_set_floating(UgCtx *ctx);
// these reset the offsets introduced by the previous elements
int ug_layout_next_row(UgCtx *ctx);
int ug_layout_next_column(UgCtx *ctx);

int ug_div_begin(UgCtx *ctx, const char *label, UgRect div);
int ug_div_end(UgCtx *ctx);
int ug_input_window_size(UgCtx *ctx, int width, int height);

// static UgId djb2(const char *str);
static UgId FNV_1a(const char *str);

int ug_button(UgCtx *ctx, const char *label, UgRect size);

static UgRect position_element(UgCtx *ctx, UgElem *parent, UgRect rect, int style);

// search the element of the corresponding id in the cache, if no element is found
// insert a new one of that id. Return the pointer to the element
static int search_or_insert(UgCtx *ctx, UgElem **elem, UgId id)
{
	int      is_new = 0;
	uint32_t cache_idx;

	UgElem *c_elem = ug_cache_search(&ctx->cache, id);
	if (c_elem == NULL) {
		UgElem tmp = {.id = id};
		c_elem     = ug_cache_insert_new(&ctx->cache, &tmp, &cache_idx);
		is_new     = 1;
	}

	*elem = c_elem;
	return is_new;
}

static int is_point_in_rect(UgPoint p, UgRect r)
{
	if ((p.x >= r.x && p.x <= r.x + r.w) && (p.y >= r.y && p.y <= r.y + r.h)) {
		return 1;
	}
	return 0;
}

static int get_parent(UgCtx *ctx, UgElem **parent)
{
	// take a reference to the parent
	// FIXME: if the tree held pointers to the elements then no more
	//        redundant cache search
	UgId parent_id = ug_tree_get(&ctx->tree, ctx->div_using);
	*parent        = ug_cache_search(&ctx->cache, parent_id);
	if (parent == NULL) {
		// Error, did you forget to do frame_begin()?
		return -1;
	}

	return 0;
}

int ug_init(UgCtx *ctx)
{
	if (ctx == NULL) {
		return -1;
	}

	*ctx = (UgCtx) {0};

	ug_tree_init(&ctx->tree, MAX_ELEMS);
	ug_fifo_init(&ctx->fifo, MAX_CMDS);

	ctx->cache     = ug_cache_init();
	ctx->layout    = row;
	ctx->div_using = 0;

	// TODO: add style config
	ctx->style.margin  = (UgRect) {1, 1, 1, 1};
	ctx->style.padding = (UgRect) {0};
	ctx->style.border  = (UgRect) {0};

	ctx->style.bgcolor = (UgColor) {0};
	ctx->style.fgcolor = (UgColor) {0};
	ctx->style.bcolor  = (UgColor) {0};

	return 0;
}

int ug_destroy(UgCtx *ctx)
{
	if (ctx == NULL) {
		return -1;
	}

	ug_tree_destroy(&ctx->tree);
	ug_cache_free(&ctx->cache);
	ug_fifo_free(&ctx->fifo);

	return 0;
}

static void print_tree(UgCtx *ctx)
{
	printf("ctx->tree: [");
	for (int c = -1, x; (x = ug_tree_level_order_it(&ctx->tree, 0, &c)) != -1;) {
		printf(
		    "[%d:%d,%.4lx], ",
		    x,
		    ug_tree_parentof(&ctx->tree, x),
		    ug_tree_get(&ctx->tree, x) & 0xffff
		);
	}
	printf("[-1]]\n");
}

int ug_frame_begin(UgCtx *ctx)
{
	if (ctx == NULL) {
		return -1;
	}

	// 1. Create the root div element
	UgRect space = {
	    .x = 0,
	    .y = 0,
	    .w = ctx->size.width,
	    .h = ctx->size.height,
	};
	UgElem root = {
	    .id    = ROOT_ID,
	    .type  = ETYPE_DIV,
	    .flags = 0,
	    .event = 0,
	    .rect  = space,
	    .div =
		{
		    .layout   = DIV_LAYOUT_ROW,
		    .origin_r = {0},
		    .origin_c = {0},
		    .color_bg = {0},
		},
	};

	// The root should have the updated flag only if the size of the window
	// was changed between frames, this propagates an element size recalculation
	// down the element tree
	if (ctx->input.flags & INPUT_CTX_SIZE) {
		root.flags |= ELEM_UPDATED;
	}

	// if the window has focus then the root element also has focus, no other
	// computation needed, child elements need to check the mouse positon and
	// other stuff
	if (ctx->input.has_focus) {
		root.flags |= ELEM_HASFOCUS;
	}

	// FIXME: check errors
	// 2. Get the root element from the cache and update it
	UgElem *c_elem;
	int     is_new = search_or_insert(ctx, &c_elem, root.id);

	// flags always need to be set to the new flags
	c_elem->flags = root.flags;

	if (is_new || FTEST(&root, ELEM_UPDATED)) {
		*c_elem = root;
	}

	// 3. Push the root element into the element tree
	ctx->div_using = ug_tree_add(&ctx->tree, root.id, 0);

	if (ctx->div_using < 0) {
		printf("why?\n");
		return -1;
	}

	// print_tree(ctx);

	// The root element does not push anything to the stack
	// TODO: add a background color taken from a theme or config

	printf("##### Frame Begin #####\n");

	return 0;
}

int ug_frame_end(UgCtx *ctx)
{
	if (ctx == NULL) {
		return -1;
	}

	// 1. clear the tree
	ug_tree_prune(&ctx->tree, 0);

	// 2. clear input fields
	ctx->input.flags = 0;

// draw mouse position
#if 1
	UgCmd cmd = {
	    .type = CMD_RECT,
	    .rect =
		{
		    .rect =
			{
			    .x = ctx->input.mouse_pos.x - 2,
			    .y = ctx->input.mouse_pos.y - 2,
			    .w = 4,
			    .h = 4,
			},
		    .color = RGBA(0xff00ffff),
		},
	};
	ug_fifo_enqueue(&(ctx->fifo), &cmd);
#endif

	printf("##### Frame End #####\n\n");
	return 0;
}

// Window size was changed
int ug_input_window_size(UgCtx *ctx, int width, int height)
{
	if (ctx == NULL) {
		return -1;
	}

	if (width <= 0 || height <= 0) {
		return -1;
	}

	if (width >= 0) {
		ctx->size.width = width;
	}
	if (height >= 0) {
		ctx->size.height = height;
	}

	ctx->input.flags |= INPUT_CTX_SIZE;

	return 0;
}

// Window gained/lost focus
int ug_input_changefoucs(UgCtx *ctx, int has_focus)
{
	if (ctx == NULL) {
		return -1;
	}

	// FIXME: raylib only has an API to query the focus status so we have to
	//        update the input flag only if the focus changed
	if (ctx->input.has_focus != (!!has_focus)) {
		ctx->input.flags |= INPUT_CTX_FOCUS;
	}
	ctx->input.has_focus = !!has_focus;

	return 0;
}

enum ug_mouse_buttons {
	UG_BTN_LEFT   = BIT(0),
	UG_BTN_MIDDLE = BIT(1),
	UG_BTN_RIGHT  = BIT(2),
	UG_BTN_4      = BIT(3),
	UG_BTN_5      = BIT(4),
};

const uint32_t mouse_supported_mask =
    UG_BTN_LEFT | UG_BTN_MIDDLE | UG_BTN_RIGHT | UG_BTN_4 | UG_BTN_5;

// Mouse Button moved
int ug_input_mouse_button(UgCtx *ctx, uint32_t button_mask)
{
	if (ctx == NULL) {
		return -1;
	}

	if (button_mask & ~mouse_supported_mask) {
		return -1;
	}

	ctx->input.mouse_updated = ctx->input.mouse_down ^ button_mask;
	ctx->input.mouse_down    = button_mask;
	ctx->input.flags |= INPUT_CTX_MOUSEBTN;

	printf(
	    "Mouse Down: %s%s%s%s%s\n",
	    button_mask & UG_BTN_LEFT ? "BTN_LEFT " : "",
	    button_mask & UG_BTN_RIGHT ? "BTN_RIGHT " : "",
	    button_mask & UG_BTN_MIDDLE ? "BTN_MIDDLE " : "",
	    button_mask & UG_BTN_4 ? "BTN_4 " : "",
	    button_mask & UG_BTN_5 ? "BTN_5 " : ""
	);
	return 0;
}

// Mouse was moved, report absolute position
int ug_input_mouse_abs(UgCtx *ctx, int x, int y) { return 1; }

// Mouse was moved, report relative motion
int ug_input_mouse_delta(UgCtx *ctx, int dx, int dy)
{
	if (ctx == NULL) {
		return -1;
	}

	ctx->input.mouse_delta.x = dx;
	ctx->input.mouse_delta.y = dy;

	int mx, my;
	mx = ctx->input.mouse_pos.x + dx;
	my = ctx->input.mouse_pos.y + dy;

	ctx->input.mouse_pos.x = CLAMP(mx, 0, ctx->size.width);
	ctx->input.mouse_pos.y = CLAMP(my, 0, ctx->size.height);

	ctx->input.flags |= INPUT_CTX_MOUSEMOVE;

	return 0;
}

static UgId FNV_1a(const char *str)
{
	const uint64_t fnv_off   = 0xcbf29ce484222325;
	const uint64_t fnv_prime = 0x100000001b3;

	uint64_t hash = fnv_off;
	for (uint32_t c; (c = str[0]) != 0; str++) {
		hash ^= c;
		hash *= fnv_prime;
	}

	return hash;
}

#if 0
static UgId djb2(const char *str)
{
	uint64_t hash = 5381;
	uint32_t c;

	while ((c = (str++)[0]) != 0) {
		hash = ((hash << 5) + hash) + c;
	} /* hash * 33 + c */

	return hash;
}
#endif

int ug_div_begin(UgCtx *ctx, const char *label, UgRect div)
{
	if (ctx == NULL || label == NULL) {
		return -1;
	}

	UgId id = FNV_1a(label);

	UgElem *c_elem;
	int     is_new = search_or_insert(ctx, &c_elem, id);

	// FIXME: why save the id in the tree and not something more direct like
	//        the element pointer or the index into the cache vector?
	int div_node = ug_tree_add(&ctx->tree, id, ctx->div_using);
	if (div_node < 0) {
		// do something
		printf("Error adding to tree\n");
	}

	UgElem *parent;
	if (get_parent(ctx, &parent)) {
		return -1;
	}

	print_tree(ctx);

	// Use the current div
	ctx->div_using = div_node;

	// 1. Fill the element fields
	// this resets the flags
	c_elem->type  = ETYPE_DIV;
	c_elem->flags = 0;

	// do layout and update flags only if the element was updated
	if (is_new || FTEST(parent, ELEM_UPDATED)) {
		// 2. layout the element
		c_elem->rect = position_element(ctx, parent, div, 0);

		// 3. Mark the element as updated
		c_elem->flags |= ELEM_UPDATED;

		// 4. Fill the div fields
		c_elem->div.layout   = parent->div.layout;
		c_elem->div.origin_c = (UgPoint) {
		    .x = c_elem->rect.x,
		    .y = c_elem->rect.y,
		};
		c_elem->div.color_bg = RGBA(0xff0000ff);
		c_elem->div.origin_r = c_elem->div.origin_c;
	} else if (FTEST(parent, ELEM_HASFOCUS)) {
		if (is_point_in_rect(ctx->input.mouse_pos, c_elem->rect)) {
			c_elem->flags |= ELEM_HASFOCUS;
		}
	} else {
		// TODO: check active
		// TODO: check scrollbars
		// TODO: check resizeable
	}

	// Add the background to the draw stack
	UgCmd cmd = {
	    .type = CMD_RECT,
	    .rect =
		{
		    .rect  = c_elem->rect,
		    .color = c_elem->div.color_bg,
		},
	};
	ug_fifo_enqueue(&ctx->fifo, &cmd);

	return 0;
}

int ug_div_end(UgCtx *ctx)
{
	// the div_using returns to the parent of the current one
	ctx->div_using = ug_tree_parentof(&ctx->tree, ctx->div_using);
	return 0;
}

// position the rectangle inside the parent according to the layout
static UgRect position_element(UgCtx *ctx, UgElem *parent, UgRect rect, int style)
{
	UgRect  elem_rect = {0};
	UgPoint origin    = {0};

	// 1. Select the right origin
	switch (parent->div.layout) {
	case DIV_LAYOUT_ROW:
		origin = parent->div.origin_r;
		break;
	case DIV_LAYOUT_COLUMN:
		origin = parent->div.origin_c;
		break;
	case DIV_LAYOUT_FLOATING: // none
	default:
		// Error
		break;
	}

	// 2. Position the rect
	elem_rect.x = origin.x + rect.x;
	elem_rect.y = origin.y + rect.y;

	// 3. Calculate width & height
	// TODO: what about negative values?
	// FIXME: account for origin offset!!
	elem_rect.w = rect.w > 0 ? rect.w : parent->rect.w;
	elem_rect.h = rect.h > 0 ? rect.h : parent->rect.h;

	// 4. Update the origins of the parent
	parent->div.origin_r = (UgPoint) {
	    .x = elem_rect.x + elem_rect.w,
	    .y = elem_rect.y,
	};
	parent->div.origin_c = (UgPoint) {
	    .x = elem_rect.x,
	    .y = elem_rect.y + elem_rect.h,
	};

	// if using the style then apply margins
	// FIXME: this does not work
	if (style && parent->div.layout != DIV_LAYOUT_FLOATING) {
		elem_rect.x += ctx->style.margin.x;
		elem_rect.y += ctx->style.margin.y;

		// total keep-out borders
		UgRect margin_tot = {
		    .x = ctx->style.padding.x + ctx->style.border.x +
		         ctx->style.margin.x,
		    .y = ctx->style.padding.y + ctx->style.border.y +
		         ctx->style.margin.y,
		    .w = ctx->style.padding.w + ctx->style.border.x +
		         ctx->style.margin.w,
		    .h = ctx->style.padding.h + ctx->style.border.x +
		         ctx->style.margin.h,
		};

		parent->div.origin_r.x += margin_tot.x + margin_tot.w;
		// parent->div.origin_r.y += margin_tot.h;

		// parent->div.origin_c.x += margin_tot.w;
		parent->div.origin_c.y += margin_tot.y + margin_tot.h;
	}

	/*
	        printf(
	            "positioning rect: %lx {%d %d %d %d}(%d %d %d %d) -> {%d %d %d
	   %d}\n", parent->id, rect.x, rect.y, rect.w, rect.h, parent->rect.x,
	            parent->rect.y,
	            parent->rect.w,
	            parent->rect.h,
	            elem_rect.x,
	            elem_rect.y,
	            elem_rect.w,
	            elem_rect.h
	        );
	*/
	return elem_rect;
}

int is_hovered(UgCtx *ctx, UgElem *elem)
{
	if (ctx == NULL || elem == NULL) {
		return 0;
	}
	return is_point_in_rect(ctx->input.mouse_pos, elem->rect);
}

int ug_button(UgCtx *ctx, const char *label, UgRect size)
{
	if (ctx == NULL || label == NULL) {
		return -1;
	}

	UgId id = FNV_1a(label);

	// TODO: do layouting if the element is new or the parent has updated
	UgElem *c_elem;
	int     is_new = search_or_insert(ctx, &c_elem, id);

	// add it to the tree
	ug_tree_add(&ctx->tree, id, ctx->div_using);
	print_tree(ctx);

	UgElem *parent;
	if (get_parent(ctx, &parent)) {
		return -1;
	}

	// 1. Fill the element fields
	// this resets the flags
	c_elem->type     = ETYPE_BUTTON;
	c_elem->flags    = 0;
	UgColor bg_color = RGBA(0x0000ffff);

	// if the element is new or the parent was updated then redo layout
	if (is_new || FTEST(parent, ELEM_UPDATED)) {
		// 2. Layout
		c_elem->rect = position_element(ctx, parent, size, 1);

		// TODO: 3. Fill the button specific fields
	}

	// TODO: Check for interactions
	if (FTEST(parent, ELEM_HASFOCUS)) {
		if (is_hovered(ctx, c_elem)) {
			c_elem->flags |= ELEM_HASFOCUS;
			c_elem->event |= EVENT_MOUSE_HOVER;
			bg_color = RGBA(0x00ff00ff);

			if (ctx->input.mouse_down & UG_BTN_LEFT) {
				c_elem->event |= EVENT_MOUSE_HOLD;
			} else {
				c_elem->event &= ~EVENT_MOUSE_HOLD;
			}
		} else {
			c_elem->event &= ~EVENT_MOUSE_HOVER;
		}
	}

	// Draw the button
	UgCmd cmd = {
	    .type = CMD_RECT,
	    .rect =
		{
		    .rect  = c_elem->rect,
		    .color = bg_color,
		},
	};
	ug_fifo_enqueue(&ctx->fifo, &cmd);

	return c_elem->event;
}

int ug_layout_set_row(UgCtx *ctx)
{
	if (ctx == NULL) {
		return -1;
	}

	UgId    parent_id = ug_tree_get(&ctx->tree, ctx->div_using);
	UgElem *parent    = ug_cache_search(&ctx->cache, parent_id);
	if (parent == NULL) {
		// Error, did you forget to do frame_begin()?
		return -1;
	}

	if (parent->type != ETYPE_DIV) {
		// what?
		return -1;
	}

	parent->div.layout = DIV_LAYOUT_ROW;

	return 0;
}

int ug_layout_set_column(UgCtx *ctx)
{
	if (ctx == NULL) {
		return -1;
	}

	UgId    parent_id = ug_tree_get(&ctx->tree, ctx->div_using);
	UgElem *parent    = ug_cache_search(&ctx->cache, parent_id);
	if (parent == NULL) {
		// Error, did you forget to do frame_begin()?
		return -1;
	}

	if (parent->type != ETYPE_DIV) {
		// what?
		return -1;
	}

	parent->div.layout = DIV_LAYOUT_COLUMN;

	return 0;
}

int ug_layout_set_floating(UgCtx *ctx)
{
	if (ctx == NULL) {
		return -1;
	}

	UgId    parent_id = ug_tree_get(&ctx->tree, ctx->div_using);
	UgElem *parent    = ug_cache_search(&ctx->cache, parent_id);
	if (parent == NULL) {
		// Error, did you forget to do frame_begin()?
		return -1;
	}

	if (parent->type != ETYPE_DIV) {
		// what?
		return -1;
	}

	parent->div.layout = DIV_LAYOUT_FLOATING;

	return 0;
}

int ug_layout_next_row(UgCtx *ctx)
{
	if (ctx == NULL) {
		return -1;
	}

	UgId    parent_id = ug_tree_get(&ctx->tree, ctx->div_using);
	UgElem *parent    = ug_cache_search(&ctx->cache, parent_id);
	if (parent == NULL) {
		// Error, did you forget to do frame_begin()?
		return -1;
	}

	if (parent->type != ETYPE_DIV) {
		// what?
		return -1;
	}

	parent->div.origin_r = (UgPoint) {
	    .x = parent->rect.x,
	    .y = parent->div.origin_c.y,
	};

	parent->div.origin_c = parent->div.origin_r;

	return 0;
}

int ug_layout_next_column(UgCtx *ctx)
{
	if (ctx == NULL) {
		return -1;
	}

	UgId    parent_id = ug_tree_get(&ctx->tree, ctx->div_using);
	UgElem *parent    = ug_cache_search(&ctx->cache, parent_id);
	if (parent == NULL) {
		// Error, did you forget to do frame_begin()?
		return -1;
	}

	if (parent->type != ETYPE_DIV) {
		// what?
		return -1;
	}

	parent->div.origin_c = (UgPoint) {
	    .x = parent->div.origin_r.x,
	    .y = parent->rect.y,
	};

	parent->div.origin_r = parent->div.origin_c;

	return 0;
}

#if 1
int main(void)
{
	UgCtx ctx;
	ug_init(&ctx);

	int width = 800, height = 450;
	SetConfigFlags(FLAG_WINDOW_RESIZABLE);
	InitWindow(width, height, "Ugui Test");
	ug_input_window_size(&ctx, width, height);

	double median_times[10][4] = {0};
	size_t frame               = 0;
	double median_input, median_layout, median_draw, median_tot;

	// Main loop
	while (!WindowShouldClose()) {
		const int PARTIAL_INPUT  = 0;
		const int PARTIAL_LAYOUT = 1;
		const int PARTIAL_DRAW   = 2;
		timer_start();

		/*** Start Input Handling ***/
		if (IsWindowResized()) {
			width  = GetScreenWidth();
			height = GetScreenHeight();
			ug_input_window_size(&ctx, width, height);
		}

		ug_input_changefoucs(&ctx, IsWindowFocused());

		// FIXME: In raylib it doesn't seem to be a quick way to check if
		//        a mouse input event was received, so for now just use
		//        the delta information
		Vector2 mousedelta = GetMouseDelta();
		if (mousedelta.x || mousedelta.y) {
			ug_input_mouse_delta(&ctx, mousedelta.x, mousedelta.y);
		}

		uint32_t mask = 0;
		mask |= IsMouseButtonDown(MOUSE_BUTTON_LEFT) ? UG_BTN_LEFT : 0;
		mask |= IsMouseButtonDown(MOUSE_BUTTON_RIGHT) ? UG_BTN_RIGHT : 0;
		mask |= IsMouseButtonDown(MOUSE_BUTTON_MIDDLE) ? UG_BTN_MIDDLE : 0;
		ug_input_mouse_button(&ctx, mask);

		timer_partial(PARTIAL_INPUT);
		/*** End Input Handling ***/

		/*** Start UI Handling ***/
		ug_frame_begin(&ctx);

		// main div, fill the whole window
		ug_div_begin(&ctx, "main", DIV_FILL);
		{
			ug_layout_set_column(&ctx);
			if (ug_button(
				&ctx,
				"button0",
				(UgRect) {.y = 100, .x = 100, .w = 30, .h = 30}
			    ) &
			    EVENT_MOUSE_HOLD) {
				printf("HOLDING button0\n");
			}
			ug_layout_next_column(&ctx);
			ug_button(&ctx, "button1", (UgRect) {.w = 30, .h = 30});
			ug_layout_next_column(&ctx);
			ug_button(&ctx, "button2", (UgRect) {.w = 30, .h = 30});
		}
		ug_div_end(&ctx);

		ug_frame_end(&ctx);
		timer_partial(PARTIAL_LAYOUT);
		/*** End UI Handling ***/

		/*** Start UI Drawing ***/
		BeginDrawing();
		// ClearBackground(BLACK);

		printf("----- Draw Begin -----\n");
		Color c;
		for (UgCmd cmd; ug_fifo_dequeue(&ctx.fifo, &cmd) >= 0;) {
			switch (cmd.type) {
			case CMD_RECT:
				printf(
				    "draw rect x=%d y=%d w=%d h=%d\n",
				    cmd.rect.rect.x,
				    cmd.rect.rect.y,
				    cmd.rect.rect.w,
				    cmd.rect.rect.h
				);
				c = (Color) {
				    .r = cmd.rect.color.r,
				    .g = cmd.rect.color.g,
				    .b = cmd.rect.color.b,
				    .a = cmd.rect.color.a,
				};
				DrawRectangle(
				    cmd.rect.rect.x,
				    cmd.rect.rect.y,
				    cmd.rect.rect.w,
				    cmd.rect.rect.h,
				    c
				);
				break;
			default:
				printf("Unknown cmd type: %d\n", cmd.type);
				break;
			}
		}
		printf("----- Draw End -----\n\n");

		EndDrawing();
		timer_partial(PARTIAL_DRAW);
		timer_stop();
		/*** End UI Drawing ***/

		median_times[frame][PARTIAL_INPUT] =
		    1e3 * timer_get_sec(PARTIAL_INPUT);
		median_times[frame][PARTIAL_LAYOUT] =
		    1e3 * timer_get_sec(PARTIAL_LAYOUT);
		median_times[frame][PARTIAL_DRAW] =
		    1e3 * timer_get_sec(PARTIAL_DRAW);
		median_times[frame][3] = 1e3 * timer_get_sec(-1);

		frame += 1;
		frame %= 10;

		if (frame == 0) {
			median_input  = 0;
			median_layout = 0;
			median_draw   = 0;
			median_tot    = 0;
			for (size_t i = 0; i < 10; i++) {
				median_input += median_times[i][PARTIAL_INPUT];
				median_layout += median_times[i][PARTIAL_LAYOUT];
				median_draw += median_times[i][PARTIAL_DRAW];
				median_tot += median_times[i][3];
			}
			median_input /= 10;
			median_layout /= 10;
			median_draw /= 10;
			median_tot /= 10;
		}

		printf("input time: %lfms\n", median_input);
		printf("layout time: %lfms\n", median_layout);
		printf("draw time: %lfms\n", median_draw);
		printf("total time: %lfms\n", median_tot);

		// Throttle Frames
		// TODO: add an fps limit, time frame generation and log it
		const float TARGET_FPS = 100;
		float wait_time = MAX((1.0 / TARGET_FPS) - timer_get_sec(-1), 0);
		WaitTime(wait_time);
	}

	CloseWindow();

	ug_destroy(&ctx);
	return 0;
}
#endif
