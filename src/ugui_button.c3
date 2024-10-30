module ugui;

// draw a button, return the events on that button
fn ElemEvents! Ctx.button(&ctx, String label, Rect size)
{
	Id id = hash(label);

	Elem *parent = ctx.get_parent()!;
	Elem *c_elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	// 1. Fill the element fields
	// this resets the flags
	c_elem.type     = ETYPE_BUTTON;
	Color bg_color = uint_to_rgba(0x0000ffff);

	// if the element is new or the parent was updated then redo layout
	if (c_elem.flags.is_new || parent.flags.updated) {
		// 2. Layout
		c_elem.rect = ctx.position_element(parent, size, true);

		// TODO: 3. Fill the button specific fields
	}

	// TODO: Check for interactions
	// FIXME: this is not how normal buttons work, usually focus follows both
	//        mouse hover and mouse down
	c_elem.events = ctx.get_elem_events(c_elem);
	if (parent.flags.has_focus) {
		if (c_elem.events.mouse_hover) {
			c_elem.flags.has_focus = true;
			bg_color = uint_to_rgba(0x00ff00ff);
		}
	}

	// Draw the button
	Cmd cmd = {
	    .type = CMD_RECT,
	    .rect =	{
		    .rect  = c_elem.rect,
		    .color = bg_color,
		},
	};
	ctx.cmd_queue.enqueue(&cmd)!;

	return c_elem.events;
}
