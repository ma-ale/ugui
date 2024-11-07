module ugui;


fn void! Ctx.div_begin(&ctx, String label, Rect size)
{
	Id id = hash(label);

	Elem *parent = ctx.get_parent()!;
	Elem* c_elem = ctx.get_elem(id)!;
	isz div_node = ctx.tree.add(id, ctx.active_div)!;
	ctx.active_div = div_node;

	// 1. Fill the element fields
	c_elem.type  = ETYPE_DIV;

	// do layout and update flags only if the element was updated
	if (c_elem.flags.is_new || parent.flags.updated) {
		// 2. layout the element
		c_elem.bounds = ctx.position_element(parent, size);

		// 3. Mark the element as updated
		c_elem.flags.updated = true;
		// 4. Fill the div fields
		c_elem.div.layout   = parent.div.layout;
		c_elem.div.origin_c = Point{
		    .x = c_elem.bounds.x,
		    .y = c_elem.bounds.y,
		};
		c_elem.div.color_bg = uint_to_rgba(0xff0000ff);
		c_elem.div.origin_r = c_elem.div.origin_c;
	}

	// Add the background to the draw stack
	Cmd cmd = {
	    .type = CMD_RECT,
	    .rect = {
		    .rect  = c_elem.bounds,
		    .color = c_elem.div.color_bg,
		},
	};
	ctx.cmd_queue.enqueue(&cmd)!;

	// TODO: check active
	// TODO: check resizeable

	// TODO: check scrollbars
	// if the bounds are outside of the view then allocate space for scrollbars
	DivLayout old_layout = c_elem.div.layout;
	c_elem.div.layout = LAYOUT_FLOATING;
	c_elem.div.layout = old_layout;

	if (parent.flags.has_focus) {
		if (point_in_rect(ctx.input.mouse.pos, c_elem.bounds)) {
			c_elem.flags.has_focus = true;
		}
	}

}

fn void! Ctx.div_end(&ctx)
{
	// the active_div returns to the parent of the current one
	ctx.active_div = ctx.tree.parentof(ctx.active_div)!;
}
