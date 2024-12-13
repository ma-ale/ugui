module ugui;

import std::io;

/*       handle
 * +----+-----+---------------------+
 * |    |#####|                     |
 * +----+-----+---------------------+
 */
fn ElemEvents! Ctx.slider_hor(&ctx, String label, Rect size)
{
    Id id = label.hash();

	Elem *parent = ctx.get_parent()!;
	Elem *c_elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	// 1. Fill the element fields
	c_elem.type = ETYPE_SLIDER;

	// if the element is new or the parent was updated then redo layout
	if (c_elem.flags.is_new || parent.flags.updated) {
		// 2. Layout
		c_elem.bounds = ctx.position_element(parent, size, true);
		c_elem.slider.handle = Rect{
			.x = (short)(c_elem.bounds.x + (int)(c_elem.bounds.w*(1.0-0.25) * c_elem.slider.value)),
			.y = c_elem.bounds.y,
			.w = (short)(c_elem.bounds.w * 0.25),
			.h = c_elem.bounds.h,
		};
	}

	c_elem.events = ctx.get_elem_events(c_elem);
	if (parent.flags.has_focus && c_elem.events.mouse_hover) {
	    if (point_in_rect(ctx.input.mouse.pos, c_elem.slider.handle) && c_elem.events.mouse_hold) {
			short x = (short)clamp(ctx.input.mouse.pos.x - c_elem.slider.handle.w/2, c_elem.bounds.x, c_elem.bounds.x + c_elem.bounds.w - c_elem.slider.handle.w);
			float v = (float)(c_elem.slider.handle.x-c_elem.bounds.x) / (float)(c_elem.bounds.w-c_elem.slider.handle.w);
			c_elem.slider.handle.x = x;
			c_elem.slider.value = v;
			c_elem.events.update = true;
		}
	}

	// Draw the slider background and handle
	Color bg_color = uint_to_rgba(0x0000ffff);
	Color handle_color = uint_to_rgba(0x0ff000ff);
	ctx.push_rect(c_elem.bounds, bg_color)!;
	ctx.push_rect(c_elem.slider.handle, handle_color)!;

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
	Id id = label.hash();

	Elem *parent = ctx.get_parent()!;
	Elem *c_elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	// 1. Fill the element fields
	c_elem.type = ETYPE_SLIDER;

	// if the element is new or the parent was updated then redo layout
	if (c_elem.flags.is_new || parent.flags.updated) {
		// 2. Layout
		c_elem.bounds = ctx.position_element(parent, size, true);
		c_elem.slider.handle = Rect{
			.x = c_elem.bounds.x,
			.y = (short)(c_elem.bounds.y + (int)(c_elem.bounds.h*(1.0-0.25) * c_elem.slider.value)),
			.w = c_elem.bounds.w,
			.h = (short)(c_elem.bounds.h * 0.25),
		};
	}

	c_elem.events = ctx.get_elem_events(c_elem);
	if (parent.flags.has_focus && c_elem.events.mouse_hover) {
	    if (point_in_rect(ctx.input.mouse.pos, c_elem.slider.handle) && c_elem.events.mouse_hold) {
			short y = (short)clamp(ctx.input.mouse.pos.y - c_elem.slider.handle.h/2, c_elem.bounds.y, c_elem.bounds.y + c_elem.bounds.h - c_elem.slider.handle.h);
			float v = (float)(c_elem.slider.handle.y-c_elem.bounds.y) / (float)(c_elem.bounds.h-c_elem.slider.handle.h);
			c_elem.slider.handle.y = y;
			c_elem.slider.value = v;
			c_elem.events.update = true;
		}
	}

	// Draw the slider background and handle
	Color bg_color = uint_to_rgba(0x0000ffff);
	Color handle_color = uint_to_rgba(0x0ff000ff);
	ctx.push_rect(c_elem.bounds, bg_color)!;
	ctx.push_rect(c_elem.slider.handle, handle_color)!;

	return c_elem.events;
}
