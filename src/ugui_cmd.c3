module ugui;

// FIXME: is this really the best solution?
// "rect" is the bounding box of the element, which includes the border and the padding (so not just the content)
fn void! Ctx.push_rect(&ctx, Rect rect, Color color, bool do_border = false, bool do_padding = false, bool do_radius = false)
{
    // FIXME: this should be culled higher up, maybe
    if (rect.w <= 0 || rect.h <= 0) {
        return;
    }

	Rect border = ctx.style.border;
	Rect padding = ctx.style.padding;
	ushort radius = ctx.style.radius;
	Color border_color = ctx.style.brcolor;

	if (do_border) {
		Cmd cmd = {
			.type = CMD_RECT,
			.rect.rect = rect,
			.rect.color = border_color,
			.rect.radius = do_radius ? radius : 0,
		};
		ctx.cmd_queue.enqueue(&cmd)!;
	}

	Cmd cmd = {
		.type = CMD_RECT,
		.rect.rect = {
			.x = rect.x + (do_border ? border.x : 0) + (do_padding ? padding.x : 0),
			.y = rect.y + (do_border ? border.y : 0) + (do_padding ? padding.y : 0),
			.w = rect.w - (do_border ? border.x+border.w : 0) - (do_padding ? padding.x+padding.w : 0),
			.h = rect.h - (do_border ? border.y+border.h : 0) - (do_padding ? padding.y+padding.h : 0),
		},
		.rect.color = color,
		.rect.radius = do_radius ? radius : 0,
	};
	ctx.cmd_queue.enqueue(&cmd)!;
}

// TODO: add texture id
fn void! Ctx.push_sprite(&ctx, Rect bounds, Rect texture)
{
    Cmd cmd = {
		.type = CMD_SPRITE,
		.sprite.rect = bounds,
		.sprite.texture_rect = texture,
	};
	ctx.cmd_queue.enqueue(&cmd)!;
}
