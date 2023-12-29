#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "raylib.h"
#include "ugui.h"

int main(void)
{
	UgCtx ctx;
	ug_init(&ctx);

	InitWindow(800, 450, "Ugui Test");

	// Main loop
	while (!WindowShouldClose()) {
		ug_begin_frame(&ctx);

		// drawing
		BeginDrawing();
		ClearBackground(BLACK);
		DrawText(
		    "Congrats! You created your first window!",
		    190,
		    200,
		    20,
		    LIGHTGRAY
		);
		EndDrawing();

		ug_end_frame(&ctx);
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

	ug_tree_init(&ctx->tree, 10);

	return 0;
}

int ug_destroy(UgCtx *ctx)
{
	if (ctx == NULL) {
		return -1;
	}

	ug_tree_destroy(&ctx->tree);

	return 0;
}
