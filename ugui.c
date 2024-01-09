#define _DEFAULT_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "raylib.h"
#include "ugui.h"

#define RGBA(u)                                                                     \
	(UgColor)                                                                   \
	{                                                                           \
		.r = (u >> 24) & 0xff, .g = (u >> 16) & 0xff, .b = (u >> 8) & 0xff, \
		.a = (u >> 0) & 0xff                                                \
	}
#define DIV_FILL                                                                    \
	(UgRect) { .x = 0, .y = 0, .w = 0, .h = 0 }

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

typedef struct _UgStack {
	int    size, count;
	UgCmd *stack;
} UgStack;

int ug_stack_init(UgStack *stack, uint32_t size);
int ug_stack_free(UgStack *stack);
int ug_stack_push(UgStack *stack, UgCmd *cmd);
int ug_stack_pop(UgStack *stack, UgCmd *cmd);

int ug_stack_init(UgStack *stack, uint32_t size)
{
	if (stack == NULL) {
		return -1;
	}

	stack->size  = size;
	stack->count = 0;
	stack->stack = calloc(size, sizeof(UgCmd));

	if (stack->stack == NULL) {
		return -1;
	}

	return 0;
}

int ug_stack_free(UgStack *stack)
{
	if (stack != NULL && stack->stack != NULL) {
		free(stack->stack);
		stack->size  = 0;
		stack->count = 0;
	}
	return 0;
}

int ug_stack_push(UgStack *stack, UgCmd *cmd)
{
	if (stack == NULL || cmd == NULL) {
		return -1;
	}

	if (stack->count >= stack->size) {
		//	UgCmd *tmp = reallocarray(stack->stack, stack->size +
		// STACK_STEP, sizeof(UgCmd)); 	if (tmp == NULL) { return -1;
		//	}
		//	stack->stack = tmp;
		//	stack->size += STACK_STEP;
		return -1;
	}

	stack->stack[stack->count++] = *cmd;

	return 0;
}

int ug_stack_pop(UgStack *stack, UgCmd *cmd)
{
	if (stack == NULL || cmd == NULL) {
		return -1;
	}

	if (stack->count <= 0) {
		//	UgCmd *tmp = reallocarray(stack->stack, stack->size +
		// STACK_STEP, sizeof(UgCmd)); 	if (tmp == NULL) { return -1;
		//	}
		//	stack->stack = tmp;
		//	stack->size += STACK_STEP;
		return -1;
	}

	*cmd = stack->stack[--stack->count];

	return 0;
}

enum InputEventFlags {
	INPUT_CTX_SIZE = 1 << 0, // window size was changed
};

struct _UgCtx {
	enum {
		row = 0,
		column,
		floating,
	} layout;

	UgTree      tree;
	UgElemCache cache;
	UgStack     stack;

	struct {
		int width, height;
	} size;

	// input structure, it describes the events received between frames
	struct {
		uint32_t flags;
	} input;

	int div_using; // tree node indicating the current active div
};

// layouting
int ug_layout_row(void);
int ug_layout_column(void);
int ug_layout_floating(void);
int ug_layout_next_row(void);
int ug_layout_next_column(void);

int  ug_div_begin(UgCtx *ctx, const char *label, UgRect div);
int  ug_div_end(UgCtx *ctx);
int  ug_input_window_size(UgCtx *ctx, int width, int height);
UgId djb2(const char *str);

int ug_button(UgCtx *ctx, const char *label, UgRect size);


