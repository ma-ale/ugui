#define _DEFAULT_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "raylib.h"
#include "ugui.h"

typedef struct _UgCmd {
	enum {
		CMD_RECT = 0,
	} type;

	union {
		struct {
			int32_t x, y, w, h;
			uint8_t color[4]; // rgba, [0] = r
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

	int div_using; // tree node indicating the current active div
};

int  ug_div_begin(UgCtx *ctx, const char *name, UgRect div);
int  ug_div_end(UgCtx *ctx);
int  ug_input_window_size(UgCtx *ctx, int width, int height);
UgId djb2(const char *str);

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

		// UI handling
		ug_frame_begin(&ctx);

		if (IsWindowResized()) {
			width  = GetScreenWidth();
			height = GetScreenHeight();
			ug_input_window_size(&ctx, width, height);
		}

// main div, fill the whole window
#define DIV_FILL (UgRect) {.x = 0, .y = 0, .w = -1, .h = -1}
		ug_div_begin(&ctx, "main", DIV_FILL);
		ug_div_end(&ctx);

		ug_frame_end(&ctx);

		// drawing
		BeginDrawing();
		ClearBackground(BLACK);

		Rectangle r;
		Color     c;
		for (UgCmd cmd; ug_fifo_dequeue(&ctx.fifo, &cmd) >= 0;) {
			switch (cmd.type) {
			case CMD_RECT:
				printf(
				    "rect x=%d y=%d w=%d h=%d\n",
				    cmd.rect.x,
				    cmd.rect.y,
				    cmd.rect.w,
				    cmd.rect.h
				);
				c = (Color) {
				    .r = cmd.rect.color[0],
				    .g = cmd.rect.color[1],
				    .b = cmd.rect.color[2],
				    .a = cmd.rect.color[3],
				};
				DrawRectangle(
				    cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h, c
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

#define MAX_ELEMS 128
#define MAX_CMDS  256

int ug_init(UgCtx *ctx)
{
	if (ctx == NULL) {
		return -1;
	}

	ug_tree_init(&ctx->tree, MAX_ELEMS);
	ug_fifo_init(&ctx->fifo, MAX_CMDS);

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
	ug_fifo_free(&ctx->fifo);

	return 0;
}

int ug_frame_begin(UgCtx *ctx) { return 0; }

int ug_frame_end(UgCtx *ctx) { return 0; }

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

int ug_div_begin(UgCtx *ctx, const char *name, UgRect div)
{
	if (ctx == NULL || name == NULL) {
		return -1;
	}

	UgId id = djb2(name);

	// add the element if it does not exist
	UgElem *c_elem = ug_cache_search(&ctx->cache, id);
	if (c_elem == NULL) {
		UgElem elem = {
		    .id   = id,
		    .type = ETYPE_DIV,
		    .rec  = (UgRect) {
			 .x = div.x,
			 .y = div.y,
			 .w = div.w >= 0 ? div.w : ctx->size.width,
			 .h = div.h >= 0 ? div.h : ctx->size.height,
                    }};
		uint32_t c_idx;
		c_elem = ug_cache_insert(&ctx->cache, &elem, &c_idx);
	}

	// FIXME: why save the id in the tree and not something more direct like
	//        the element pointer or the index into the cache vector?
	int div_node = ug_tree_add(&ctx->tree, c_elem->id, ctx->div_using);
	if (div_node < 0) {
		// do something
		printf("Error adding to tree\n");
	}
	ctx->div_using = div_node;

	//	printf(
	//	    "elem.rect: x=%d x=%d w=%d h=%d\n",
	//	    c_elem->rec.x,
	//	    c_elem->rec.y,
	//	    c_elem->rec.w,
	//	    c_elem->rec.h
	//	);
	UgCmd cmd = {
	    .type = CMD_RECT,
	    .rect =
		{
		    .x     = c_elem->rec.x,
		    .y     = c_elem->rec.y,
		    .w     = c_elem->rec.w,
		    .h     = c_elem->rec.h,
		    .color = {0xff, 0x00, 0x00, 0xff}, // red
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
