module ugui;

import std::io;

fn void! Ctx.div_begin(&ctx, String label, Rect size)
{
	Id id = label.hash();

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
		if (c_elem.flags.is_new) {
			c_elem.div.children_bounds = c_elem.bounds;
			c_elem.div.color_bg = ctx.style.bgcolor;
			c_elem.div.scroll.can_x = false;
			c_elem.div.scroll.can_y = false;
			c_elem.div.scroll.value_x = 0;
			c_elem.div.scroll.value_y = 0;
		}

		// 3. Mark the element as updated
		c_elem.flags.updated = true;
		// 4. Fill the div fields
		c_elem.div.origin_c = Point{
		    .x = c_elem.bounds.x,
		    .y = c_elem.bounds.y,
		};
		c_elem.div.origin_r = c_elem.div.origin_c;
		c_elem.div.layout   = parent.div.layout;
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

	// check and draw scroll bars
	if (!rect_contains(c_elem.bounds, c_elem.div.children_bounds)) {
		Point cbc = {
			.x = c_elem.div.children_bounds.x + c_elem.div.children_bounds.w,
			.y = c_elem.div.children_bounds.y + c_elem.div.children_bounds.h,
		};
		Point bc = {
			.x = c_elem.bounds.x + c_elem.bounds.w,
			.y = c_elem.bounds.y + c_elem.bounds.h,
		};
		// vertical overflow, check and draw scroll bar
		if (cbc.y > bc.y && c_elem.div.scroll.can_y) {
			// set the scrollbar flag, is used in layout
			c_elem.div.scroll.on_y = true;

			Rect vslider = {
				.x = c_elem.bounds.x + c_elem.bounds.w - 10,
				.y = c_elem.bounds.y,
				.w = 10,
				.h = c_elem.bounds.h,
			};

			float vh = max((float)bc.y / cbc.y, (float)0.15);
			Rect vhandle = {
				.x = c_elem.bounds.x + c_elem.bounds.w - 10,
				.y = (short)(c_elem.bounds.y + (int)(c_elem.bounds.h*(1-vh) * c_elem.div.scroll.value_y)),
				.w = 10,
				.h = (short)(c_elem.bounds.h * vh),
			};

			c_elem.events = ctx.get_elem_events(c_elem);
			if (parent.flags.has_focus && c_elem.events.mouse_hover && c_elem.events.mouse_hold && point_in_rect(ctx.input.mouse.pos, vhandle)) {
				short y = (short)clamp(ctx.input.mouse.pos.y - vhandle.h/2, vslider.y, vslider.y + vslider.h - vhandle.h);
				vhandle.y = y;
				float v = (float)(vhandle.y-vslider.y) / (float)(vslider.h-vhandle.h);
				c_elem.div.scroll.value_y = v;
				c_elem.flags.updated = true;
				c_elem.div.origin_c = Point{
					.x = c_elem.bounds.x,
					.y = c_elem.bounds.y,
				};
				c_elem.div.origin_r = c_elem.div.origin_c;
			}

			Cmd scrl = {
				.type = CMD_RECT,
				.rect.rect = vslider,
				.rect.color = uint_to_rgba(0x999999ff),
			};
			ctx.cmd_queue.enqueue(&scrl)!;

			scrl.rect.rect = vhandle;
			scrl.rect.color = uint_to_rgba(0x9999ffff);
			ctx.cmd_queue.enqueue(&scrl)!;

		} else {
			c_elem.div.scroll.on_y = false;
		}
	}

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