int main(void)
{
	UgCtx ctx;
	ug_init(&ctx);

	int width = 800, height = 450;
	SetConfigFlags(FLAG_WINDOW_RESIZABLE);
	InitWindow(width, height, "Ugui Test");
	ug_input_window_size(&ctx, width, height);

	// Main loop
	while (!WindowShouldClose()) {

		// Input handling
		if (IsWindowResized()) {
			width  = GetScreenWidth();
			height = GetScreenHeight();
			ug_input_window_size(&ctx, width, height);
		}

		// UI handling
		ug_frame_begin(&ctx);

		// main div, fill the whole window
		ug_div_begin(&ctx, "main", DIV_FILL);

		ug_button(&ctx, "button0", (UgRect){.w = 100, .h = 16});
		
		ug_div_end(&ctx);

		ug_frame_end(&ctx);

		// drawing
		BeginDrawing();
		ClearBackground(BLACK);

		Color c;
		for (UgCmd cmd; ug_stack_pop(&ctx.stack, &cmd) >= 0;) {
			printf("bruh\n");
			switch (cmd.type) {
			case CMD_RECT:
				//printf(
				//    "rect x=%d y=%d w=%d h=%d\n",
				//    cmd.rect.rect.x,
				//    cmd.rect.rect.y,
				//    cmd.rect.rect.w,
				//    cmd.rect.rect.h
				//);
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

		EndDrawing();

		WaitTime(0.2);
	}

	CloseWindow();

	ug_destroy(&ctx);
	return 0;
}

int ug_init(UgCtx *ctx)
{
	if (ctx == NULL) {
		return -1;
	}

	ug_tree_init(&ctx->tree, MAX_ELEMS);
	ug_stack_init(&ctx->stack, MAX_CMDS);

	ctx->cache     = ug_cache_init();
	ctx->layout    = row;
	ctx->div_using = 0;

	return 0;
}

int ug_destroy(UgCtx *ctx)
{
	if (ctx == NULL) {
		return -1;
	}

	ug_tree_destroy(&ctx->tree);
	ug_cache_free(&ctx->cache);

	return 0;
}

void print_tree(UgCtx *ctx)
{
	printf("ctx->tree: [");
	for (int c = -1, x; (x = ug_tree_level_order_it(&ctx->tree, 0, &c)) != -1;) {
		printf("%d, ", x);
	}
	printf("-1]\n");
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

	// FIXME: check errors
	uint32_t cache_idx;
	ug_cache_insert(&ctx->cache, &root, &cache_idx);
	ctx->div_using = ug_tree_add(&ctx->tree, root.id, 0);

	if (ctx->div_using < 0) {
		printf("why?\n");
		return -1;
	}

	//print_tree(ctx);

	// The root element does not push anything to the stack
	// TODO: add a background color taken from a theme or config

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

	return 0;
}

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

	return 0;
}

UgId djb2(const char *str)
{
	uint64_t hash = 5381;
	uint32_t c;

	while ((c = (str++)[0]) != 0) {
		hash = ((hash << 5) + hash) + c;
	} /* hash * 33 + c */

	return hash;
}

int ug_div_begin(UgCtx *ctx, const char *label, UgRect div)
{
	if (ctx == NULL || label == NULL) {
		return -1;
	}

	UgId id = djb2(label);

	// TODO: do layouting if the element is new or the parent has updated
	int is_new_elem = 0;

	// add the element if it does not exist
	UgElem *c_elem = ug_cache_search(&ctx->cache, id);
	if (c_elem == NULL) {
		UgElem   elem = {0};
		uint32_t c_idx;
		c_elem      = ug_cache_insert(&ctx->cache, &elem, &c_idx);
		is_new_elem = 1;
	}

	// take a reference to the parent
	// FIXME: if the tree held pointers to the elements then no more
	//        redundant cache search
	UgId    parent_id = ctx->tree.vector[ctx->div_using];
	UgElem *parent    = ug_cache_search(&ctx->cache, parent_id);
	if (parent == NULL) {
		// Error, did you forget to do frame_begin()?
		return -1;
	}

	// FIXME: why save the id in the tree and not something more direct like
	//        the element pointer or the index into the cache vector?
	int div_node = ug_tree_add(&ctx->tree, c_elem->id, ctx->div_using);
	if (div_node < 0) {
		// do something
		printf("Error adding to tree\n");
	}
	ctx->div_using = div_node;

	//print_tree(ctx);

	// layouting
	// TODO: do layout
	if (is_new_elem || parent->flags & ELEM_UPDATED) {
		c_elem->id   = id;
		c_elem->type = ETYPE_DIV;

		// 1. Select the right origin offset
		switch (parent->div.layout) {
		case DIV_LAYOUT_ROW:
			c_elem->rect = (UgRect) {
			    .x = parent->div.origin_r.x + div.x,
			    .y = parent->div.origin_r.y + div.y,
			};
			break;
		case DIV_LAYOUT_COLUMN:
			c_elem->rect = (UgRect) {
			    .x = parent->div.origin_c.x + div.x,
			    .y = parent->div.origin_c.y + div.y,
			};
			break;
		case DIV_LAYOUT_FLOATING:
			c_elem->rect = (UgRect) {
			    .x = div.x,
			    .y = div.y,
			};
			break;
		default:
			// Error
			break;
		}

		// 2. Calculate width & height
		// TODO: what about negative values?
		c_elem->rect.w = div.w != 0 ? div.w : parent->rect.w;
		c_elem->rect.h = div.h != 0 ? div.h : parent->rect.h;

		// 3. Mark the element as updated
		c_elem->flags |= ELEM_UPDATED;

		// 4. Set div information
		c_elem->div.layout   = parent->div.layout;
		c_elem->div.origin_c = (UgPoint) {
		    .x = c_elem->rect.x,
		    .y = c_elem->rect.y,
		};
		c_elem->div.origin_r = c_elem->div.origin_c;
		c_elem->div.color_bg = RGBA(0xff0000ff);

		// 4. Update the origins of the parent
		parent->div.origin_r = (UgPoint) {
		    .x = c_elem->rect.x + c_elem->rect.w,
		    .y = c_elem->rect.y,
		};
		parent->div.origin_c = (UgPoint) {
		    .x = c_elem->rect.x,
		    .y = c_elem->rect.y + c_elem->rect.h,
		};
	} else {
		// TODO: check active
		// TODO: check resizeable
		// TODO: check scrollbars
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
	ug_stack_push(&ctx->stack, &cmd);

	return 0;
}

int ug_div_end(UgCtx *ctx)
{
	// the div_using returns to the parent of the current one
	ctx->div_using = ug_tree_parentof(&ctx->tree, ctx->div_using);
	return 0;
}

int ug_button(UgCtx *ctx, const char *label, UgRect size)
{
	if (ctx == NULL || label == NULL) {
		return -1;
	}

	UgId id = djb2(label);

	// TODO: do layouting if the element is new or the parent has updated
	int is_new_elem = 0;

	// add the element if it does not exist
	UgElem *c_elem = ug_cache_search(&ctx->cache, id);
	if (c_elem == NULL) {
		UgElem   elem = {0};
		uint32_t c_idx;
		c_elem      = ug_cache_insert(&ctx->cache, &elem, &c_idx);
		is_new_elem = 1;
	}

	// take a reference to the parent
	// FIXME: if the tree held pointers to the elements then no more
	//        redundant cache search
	UgId    parent_id = ctx->tree.vector[ctx->div_using];
	UgElem *parent    = ug_cache_search(&ctx->cache, parent_id);
	if (parent == NULL) {
		// Error, did you forget to do frame_begin()?
		return -1;
	}

	// if the element is new or the parent was updated then redo layout
	if (is_new_elem || parent->flags & ELEM_UPDATED) {
		c_elem->id   = id;
		c_elem->type = ETYPE_BUTTON;

		// 1. Select the right origin offset
		switch (parent->div.layout) {
		case DIV_LAYOUT_ROW:
			c_elem->rect = (UgRect) {
			    .x = parent->div.origin_r.x + size.x,
			    .y = parent->div.origin_r.y + size.y,
			};
			break;
		case DIV_LAYOUT_COLUMN:
			c_elem->rect = (UgRect) {
			    .x = parent->div.origin_c.x + size.x,
			    .y = parent->div.origin_c.y + size.y,
			};
			break;
		case DIV_LAYOUT_FLOATING:
			c_elem->rect = (UgRect) {
			    .x = size.x,
			    .y = size.y,
			};
			break;
		default:
			// Error
			break;
		}

		// 2. Calculate width & height
		// TODO: what about negative values?
		c_elem->rect.w = size.w != 0 ? size.w : parent->rect.w;
		c_elem->rect.h = size.h != 0 ? size.h : parent->rect.h;

		/// Not a div, so not needed
		// 3. Mark the element as updated
		// 4. Set div information

		// 4. Update the origins of the parent
		parent->div.origin_r = (UgPoint) {
		    .x = c_elem->rect.x + c_elem->rect.w,
		    .y = c_elem->rect.y,
		};
		parent->div.origin_c = (UgPoint) {
		    .x = c_elem->rect.x,
		    .y = c_elem->rect.y + c_elem->rect.h,
		};
	} else {
		// TODO: Check for interactions
	}

	// Draw the button
	UgCmd cmd = {
	    .type = CMD_RECT,
	    .rect =
		{
		    .rect  = c_elem->rect,
		    .color = RGBA(0x0000ffff),
		},
	};
	ug_stack_push(&ctx->stack, &cmd);

	return 0;
}
