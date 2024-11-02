module ugui;

/*       handle
 * +----+-----+---------------------+
 * |    |#####|                     |
 * +----+-----+---------------------+
 */
fn ElemEvents! Ctx.slider_hor(&ctx, String label, Rect size)
{
    Id id = hash(label);

	Elem *parent = ctx.get_parent()!;
	Elem *c_elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	// 1. Fill the element fields
	c_elem.type = ETYPE_SLIDER;

	// if the element is new or the parent was updated then redo layout
	if (c_elem.flags.is_new || parent.flags.updated) {
		// 2. Layout
		c_elem.rect = ctx.position_element(parent, size, true);
		c_elem.slider.handle = Rect{
			.x = (short)(c_elem.rect.x + (int)(c_elem.rect.w * c_elem.slider.value)),
			.y = c_elem.rect.y,
			.w = (short)(c_elem.rect.w * 0.25),
			.h = c_elem.rect.h,
		};
	}

	c_elem.events = ctx.get_elem_events(c_elem);
	if (parent.flags.has_focus && c_elem.events.mouse_hover) {
	    if (point_in_rect(ctx.input.mouse.pos, c_elem.slider.handle) && c_elem.events.mouse_hold) {
			short x = (short)clamp(ctx.input.mouse.pos.x - c_elem.slider.handle.w/2, c_elem.rect.x, c_elem.rect.x + c_elem.rect.w - c_elem.slider.handle.w);
			float v = (float)(c_elem.slider.handle.x-c_elem.rect.x) / (float)(c_elem.rect.w-c_elem.slider.handle.w);
			c_elem.slider.handle.x = x;
			c_elem.slider.value = v;
			c_elem.events.update = true;
		}
	}

	// Draw the button
	Color bg_color = uint_to_rgba(0x0000ffff);
	Color handle_color = uint_to_rgba(0x0ff000ff);

	Cmd cmd = {
	    .type = CMD_RECT,
	    .rect =	{
		    .rect  = c_elem.rect,
		    .color = bg_color,
		},
	};
	ctx.cmd_queue.enqueue(&cmd)!;

	cmd = Cmd{
	    .type = CMD_RECT,
	    .rect =	{
		    .rect  = c_elem.slider.handle,
		    .color = handle_color,
		},
	};
	ctx.cmd_queue.enqueue(&cmd)!;

	return c_elem.events;
}

/*
 * +-+
 * | |
 * | |
 * +-+
 * |#| handle
 * |#|
 * +-+
 * | |
 * | |
 * +-+
 */
fn ElemEvents! Ctx.slider_ver(&ctx, String label, Rect size)
{
    Id id = hash(label);

	Elem *parent = ctx.get_parent()!;
	Elem *c_elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	// 1. Fill the element fields
	c_elem.type = ETYPE_SLIDER;

	// if the element is new or the parent was updated then redo layout
	if (c_elem.flags.is_new || parent.flags.updated) {
		// 2. Layout
		c_elem.rect = ctx.position_element(parent, size, true);
		c_elem.slider.handle = Rect{
			.x = c_elem.rect.x,
			.y = (short)(c_elem.rect.y + (int)(c_elem.rect.h * c_elem.slider.value)),
			.w = c_elem.rect.w,
			.h = (short)(c_elem.rect.h * 0.25),
		};
	}

	c_elem.events = ctx.get_elem_events(c_elem);
	if (parent.flags.has_focus && c_elem.events.mouse_hover) {
	    if (point_in_rect(ctx.input.mouse.pos, c_elem.slider.handle) && c_elem.events.mouse_hold) {
			short y = (short)clamp(ctx.input.mouse.pos.y - c_elem.slider.handle.h/2, c_elem.rect.y, c_elem.rect.y + c_elem.rect.h - c_elem.slider.handle.h);
			float v = (float)(c_elem.slider.handle.y-c_elem.rect.y) / (float)(c_elem.rect.h-c_elem.slider.handle.h);
			c_elem.slider.handle.y = y;
			c_elem.slider.value = v;
			c_elem.events.update = true;
		}
	}

	// Draw the button
	Color bg_color = uint_to_rgba(0x0000ffff);
	Color handle_color = uint_to_rgba(0x0ff000ff);

	Cmd cmd = {
	    .type = CMD_RECT,
	    .rect =	{
		    .rect  = c_elem.rect,
		    .color = bg_color,
		},
	};
	ctx.cmd_queue.enqueue(&cmd)!;

	cmd = Cmd{
	    .type = CMD_RECT,
	    .rect =	{
		    .rect  = c_elem.slider.handle,
		    .color = handle_color,
		},
	};
	ctx.cmd_queue.enqueue(&cmd)!;

	return c_elem.events;
}
